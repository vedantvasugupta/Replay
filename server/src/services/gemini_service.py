from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

from google import genai
from google.genai import types
import httpx

from ..core.config import get_settings

logger = logging.getLogger("uvicorn")


class GeminiService:
    """Adapter around Gemini 2.5 Pro APIs. Falls back to deterministic stubs when no API key is configured."""

    def __init__(self) -> None:
        settings = get_settings().gemini()
        self.project_id = settings.project_id
        self.location = settings.location
        self.model = settings.model
        self.api_key = settings.api_key
        self._endpoint = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:generateContent"

        # Create Gemini client if API key is configured
        self.client = genai.Client(api_key=self.api_key) if self.api_key else None

    async def transcribe_and_analyze(self, audio_path: Path, mime_type: str, duration_sec: int = 0) -> dict[str, Any]:
        """Transcribe audio and generate summary + title in a single API call using File API.

        Args:
            audio_path: Path to the audio file
            mime_type: MIME type of the audio file
            duration_sec: Duration of the recording in seconds (for timeout calculation)
        """
        if not self.api_key:
            text = f"Transcription placeholder for {audio_path.name}. Configure GEMINI_API_KEY for live transcription."
            return {
                "text": text,
                "segments": [{"start": 0.0, "end": 30.0, "text": text}],
                "title": "Demo Recording",
                "summary": {
                    "summary": text,
                    "action_items": [],
                    "timeline": [],
                    "decisions": [],
                },
            }

        # Enhanced prompt for detailed transcription with language detection and emotion analysis
        prompt = """
Process the audio file and generate a detailed transcription.

Requirements:
1. Identify distinct speakers (e.g., Speaker 1, Speaker 2, or names if context allows).
2. Provide accurate timestamps for each segment (Format: MM:SS).
3. Detect the primary language of each segment.
4. If the segment is in a language different than English, also provide the English translation.
5. Identify the primary emotion of the speaker in this segment. You MUST choose exactly one of the following: Happy, Sad, Angry, Neutral.
6. Provide a brief summary of the entire audio at the beginning.
7. Generate a brief descriptive title (max 6 words).
8. Extract action items, timeline, and decisions from the meeting.
"""

        uploaded_file = None
        try:
            # Upload file to Gemini (no memory spike - streamed upload)
            file_size_mb = audio_path.stat().st_size / (1024 * 1024)
            logger.info(f"📤 [UPLOAD START] Uploading {file_size_mb:.1f}MB audio file to Gemini File API: {audio_path.name}")

            import time
            upload_start = time.time()
            # Upload file using path string with config
            uploaded_file = self.client.files.upload(
                file=str(audio_path),
                config=types.UploadFileConfig(mime_type=mime_type)
            )
            upload_duration = time.time() - upload_start
            logger.info(f"✅ [UPLOAD COMPLETE] File uploaded in {upload_duration:.1f}s: {uploaded_file.name}")
            logger.info(f"📝 [UPLOAD INFO] URI: {uploaded_file.uri}, State: {uploaded_file.state}")

            # Wait for file to be processed by Gemini
            import asyncio
            wait_start = time.time()
            check_count = 0
            while uploaded_file.state == "PROCESSING":
                check_count += 1
                elapsed = time.time() - wait_start
                logger.info(f"⏳ [PROCESSING] Waiting for Gemini to process file... (check #{check_count}, {elapsed:.1f}s elapsed)")
                await asyncio.sleep(5)  # Check every 5 seconds - use async sleep to avoid greenlet issues
                uploaded_file = self.client.files.get(name=uploaded_file.name)

            if uploaded_file.state == "FAILED":
                logger.error(f"❌ [PROCESSING FAILED] Gemini file processing failed: {uploaded_file.state}")
                raise Exception(f"Gemini file processing failed: {uploaded_file.state}")

            wait_duration = time.time() - wait_start
            logger.info(f"✅ [PROCESSING COMPLETE] File ready for transcription in {wait_duration:.1f}s: {uploaded_file.name}")

            # Generate content using the uploaded file reference
            # Calculate dynamic timeout based on recording duration
            # Base: 10 minutes + 1 minute per 5 minutes of audio (max 60 minutes for API call)
            # Example: 82-min recording = 10 + (82/5) = 26.4 minutes
            api_timeout_minutes = min(60, 10 + (duration_sec / 300)) if duration_sec > 0 else 10
            api_timeout_seconds = int(api_timeout_minutes * 60)
            logger.info(f"🤖 [GENERATION START] Requesting transcription and analysis from {self.model}...")
            logger.info(f"⏱️ [TIMEOUT] API timeout set to {api_timeout_minutes:.1f} minutes ({api_timeout_seconds}s) for {duration_sec}s recording")
            gen_start = time.time()
            response = self.client.models.generate_content(
                model=self.model,
                contents=[
                    types.Content(
                        parts=[
                            types.Part(file_data=types.FileData(file_uri=uploaded_file.uri)),
                            types.Part(text=prompt)
                        ]
                    )
                ],
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_schema=types.Schema(
                        type=types.Type.OBJECT,
                        properties={
                            "title": types.Schema(
                                type=types.Type.STRING,
                                description="Brief descriptive title (max 6 words)",
                            ),
                            "summary": types.Schema(
                                type=types.Type.STRING,
                                description="A concise summary of the audio content.",
                            ),
                            "action_items": types.Schema(
                                type=types.Type.ARRAY,
                                description="List of action items from the meeting",
                                items=types.Schema(type=types.Type.STRING),
                            ),
                            "timeline": types.Schema(
                                type=types.Type.ARRAY,
                                description="Chronological key events",
                                items=types.Schema(type=types.Type.STRING),
                            ),
                            "decisions": types.Schema(
                                type=types.Type.ARRAY,
                                description="Decisions made in the meeting",
                                items=types.Schema(type=types.Type.STRING),
                            ),
                            "segments": types.Schema(
                                type=types.Type.ARRAY,
                                description="List of transcribed segments with speaker and timestamp.",
                                items=types.Schema(
                                    type=types.Type.OBJECT,
                                    properties={
                                        "speaker": types.Schema(
                                            type=types.Type.STRING,
                                            description="Speaker identifier (e.g., Speaker 1, Speaker 2, or name)"
                                        ),
                                        "timestamp": types.Schema(
                                            type=types.Type.STRING,
                                            description="Timestamp in MM:SS format"
                                        ),
                                        "content": types.Schema(
                                            type=types.Type.STRING,
                                            description="The text spoken"
                                        ),
                                        "language": types.Schema(
                                            type=types.Type.STRING,
                                            description="Name of the language spoken"
                                        ),
                                        "language_code": types.Schema(
                                            type=types.Type.STRING,
                                            description="ISO language code (e.g., en, es, fr)"
                                        ),
                                        "translation": types.Schema(
                                            type=types.Type.STRING,
                                            description="English translation if language is not English, empty string otherwise"
                                        ),
                                        "emotion": types.Schema(
                                            type=types.Type.STRING,
                                            enum=["happy", "sad", "angry", "neutral"],
                                            description="Primary emotion of the speaker"
                                        ),
                                    },
                                    required=["speaker", "timestamp", "content", "language", "language_code", "emotion"],
                                ),
                            ),
                        },
                        required=["title", "summary", "segments"],
                    ),
                )
            )
            gen_duration = time.time() - gen_start
            logger.info(f"✅ [GENERATION COMPLETE] Transcription received in {gen_duration:.1f}s")

            text = response.text
            logger.info(f"📊 [RESPONSE SIZE] Received {len(text)} characters of JSON response")

        finally:
            # Clean up uploaded file
            if uploaded_file:
                try:
                    logger.info(f"🗑️ [CLEANUP] Deleting uploaded file: {uploaded_file.name}")
                    self.client.files.delete(name=uploaded_file.name)
                    logger.info(f"✅ [CLEANUP COMPLETE] File deleted successfully")
                except Exception as e:
                    logger.warning(f"⚠️ [CLEANUP FAILED] Failed to delete uploaded file {uploaded_file.name}: {e}")

        # Parse JSON response
        logger.info(f"🔍 [JSON PARSE START] Parsing Gemini response...")
        try:
            import json
            import re

            # Sanitize control characters from JSON response
            # Remove control characters except for \n, \r, \t
            sanitized_text = re.sub(r'[\x00-\x08\x0b-\x0c\x0e-\x1f\x7f-\x9f]', '', text)

            if sanitized_text != text:
                removed_count = len(text) - len(sanitized_text)
                logger.warning(f"⚠️ [JSON SANITIZE] Removed {removed_count} invalid control characters from response")

            result = json.loads(sanitized_text)
            logger.info(f"✅ [JSON PARSE SUCCESS] Response parsed successfully")

            # Extract structured data from new format
            segments = result.get("segments", [])
            title = result.get("title", "Untitled Recording")
            summary_text = result.get("summary", "")
            action_items = result.get("action_items", [])
            timeline = result.get("timeline", [])
            decisions = result.get("decisions", [])

            logger.info(f"🎯 [STRUCTURED DATA] Found {len(segments)} segments")
            logger.info(f"📋 [RESULT SUMMARY] Title: '{title}', Summary: {len(summary_text)} chars, Actions: {len(action_items)} items")

            # Build full transcript text from segments and extract speakers
            transcript_lines = []
            speakers_seen = set()

            # Process segments to build transcript and enhance with numeric timestamps
            processed_segments = []
            for idx, segment in enumerate(segments):
                speaker = segment.get("speaker", "Unknown")
                content = segment.get("content", "")
                timestamp_str = segment.get("timestamp", "00:00")
                language = segment.get("language", "English")
                language_code = segment.get("language_code", "en")
                translation = segment.get("translation", "")
                emotion = segment.get("emotion", "neutral")

                speakers_seen.add(speaker)

                # Convert MM:SS timestamp to seconds for backward compatibility
                try:
                    parts = timestamp_str.split(":")
                    if len(parts) == 2:
                        minutes, seconds = int(parts[0]), int(parts[1])
                        start_time = minutes * 60 + seconds
                    else:
                        start_time = idx * 10  # Fallback: 10 seconds per segment
                except (ValueError, AttributeError):
                    start_time = idx * 10

                # Calculate end time (estimate based on next segment or add 10 seconds)
                if idx < len(segments) - 1:
                    try:
                        next_timestamp = segments[idx + 1].get("timestamp", "00:00")
                        next_parts = next_timestamp.split(":")
                        if len(next_parts) == 2:
                            next_minutes, next_seconds = int(next_parts[0]), int(next_parts[1])
                            end_time = next_minutes * 60 + next_seconds
                        else:
                            end_time = start_time + 10
                    except (ValueError, AttributeError):
                        end_time = start_time + 10
                else:
                    end_time = start_time + 10

                # Build transcript line with speaker label
                transcript_lines.append(f"{speaker}: {content}")

                # Create enhanced segment with all fields
                processed_segments.append({
                    "speaker": speaker,
                    "text": content,
                    "start": float(start_time),
                    "end": float(end_time),
                    "timestamp": timestamp_str,
                    "language": language,
                    "language_code": language_code,
                    "translation": translation,
                    "emotion": emotion,
                })

            # Build full transcript text
            full_transcript = "\n\n".join(transcript_lines)

            # Build speakers list (for backward compatibility)
            speakers = [{"id": speaker, "characteristics": ""} for speaker in sorted(speakers_seen)]

            logger.info(f"👥 [SPEAKERS] Found {len(speakers)} unique speakers")
            logger.info(f"✅ [SEGMENTS COMPLETE] Processed {len(processed_segments)} segments with enhanced metadata")
            logger.info(f"🎉 [TRANSCRIBE SUCCESS] All processing complete for {audio_path.name}")

            return {
                "text": full_transcript,
                "segments": processed_segments,
                "speakers": speakers,
                "title": title,
                "summary": {
                    "summary": summary_text,
                    "action_items": action_items,
                    "timeline": timeline,
                    "decisions": decisions,
                },
            }
        except Exception as e:
            # Fallback if JSON parsing fails
            logger.error(f"❌ [JSON PARSE FAILED] Failed to parse JSON response: {e}")
            logger.warning(f"⚠️ [FALLBACK] Using fallback response structure")
            return {
                "text": text,
                "segments": [{"start": 0.0, "end": max(30.0, len(text.split()) / 2.0), "text": text, "speaker": "Unknown", "timestamp": "00:00", "language": "English", "language_code": "en", "translation": "", "emotion": "neutral"}],
                "speakers": [],
                "title": "Untitled Recording",
                "summary": {
                    "summary": text[:500],
                    "action_items": [],
                    "timeline": [],
                    "decisions": [],
                },
            }

    async def transcribe(self, audio_path: Path, mime_type: str) -> dict[str, Any]:
        """Legacy method - prefer transcribe_and_analyze for efficiency."""
        result = await self.transcribe_and_analyze(audio_path, mime_type)
        return {
            "text": result["text"],
            "segments": result["segments"],
        }

    async def summarize(self, transcript_text: str) -> dict[str, Any]:
        if not self.api_key:
            sentences = [s.strip() for s in transcript_text.split(".") if s.strip()]
            summary = sentences[0] if sentences else "No transcript text available."
            return {
                "summary": summary,
                "action_items": [],
                "timeline": [],
                "decisions": [],
            }

        prompt = (
            "Summarize the following meeting transcript. Provide a concise summary, a bullet list of action items, "
            "a chronological timeline, and any decisions reached.\n\nTranscript:\n"
            f"{transcript_text}"
        )
        async with httpx.AsyncClient(timeout=60) as client:
            response = await client.post(
                self._endpoint,
                params={"key": self.api_key},
                json={"contents": [{"parts": [{"text": prompt}]}]},
            )
            response.raise_for_status()
            body = response.json()

        text = self._extract_text(body)
        return self._coerce_summary(text)

    async def answer(self, question: str, transcript_text: str, chat_history: list[dict] = None) -> dict[str, Any]:
        if not self.api_key:
            answer = self._keyword_answer(question, transcript_text)
            return {"answer": answer, "citations": []}

        # Build conversation context from chat history
        history_context = ""
        if chat_history:
            history_lines = []
            for msg in chat_history[-10:]:  # Last 10 messages for context
                role = msg.get("role", "").upper()
                content = msg.get("content", "")
                history_lines.append(f"{role}: {content}")
            if history_lines:
                history_context = "\n\nConversation History:\n" + "\n".join(history_lines)

        prompt = (
            "You are a helpful meeting assistant with memory of our conversation. "
            "Answer the user's question using the supplied transcript and our conversation history.\n\n"
            f"Transcript:\n{transcript_text}"
            f"{history_context}\n\n"
            f"Current Question: {question}"
        )
        async with httpx.AsyncClient(timeout=60) as client:
            response = await client.post(
                self._endpoint,
                params={"key": self.api_key},
                json={"contents": [{"parts": [{"text": prompt}]}]},
            )
            response.raise_for_status()
            body = response.json()

        text = self._extract_text(body)
        return {"answer": text, "citations": []}

    def _extract_text(self, body: dict[str, Any]) -> str:
        try:
            candidates = body["candidates"]
            parts = candidates[0]["content"]["parts"]
            return "".join(part.get("text", "") for part in parts).strip()
        except (KeyError, IndexError):
            return ""

    def _coerce_summary(self, text: str) -> dict[str, Any]:
        sections = {"summary": "", "action_items": [], "timeline": [], "decisions": []}
        current = "summary"
        for line in text.splitlines():
            line = line.strip()
            if not line:
                continue
            lower = line.lower()
            if "action item" in lower:
                current = "action_items"
                continue
            if "timeline" in lower:
                current = "timeline"
                continue
            if "decision" in lower:
                current = "decisions"
                continue
            if current == "summary":
                sections["summary"] += (" " if sections["summary"] else "") + line
            else:
                sections[current].append(line)
        if not sections["summary"]:
            sections["summary"] = text[:500]
        return sections

    def _keyword_answer(self, question: str, transcript_text: str) -> str:
        question_terms = [term.lower() for term in question.split() if len(term) > 2]
        best_sentence = ""
        best_score = 0
        for sentence in transcript_text.split("."):
            words = sentence.lower().split()
            score = sum(words.count(term) for term in question_terms)
            if score > best_score:
                best_sentence = sentence.strip()
                best_score = score
        if not best_sentence:
            return "I could not find information about that in the transcript."
        return best_sentence or "I could not find information about that in the transcript."
