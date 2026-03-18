import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/kiro_api.dart';

/// Displays task details and its linked session conversation.
class TaskDetailView extends StatefulWidget {
  const TaskDetailView({
    super.key,
    required this.api,
    required this.task,
    this.session,
  });

  final KiroApi api;
  final AgentTask task;
  final ChatSession? session;

  @override
  State<TaskDetailView> createState() => _TaskDetailViewState();
}

class _TaskDetailViewState extends State<TaskDetailView> {
  List<SessionMessage> _messages = [];
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;

  bool get _isActive {
    final s = widget.task.status?.toUpperCase() ?? '';
    return s != 'COMPLETED' && s != 'FAILED' && s != 'CANCELLED';
  }

  @override
  void initState() {
    super.initState();
    if (widget.session != null) {
      _fetchHistory();
      if (_isActive) {
        _pollTimer = Timer.periodic(
          const Duration(seconds: 5),
          (_) => _fetchHistory(),
        );
      }
    } else {
      _loading = false;
    }
  }

  Future<void> _fetchHistory() async {
    if (widget.session == null) return;
    try {
      final history = await widget.api.listSessionHistory(
        sessionId: widget.session!.sessionId,
      );
      if (mounted) {
        setState(() {
          _messages = history.activities.reversed.toList();
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _loading) {
        setState(() {
          _loading = false;
          _error = 'Failed to load conversation.';
        });
      }
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  String _repoLabel() {
    final res = widget.session?.providerResources;
    if (res == null || res.isEmpty) return '';
    if (res.length > 1) return '${res.length} repos';
    final gh = res.first['github'] as Map<String, dynamic>?;
    if (gh == null) return '';
    final owner = gh['owner'] as String? ?? '';
    final name = gh['name'] as String? ?? '';
    if (owner.isNotEmpty && name.isNotEmpty) return '$owner/$name';
    return name;
  }

  String _sourceLabel() {
    final src = widget.task.sourceProvider;
    if (src == null || src.isEmpty) return '';
    if (src.contains('BIGWEAVER')) return 'Kiro';
    return src;
  }

  Widget _statusChip(ThemeData theme) {
    final label = widget.task.status ?? 'unknown';
    final isCompleted = label.toUpperCase() == 'COMPLETED';
    final isInProgress =
        label.toUpperCase() == 'IN_PROGRESS' || label.toUpperCase() == 'RUNNING';
    final Color color;
    final IconData icon;
    if (isCompleted) {
      color = Colors.green;
      icon = Icons.check_circle_outline;
    } else if (isInProgress) {
      color = Colors.orange;
      icon = Icons.autorenew;
    } else {
      color = theme.colorScheme.onSurfaceVariant;
      icon = Icons.circle_outlined;
    }
    final display = label
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty
            ? w
            : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(display,
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.toLocal().hour.toString().padLeft(2, '0');
    final m = dt.toLocal().minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = widget.task;
    final repo = _repoLabel();
    final source = _sourceLabel();

    return Scaffold(
      appBar: AppBar(
        title: Text('Task Details', style: theme.textTheme.titleMedium),
      ),
      body: Column(
        children: [
          // Task info header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
              border: Border(
                bottom: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.name ?? task.title ?? 'Untitled Task',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    _statusChip(theme),
                    if (repo.isNotEmpty)
                      _InfoChip(
                          icon: Icons.folder_outlined, label: repo),
                    if (source.isNotEmpty)
                      _InfoChip(
                          icon: Icons.source_outlined, label: source),
                    if (task.createdTime != null)
                      _InfoChip(
                        icon: Icons.calendar_today_outlined,
                        label: 'Created ${_formatDate(task.createdTime!)}',
                      ),
                    if (task.lastUpdatedTime != null)
                      _InfoChip(
                        icon: Icons.update,
                        label: 'Updated ${_formatDate(task.lastUpdatedTime!)}',
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Conversation
          Expanded(child: _buildConversation(theme)),
        ],
      ),
    );
  }

  Widget _buildConversation(ThemeData theme) {
    if (widget.session == null) {
      return const Center(child: Text('No linked session found.'));
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() => _loading = true);
                _fetchHistory();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isActive) const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_isActive
                ? 'Waiting for agent response…'
                : 'No conversation history.'),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return _MessageBubble(message: msg);
      },
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final SessionMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final theme = Theme.of(context);

    String displayText;
    try {
      if (message.content != null && message.content!.startsWith('{')) {
        final parsed =
            Map<String, dynamic>.from(_tryParseJson(message.content!));
        // Handle nested {text: {content: "..."}} from activities
        if (parsed.containsKey('text') && parsed['text'] is Map) {
          final inner = parsed['text'] as Map;
          displayText = inner['content'] as String? ?? message.content!;
          // The inner content might itself be JSON like {"text": "actual msg"}
          if (displayText.startsWith('{')) {
            try {
              final innerParsed = Map<String, dynamic>.from(
                  _tryParseJson(displayText));
              displayText = innerParsed['text'] as String? ?? displayText;
            } catch (_) {}
          }
        } else {
          displayText = parsed['text'] as String? ?? message.content!;
        }
      } else {
        displayText = message.content ?? '(no content)';
      }
    } catch (_) {
      displayText = message.content ?? '(no content)';
    }

    if (displayText.length > 800) {
      displayText = '${displayText.substring(0, 800)}…';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 4),
              child: Icon(
                Icons.smart_toy_outlined,
                size: 20,
                color: theme.colorScheme.primary,
              ),
            ),
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isUser && message.agentName != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        message.agentName!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  Text(displayText, style: theme.textTheme.bodyMedium),
                  if (message.timestamp != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _formatTime(message.timestamp!),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 28),
        ],
      ),
    );
  }

  static Map<String, dynamic> _tryParseJson(String text) {
    try {
      return Map<String, dynamic>.from(
        const JsonDecoder().convert(text) as Map,
      );
    } catch (_) {
      return {};
    }
  }

  static String _formatTime(DateTime dt) {
    final h = dt.toLocal().hour.toString().padLeft(2, '0');
    final m = dt.toLocal().minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
