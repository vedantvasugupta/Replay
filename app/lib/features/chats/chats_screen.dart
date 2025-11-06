import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/session_models.dart';
import '../../state/session_list_controller.dart';
import '../home/widgets/session_card.dart';

enum DateCategory { today, yesterday, thisWeek, thisMonth, older }

class _DateGroup {
  _DateGroup({
    required this.category,
    required this.label,
    required this.sessions,
    this.isExpanded = true,
  });

  final DateCategory category;
  final String label;
  final List<SessionListItem> sessions;
  bool isExpanded;
}

class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  final Map<DateCategory, bool> _expandedSections = {
    DateCategory.today: true,
    DateCategory.yesterday: true,
    DateCategory.thisWeek: true,
    DateCategory.thisMonth: true,
    DateCategory.older: true,
  };

  @override
  void initState() {
    super.initState();
    // Auto-refresh every 10 seconds to check for completed transcriptions
    Future.delayed(Duration.zero, () {
      if (mounted) {
        _startAutoRefresh();
      }
    });
  }

  DateCategory _categorizeDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
    final thisMonthStart = DateTime(now.year, now.month, 1);

    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly.isAtSameMomentAs(today)) {
      return DateCategory.today;
    } else if (dateOnly.isAtSameMomentAs(yesterday)) {
      return DateCategory.yesterday;
    } else if (dateOnly.isAfter(thisWeekStart) || dateOnly.isAtSameMomentAs(thisWeekStart)) {
      return DateCategory.thisWeek;
    } else if (dateOnly.isAfter(thisMonthStart) || dateOnly.isAtSameMomentAs(thisMonthStart)) {
      return DateCategory.thisMonth;
    } else {
      return DateCategory.older;
    }
  }

  String _getCategoryLabel(DateCategory category) {
    switch (category) {
      case DateCategory.today:
        return 'Today';
      case DateCategory.yesterday:
        return 'Yesterday';
      case DateCategory.thisWeek:
        return 'This Week';
      case DateCategory.thisMonth:
        return 'This Month';
      case DateCategory.older:
        return 'Older';
    }
  }

  List<_DateGroup> _groupSessionsByDate(List<SessionListItem> sessions) {
    final groups = <DateCategory, List<SessionListItem>>{};

    for (final session in sessions) {
      final category = _categorizeDate(session.createdAt);
      groups.putIfAbsent(category, () => []).add(session);
    }

    return DateCategory.values
        .where((category) => groups.containsKey(category))
        .map((category) => _DateGroup(
              category: category,
              label: _getCategoryLabel(category),
              sessions: groups[category]!,
              isExpanded: _expandedSections[category] ?? true,
            ))
        .toList();
  }

  void _startAutoRefresh() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 10));
      if (!mounted) return false;

      final sessions = ref.read(sessionListControllerProvider);
      sessions.whenData((items) {
        // Check if any sessions are still processing
        final hasProcessing = items.any((s) => s.status == SessionStatus.processing);
        if (hasProcessing) {
          ref.read(sessionListControllerProvider.notifier).refreshSilently();
        }
      });

      return mounted;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(sessionListControllerProvider);
    final sessionNotifier = ref.read(sessionListControllerProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Conversations',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withOpacity(0.9),
                      letterSpacing: -0.5,
                    ),
                  ),
                  sessions.maybeWhen(
                    data: (items) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${items.length}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF6366F1),
                        ),
                      ),
                    ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),

            // Sessions list
            Expanded(
              child: sessions.when(
                data: (items) => items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(48),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 64,
                                color: Colors.white.withOpacity(0.3),
                              ),
                              const SizedBox(height: 24),
                              Text(
                                'No conversations yet',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Swipe left to record your first session',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withOpacity(0.5),
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: sessionNotifier.refresh,
                        backgroundColor: const Color(0xFF1E1E1E),
                        color: const Color(0xFF6366F1),
                        child: _buildGroupedList(items, sessionNotifier),
                      ),
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF6366F1),
                  ),
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
                          'Failed to load conversations',
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
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: sessionNotifier.refresh,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedList(List<SessionListItem> items, dynamic sessionNotifier) {
    final groups = _groupSessionsByDate(items);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: groups.fold<int>(0, (sum, group) => sum + 1 + (group.isExpanded ? group.sessions.length : 0)),
      itemBuilder: (context, index) {
        int currentIndex = 0;

        for (final group in groups) {
          // Date header
          if (currentIndex == index) {
            return _buildDateHeader(group);
          }
          currentIndex++;

          // Sessions in this group (if expanded)
          if (group.isExpanded) {
            final sessionIndex = index - currentIndex;
            if (sessionIndex >= 0 && sessionIndex < group.sessions.length) {
              final session = group.sessions[sessionIndex];
              return Padding(
                padding: const EdgeInsets.only(left: 0),
                child: SessionCard(
                  session: session,
                  onTap: () => context.push('/session/${session.id}'),
                  onDelete: () => _deleteSession(session.id, sessionNotifier),
                ),
              );
            }
            currentIndex += group.sessions.length;
          }
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildDateHeader(_DateGroup group) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: InkWell(
        onTap: () {
          setState(() {
            _expandedSections[group.category] = !group.isExpanded;
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Icon(
                group.isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                color: Colors.white.withOpacity(0.6),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                group.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.6),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${group.sessions.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF6366F1).withOpacity(0.8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteSession(int sessionId, dynamic sessionNotifier) async {
    try {
      await sessionNotifier.deleteSession(sessionId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Recording deleted successfully'),
            backgroundColor: const Color(0xFF1E1E1E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: const Color(0xFFFF3B30),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }
}
