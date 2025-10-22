enum SessionStatus { uploaded, processing, ready, failed }

SessionStatus sessionStatusFromString(String value) {
  return SessionStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => SessionStatus.processing,
  );
}

class SessionListItem {
  SessionListItem({
    required this.id,
    required this.status,
    required this.createdAt,
    this.durationSec,
    this.title,
  });

  final int id;
  final SessionStatus status;
  final DateTime createdAt;
  final int? durationSec;
  final String? title;

  factory SessionListItem.fromJson(Map<String, dynamic> json) {
    return SessionListItem(
      id: json['id'] as int,
      status: sessionStatusFromString(json['status'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      durationSec: json['durationSec'] as int?,
      title: json['title'] as String?,
    );
  }
}

class TranscriptSegment {
  TranscriptSegment({required this.start, required this.end, required this.text});

  final double start;
  final double end;
  final String text;

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) {
    return TranscriptSegment(
      start: (json['start'] as num).toDouble(),
      end: (json['end'] as num).toDouble(),
      text: json['text'] as String,
    );
  }
}

class SessionTranscript {
  SessionTranscript({required this.text, required this.segments});

  final String text;
  final List<TranscriptSegment> segments;

  factory SessionTranscript.fromJson(Map<String, dynamic> json) {
    final segmentsJson = json['segments'] as List<dynamic>? ?? <dynamic>[];
    return SessionTranscript(
      text: json['text'] as String,
      segments:
          segmentsJson.map((segment) => TranscriptSegment.fromJson(segment as Map<String, dynamic>)).toList(),
    );
  }
}

class SessionSummary {
  SessionSummary({
    required this.summary,
    required this.actionItems,
    required this.timeline,
    required this.decisions,
  });

  final String summary;
  final List<String> actionItems;
  final List<String> timeline;
  final List<String> decisions;

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    return SessionSummary(
      summary: json['summary'] as String,
      actionItems: (json['actionItems'] as List<dynamic>? ?? []).cast<String>(),
      timeline: (json['timeline'] as List<dynamic>? ?? []).cast<String>(),
      decisions: (json['decisions'] as List<dynamic>? ?? []).cast<String>(),
    );
  }
}

class SessionMeta {
  SessionMeta({
    required this.id,
    required this.status,
    required this.createdAt,
    this.durationSec,
    this.title,
  });

  final int id;
  final SessionStatus status;
  final DateTime createdAt;
  final int? durationSec;
  final String? title;

  factory SessionMeta.fromJson(Map<String, dynamic> json) {
    return SessionMeta(
      id: json['id'] as int,
      status: sessionStatusFromString(json['status'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      durationSec: json['durationSec'] as int?,
      title: json['title'] as String?,
    );
  }
}

class SessionDetail {
  SessionDetail({required this.meta, this.summary, this.transcript});

  final SessionMeta meta;
  final SessionSummary? summary;
  final SessionTranscript? transcript;

  factory SessionDetail.fromJson(Map<String, dynamic> json) {
    return SessionDetail(
      meta: SessionMeta.fromJson(json['meta'] as Map<String, dynamic>),
      summary:
          json['summary'] != null ? SessionSummary.fromJson(json['summary'] as Map<String, dynamic>) : null,
      transcript: json['transcript'] != null
          ? SessionTranscript.fromJson(json['transcript'] as Map<String, dynamic>)
          : null,
    );
  }
}

class ChatMessage {
  ChatMessage({
    required this.role,
    required this.content,
    required this.createdAt,
    this.citations,
    this.isThinking = false,
  });

  final String role;
  final String content;
  final DateTime createdAt;
  final List<ChatCitation>? citations;
  final bool isThinking;
}

class ChatResponse {
  ChatResponse({required this.assistantMessage, required this.citations});

  final String assistantMessage;
  final List<ChatCitation> citations;

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    final citationsJson = json['citations'] as List<dynamic>? ?? <dynamic>[];
    return ChatResponse(
      assistantMessage: json['assistantMessage'] as String,
      citations: citationsJson.map((item) => ChatCitation.fromJson(item as Map<String, dynamic>)).toList(),
    );
  }
}

class ChatCitation {
  ChatCitation({required this.timestamp, required this.quote});

  final double timestamp;
  final String quote;

  factory ChatCitation.fromJson(Map<String, dynamic> json) {
    return ChatCitation(
      timestamp: (json['timestamp'] as num).toDouble(),
      quote: json['quote'] as String,
    );
  }
}
