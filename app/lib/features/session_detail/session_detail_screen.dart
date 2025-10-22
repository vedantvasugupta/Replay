import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/session_models.dart';
import '../../state/chat_controller.dart';
import '../../state/session_detail_controller.dart';

class SessionDetailScreen extends ConsumerStatefulWidget {
  const SessionDetailScreen({required this.sessionId, super.key});

  final int sessionId;

  @override
  ConsumerState<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  bool _isEditingTitle = false;
  final _titleController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _updateTitle() async {
    if (_titleController.text.trim().isEmpty) return;

    // TODO: Call API to update title
    // For now, just close edit mode
    setState(() {
      _isEditingTitle = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(sessionDetailControllerProvider(widget.sessionId));
    final controller = ref.read(sessionDetailControllerProvider(widget.sessionId).notifier);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: detail.maybeWhen(
            data: (value) {
              final currentTitle = value.meta.title ?? 'Recording ${widget.sessionId}';
              if (!_isEditingTitle) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        currentTitle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () {
                        _titleController.text = currentTitle;
                        setState(() {
                          _isEditingTitle = true;
                        });
                      },
                      tooltip: 'Edit title',
                    ),
                  ],
                );
              } else {
                return Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _titleController,
                        autofocus: true,
                        style: const TextStyle(fontSize: 18),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Enter title',
                        ),
                        onSubmitted: (_) => _updateTitle(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.check, size: 20),
                      onPressed: _updateTitle,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () {
                        setState(() {
                          _isEditingTitle = false;
                        });
                      },
                    ),
                  ],
                );
              }
            },
            orElse: () => Text('Recording ${widget.sessionId}'),
          ),
          elevation: 0,
          bottom: TabBar(
            indicatorSize: TabBarIndicatorSize.label,
            indicatorPadding: const EdgeInsets.symmetric(horizontal: 16),
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.chat_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('Summary & Chat'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.article_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('Transcript'),
                  ],
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _SummaryAndChatView(sessionId: widget.sessionId, detail: detail),
            detail.when(
              data: (value) => _TranscriptView(transcript: value.transcript),
              loading: () => const Center(
                child: CircularProgressIndicator(color: Color(0xFF6366F1)),
              ),
              error: (error, _) => _ErrorView(onRetry: controller.refresh, message: error.toString()),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryAndChatView extends ConsumerStatefulWidget {
  const _SummaryAndChatView({required this.sessionId, required this.detail});

  final int sessionId;
  final AsyncValue<SessionDetail> detail;

  @override
  ConsumerState<_SummaryAndChatView> createState() => _SummaryAndChatViewState();
}

class _SummaryAndChatViewState extends ConsumerState<_SummaryAndChatView> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatControllerProvider(widget.sessionId));

    return widget.detail.when(
      data: (sessionDetail) {
        final summary = sessionDetail.summary;
        return Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.all(20),
                children: [
                  // Summary Section
                  if (summary != null) ...[
                    // Main summary card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.05),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.summarize_rounded,
                                  size: 20,
                                  color: Color(0xFF6366F1),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Summary',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.15,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            summary.summary,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.6,
                              color: Colors.white.withOpacity(0.9),
                              letterSpacing: 0.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Summary sections
                    if (summary.actionItems.isNotEmpty)
                      _SummarySection(
                        title: 'Action Items',
                        icon: Icons.task_alt_rounded,
                        items: summary.actionItems,
                        color: const Color(0xFF30D158),
                      ),
                    if (summary.timeline.isNotEmpty)
                      _SummarySection(
                        title: 'Timeline',
                        icon: Icons.timeline_rounded,
                        items: summary.timeline,
                        color: const Color(0xFF6366F1),
                      ),
                    if (summary.decisions.isNotEmpty)
                      _SummarySection(
                        title: 'Decisions',
                        icon: Icons.lightbulb_rounded,
                        items: summary.decisions,
                        color: const Color(0xFFFF9500),
                      ),

                    const SizedBox(height: 24),
                  ] else ...[
                    // No summary yet
                    Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.05),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.pending_outlined,
                            size: 48,
                            color: Colors.white.withOpacity(0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Summary not ready yet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'The AI is processing your recording',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Chat Section Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6366F1).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.chat_rounded,
                          size: 20,
                          color: Color(0xFF6366F1),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Ask Questions',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Chat messages
                  messages.when(
                    data: (items) {
                      if (items.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.05),
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 48,
                                color: Colors.white.withOpacity(0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No questions yet',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Ask questions about this recording below',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return Column(
                        children: items
                            .map((message) => _ChatMessageBubble(message: message))
                            .toList(),
                      );
                    },
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(color: Color(0xFF6366F1)),
                      ),
                    ),
                    error: (error, stack) => Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.05),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 48,
                            color: Colors.white.withOpacity(0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Unable to load chat',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Chat input at bottom
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF000000),
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: 'Ask about this recording...',
                          hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        style: const TextStyle(fontSize: 15),
                        minLines: 1,
                        maxLines: 4,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded),
                      color: Colors.white,
                      onPressed: () async {
                        final text = _controller.text.trim();
                        if (text.isEmpty) {
                          return;
                        }
                        _controller.clear();
                        await ref.read(chatControllerProvider(widget.sessionId).notifier).sendMessage(text);
                        // Scroll to bottom after sending
                        Future.delayed(const Duration(milliseconds: 100), () {
                          if (_scrollController.hasClients) {
                            _scrollController.animateTo(
                              _scrollController.position.maxScrollExtent,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            );
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: Color(0xFF6366F1)),
      ),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: Colors.white.withOpacity(0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load session',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryView extends StatelessWidget {
  const _SummaryView({required this.detail});

  final SessionDetail detail;

  @override
  Widget build(BuildContext context) {
    final summary = detail.summary;
    if (summary == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.pending_outlined,
                size: 64,
                color: Colors.white.withOpacity(0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'Summary not ready yet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'The AI is processing your recording',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Main summary card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.05),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.summarize_rounded,
                      size: 20,
                      color: Color(0xFF6366F1),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Summary',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.15,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                summary.summary,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: Colors.white.withOpacity(0.9),
                  letterSpacing: 0.25,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Sections
        if (summary.actionItems.isNotEmpty)
          _SummarySection(
            title: 'Action Items',
            icon: Icons.task_alt_rounded,
            items: summary.actionItems,
            color: const Color(0xFF30D158),
          ),
        if (summary.timeline.isNotEmpty)
          _SummarySection(
            title: 'Timeline',
            icon: Icons.timeline_rounded,
            items: summary.timeline,
            color: const Color(0xFF6366F1),
          ),
        if (summary.decisions.isNotEmpty)
          _SummarySection(
            title: 'Decisions',
            icon: Icons.lightbulb_rounded,
            items: summary.decisions,
            color: const Color(0xFFFF9500),
          ),
      ],
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({
    required this.title,
    required this.icon,
    required this.items,
    required this.color,
  });

  final String title;
  final IconData icon;
  final List<String> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...items.asMap().entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: Colors.white.withOpacity(0.9),
                        letterSpacing: 0.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TranscriptView extends StatelessWidget {
  const _TranscriptView({required this.transcript});

  final SessionTranscript? transcript;

  @override
  Widget build(BuildContext context) {
    if (transcript == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.pending_outlined,
                size: 64,
                color: Colors.white.withOpacity(0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'Transcript not ready yet',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'The AI is transcribing your recording',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.05),
            ),
          ),
          child: SelectableText(
            transcript!.text,
            style: TextStyle(
              fontSize: 15,
              height: 1.8,
              color: Colors.white.withOpacity(0.9),
              letterSpacing: 0.25,
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatTab extends ConsumerStatefulWidget {
  const _ChatTab({required this.sessionId});

  final int sessionId;

  @override
  ConsumerState<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends ConsumerState<_ChatTab> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatControllerProvider(widget.sessionId));
    return Column(
      children: [
        Expanded(
          child: messages.when(
            data: (items) => items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 64,
                            color: Colors.white.withOpacity(0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Start a conversation',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.7),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ask questions about this recording',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final message = items[index];
                      return _ChatMessageBubble(message: message);
                    },
                  ),
            loading: () => const Center(
              child: CircularProgressIndicator(color: Color(0xFF6366F1)),
            ),
            error: (error, stack) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: Colors.white.withOpacity(0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Unable to load chat',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      error.toString(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF000000),
            border: Border(
              top: BorderSide(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                    ),
                  ),
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Ask about this recording...',
                      hintStyle: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    style: const TextStyle(fontSize: 15),
                    minLines: 1,
                    maxLines: 4,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.send_rounded),
                  color: Colors.white,
                  onPressed: () async {
                    final text = _controller.text.trim();
                    if (text.isEmpty) {
                      return;
                    }
                    _controller.clear();
                    await ref.read(chatControllerProvider(widget.sessionId).notifier).sendMessage(text);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatMessageBubble extends StatelessWidget {
  const _ChatMessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final bubbleColor = isUser ? const Color(0xFF6366F1) : const Color(0xFF1E1E1E);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: isUser
              ? null
              : Border.all(
                  color: Colors.white.withOpacity(0.05),
                ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ChatMessageContent(message: message, isUser: isUser),
            if (!message.isThinking && message.citations != null && message.citations!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.format_quote_rounded,
                          size: 14,
                          color: Colors.white.withOpacity(0.6),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Citations',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.6),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...message.citations!.map(
                      (citation) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.5),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '[${citation.timestamp.toStringAsFixed(1)}s] ${citation.quote}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.7),
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChatMessageContent extends StatelessWidget {
  const _ChatMessageContent({required this.message, required this.isUser});

  final ChatMessage message;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final textColor = isUser ? Colors.white : Colors.white.withOpacity(0.9);

    if (message.isThinking) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: isUser ? Colors.white : const Color(0xFF6366F1),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Thinking...',
            style: TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: textColor.withOpacity(isUser ? 1 : 0.85),
              letterSpacing: 0.25,
            ),
          ),
        ],
      );
    }

    final sanitized = message.content.trim();
    if (sanitized.isEmpty) {
      return const SizedBox.shrink();
    }

    final paragraphs = sanitized.split(RegExp(r'\n\s*\n'));
    final style = TextStyle(
      fontSize: 15,
      height: 1.5,
      color: textColor,
      letterSpacing: 0.25,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < paragraphs.length; index++) ...[
          _FormattedParagraph(
            text: paragraphs[index],
            style: style,
            isUser: isUser,
          ),
          if (index != paragraphs.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _FormattedParagraph extends StatelessWidget {
  const _FormattedParagraph({required this.text, required this.style, required this.isUser});

  final String text;
  final TextStyle style;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const SizedBox.shrink();
    }

    final lines = trimmed.split('\n');
    final bulletPattern = RegExp(r'^[-*•]\s+');
    final bulletLines = lines.where((line) => line.trim().isNotEmpty).toList();
    final isBulletList =
        !isUser && bulletLines.isNotEmpty && bulletLines.every((line) => bulletPattern.hasMatch(line.trim()));

    if (isBulletList) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < bulletLines.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '•',
                  style: style.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    bulletLines[i].trim().replaceFirst(bulletPattern, ''),
                    style: style,
                  ),
                ),
              ],
            ),
            if (i != bulletLines.length - 1) const SizedBox(height: 6),
          ],
        ],
      );
    }

    return Text(
      trimmed,
      style: style,
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry, required this.message});

  final Future<void> Function() onRetry;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Something went wrong', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
