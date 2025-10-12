import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../providers/session_providers.dart';

class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(sessionDetailProvider(sessionId));
    final chat = ref.watch(chatHistoryProvider(sessionId));
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Session'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Summary'),
              Tab(text: 'Transcript'),
              Tab(text: 'Chat'),
            ],
          ),
        ),
        body: detail.when(
          data: (session) => TabBarView(
            children: [
              _SummaryTab(insights: session.insights),
              _TranscriptTab(transcript: session.transcript, segments: session.segments),
              _ChatTab(sessionId: sessionId, messages: chat),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(
            child: Text('Failed to load session: ${err.toString()}'),
          ),
        ),
      ),
    );
  }
}

class _SummaryTab extends StatelessWidget {
  const _SummaryTab({this.insights});

  final SessionInsights? insights;

  @override
  Widget build(BuildContext context) {
    if (insights == null) {
      return const Center(child: Text('Processing… check back soon.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Summary', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(insights!.summary),
        const SizedBox(height: 16),
        _InsightSection(title: 'Action items', items: insights!.actionItems),
        _InsightSection(title: 'Timeline', items: insights!.timeline),
        _InsightSection(title: 'Decisions', items: insights!.decisions),
      ],
    );
  }
}

class _TranscriptTab extends StatelessWidget {
  const _TranscriptTab({this.transcript, this.segments});

  final String? transcript;
  final List<Map<String, dynamic>>? segments;

  @override
  Widget build(BuildContext context) {
    if (transcript == null) {
      return const Center(child: Text('Transcript not available yet.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: segments?.length ?? 1,
      itemBuilder: (context, index) {
        if (segments == null) {
          return Text(transcript!);
        }
        final segment = segments![index];
        final speaker = segment['speaker'] ?? 'Speaker';
        final text = segment['text'] ?? '';
        final ts = segment['start']?.toString();
        return ListTile(
          title: Text(text),
          subtitle: Text('$speaker · $ts'),
        );
      },
    );
  }
}

class _ChatTab extends ConsumerStatefulWidget {
  const _ChatTab({required this.sessionId, required this.messages});

  final String sessionId;
  final List<ChatMessage> messages;

  @override
  ConsumerState<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends ConsumerState<_ChatTab> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    _controller.clear();
    await ref.read(chatHistoryProvider(widget.sessionId).notifier).send(text);
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.messages;
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final message = messages[index];
              final isUser = message.role == 'user';
              return Align(
                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isUser
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment:
                        isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.content,
                        style: TextStyle(
                          color: isUser
                              ? Theme.of(context).colorScheme.onPrimary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (!isUser && message.citations != null)
                        ...message.citations!.map(
                          (c) => Text(
                            '${c.quote} (${c.t})',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(hintText: 'Ask about this meeting'),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _sending ? null : _send,
                child: _sending
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InsightSection extends StatelessWidget {
  const _InsightSection({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• '),
                  Expanded(child: Text(item)),
                ],
              ),
            )),
        const SizedBox(height: 16),
      ],
    );
  }
}
