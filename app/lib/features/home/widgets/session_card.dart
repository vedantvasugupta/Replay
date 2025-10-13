import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/session_models.dart';

class SessionCard extends StatelessWidget {
  const SessionCard({
    required this.session,
    required this.onTap,
    required this.onDelete,
    super.key,
  });

  final SessionListItem session;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('MMM d, h:mm a');
    final dateStr = formatter.format(session.createdAt.toLocal());
    final duration = session.durationSec != null
        ? '${Duration(seconds: session.durationSec!).inMinutes} min'
        : '';

    return Dismissible(
      key: Key('session_${session.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFF3B30),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(
          Icons.delete_rounded,
          color: Colors.white,
          size: 28,
        ),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Delete Recording?'),
            content: Text(
              session.status == SessionStatus.processing
                  ? 'This recording is still being processed. Deleting it will stop the transcription.'
                  : 'This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFF3B30),
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ?? false;
      },
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withOpacity(0.05),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Status indicator dot
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _getStatusColor(session.status),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _getStatusColor(session.status).withOpacity(0.5),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.title ?? 'Recording ${session.id}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.6),
                          letterSpacing: 0.25,
                        ),
                      ),
                      if (duration.isNotEmpty) ...[
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.4),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(
                          duration,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.6),
                            letterSpacing: 0.25,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _getStatusColor(session.status).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _getStatusText(session.status),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _getStatusColor(session.status),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Color _getStatusColor(SessionStatus status) {
    switch (status) {
      case SessionStatus.ready:
        return const Color(0xFF30D158); // Green
      case SessionStatus.processing:
        return const Color(0xFFFF9500); // Orange
      case SessionStatus.uploaded:
        return const Color(0xFF6366F1); // Indigo
      case SessionStatus.failed:
        return const Color(0xFFFF3B30); // Red
    }
  }

  String _getStatusText(SessionStatus status) {
    switch (status) {
      case SessionStatus.ready:
        return 'READY';
      case SessionStatus.processing:
        return 'PROCESSING';
      case SessionStatus.uploaded:
        return 'UPLOADED';
      case SessionStatus.failed:
        return 'FAILED';
    }
  }
}
