class AuthTokens {
  AuthTokens({required this.access, required this.refresh});

  final String access;
  final String refresh;

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
        access: json['access'] as String,
        refresh: json['refresh'] as String,
      );
}

class SessionSummary {
  SessionSummary({
    required this.id,
    required this.createdAt,
    required this.status,
    this.durationSec,
  });

  final String id;
  final DateTime createdAt;
  final String status;
  final int? durationSec;

  factory SessionSummary.fromJson(Map<String, dynamic> json) => SessionSummary(
        id: json['id'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        status: json['status'] as String,
        durationSec: json['durationSec'] as int?,
      );
}

class SessionInsights {
  SessionInsights({
    required this.summary,
    required this.actionItems,
    required this.timeline,
    required this.decisions,
  });

  final String summary;
  final List<String> actionItems;
  final List<String> timeline;
  final List<String> decisions;

  factory SessionInsights.fromJson(Map<String, dynamic> json) => SessionInsights(
        summary: json['summary'] as String,
        actionItems: List<String>.from(json['action_items'] as List? ?? []),
        timeline: List<String>.from(json['timeline'] as List? ?? []),
        decisions: List<String>.from(json['decisions'] as List? ?? []),
      );
}

class SessionDetail {
  SessionDetail({
    required this.meta,
    this.transcript,
    this.segments,
    this.insights,
  });

  final SessionSummary meta;
  final String? transcript;
  final List<Map<String, dynamic>>? segments;
  final SessionInsights? insights;

  factory SessionDetail.fromJson(Map<String, dynamic> json) => SessionDetail(
        meta: SessionSummary.fromJson(json['meta'] as Map<String, dynamic>),
        transcript: json['transcript'] as String?,
        segments: (json['segments'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        insights: json['summary'] == null
            ? null
            : SessionInsights.fromJson(json['summary'] as Map<String, dynamic>),
      );
}

class MessageCitation {
  MessageCitation({required this.t, required this.quote});

  final String t;
  final String quote;

  factory MessageCitation.fromJson(Map<String, dynamic> json) => MessageCitation(
        t: json['t'] as String,
        quote: json['quote'] as String,
      );
}

class ChatMessage {
  ChatMessage({required this.role, required this.content, this.citations});

  final String role;
  final String content;
  final List<MessageCitation>? citations;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'] as String,
        content: json['content'] as String,
        citations: (json['citations'] as List?)
            ?.map((e) => MessageCitation.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
