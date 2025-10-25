from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

import google.generativeai as genai
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

        # Configure the SDK with API key
        if self.api_key:
            genai.configure(api_key=self.api_key)

    async def transcribe_and_analyze(self, audio_path: Path, mime_type: str) -> dict[str, Any]:
        """Transcribe audio and generate summary + title in a single API call using File API."""
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

        # Combined prompt for transcription, summary, and title generation with speaker diarization
        prompt = """Transcribe this meeting audio with speaker identification, then analyze it.

Identify different speakers in the audio and label them as Speaker 1, Speaker 2, etc.

Return your response in the following JSON format:
{
  "transcript": "full verbatim transcription with speaker labels, e.g., 'Speaker 1: Hello. Speaker 2: Hi there.'",
  "speakers": [
    {
      "id": "Speaker 1",
      "characteristics": "brief description of voice (e.g., male, deep voice)"
    },
    {
      "id": "Speaker 2",
      "characteristics": "brief description of voice (e.g., female, higher pitch)"
    }
  ],
  "utterances": [
    {
      "speaker": "Speaker 1",
      "text": "the text spoken",
      "start_time": "approximate start time in seconds or description like 'beginning', 'middle', 'end'"
    }
  ],
  "title": "brief descriptive title (max 6 words)",
  "summary": "2-3 sentence overview of the meeting",
  "action_items": ["list", "of", "action", "items"],
  "timeline": ["chronological", "key", "events"],
  "decisions": ["decisions", "made"]
}

Important: Return ONLY valid JSON, no markdown formatting. If only one speaker is detected, still use the Speaker 1 format."""

        uploaded_file = None
        try:
            # Upload file to Gemini (no memory spike - streamed upload)
            file_size_mb = audio_path.stat().st_size / (1024 * 1024)
            logger.info(f"Uploading {file_size_mb:.1f}MB audio file to Gemini File API: {audio_path.name}")

            uploaded_file = genai.upload_file(path=str(audio_path), mime_type=mime_type)
            logger.info(f"File uploaded successfully: {uploaded_file.name} (URI: {uploaded_file.uri})")

            # Wait for file to be processed by Gemini
            import time
            while uploaded_file.state.name == "PROCESSING":
                logger.info("Waiting for Gemini to process uploaded file...")
                time.sleep(2)
                uploaded_file = genai.get_file(uploaded_file.name)

            if uploaded_file.state.name == "FAILED":
                raise Exception(f"Gemini file processing failed: {uploaded_file.state}")

            logger.info(f"File ready for transcription: {uploaded_file.name}")

            # Generate content using the uploaded file reference
            model = genai.GenerativeModel(self.model)
            response = model.generate_content(
                [uploaded_file, prompt],
                generation_config=genai.GenerationConfig(
                    response_mime_type="application/json",
                ),
                request_options={"timeout": 600}  # 10 minutes for generation
            )

            text = response.text

        finally:
            # Clean up uploaded file
            if uploaded_file:
                try:
                    logger.info(f"Deleting uploaded file: {uploaded_file.name}")
                    genai.delete_file(uploaded_file.name)
                except Exception as e:
                    logger.warning(f"Failed to delete uploaded file {uploaded_file.name}: {e}")

        # Parse JSON response
        try:
            import json
            result = json.loads(text)

            # Extract speaker information
            speakers = result.get("speakers", [])
            utterances = result.get("utterances", [])

            # Build segments from utterances if available with backward-compatible format
            segments = []
            if utterances:
                total_duration = max(30.0, len(result.get("transcript", text).split()) / 2.0)
                segment_duration = total_duration / max(len(utterances), 1)

                for idx, utterance in enumerate(utterances):
                    # Calculate approximate numeric timestamps for backward compatibility
                    start_time = idx * segment_duration
                    end_time = (idx + 1) * segment_duration

                    segments.append({
                        "speaker": utterance.get("speaker", "Unknown"),
                        "text": utterance.get("text", ""),
                        "start": start_time,
                        "end": end_time,
                        "start_time": utterance.get("start_time", f"{int(start_time)}s"),
                    })
            else:
                # Fallback to single segment
                segments = [{"start": 0.0, "end": max(30.0, len(result.get("transcript", text).split()) / 2.0), "text": result.get("transcript", text)}]

            return {
                "text": result.get("transcript", text),
                "segments": segments,
                "speakers": speakers,
                "title": result.get("title", "Untitled Recording"),
                "summary": {
                    "summary": result.get("summary", ""),
                    "action_items": result.get("action_items", []),
                    "timeline": result.get("timeline", []),
                    "decisions": result.get("decisions", []),
                },
            }
        except Exception as e:
            # Fallback if JSON parsing fails
            print(f"[GeminiService] Failed to parse JSON response: {e}")
            return {
                "text": text,
                "segments": [{"start": 0.0, "end": max(30.0, len(text.split()) / 2.0), "text": text}],
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
            "Answer the user's question using the supplied transcript and our conversation history. "
            "Quote the relevant excerpts with timestamps if supplied.\n\n"
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
