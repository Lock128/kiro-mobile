import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_manager.dart';
import '../services/debug_log.dart';
import '../services/kiro_api.dart';
import 'content_formatter.dart';
import 'formatted_content_view.dart';
import 'message_input_bar.dart';

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
  final _scrollController = ScrollController();
  bool _showScrollToBottom = false;

  bool get _isActive {
    final s = widget.task.status?.toUpperCase() ?? '';
    return s != 'COMPLETED' && s != 'FAILED' && s != 'CANCELLED';
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
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

  void _onScroll() {
    final atBottom = _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100;
    if (_showScrollToBottom == atBottom) {
      setState(() => _showScrollToBottom = !atBottom);
    }
  }

  void _scrollToBottom() {
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
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
    } on AuthExpiredException {
      DebugLog.log('TaskDetailView: auth expired during fetchHistory');
      if (mounted) {
        context.read<AuthManager>().handleAuthError();
      }
    } catch (e) {
      DebugLog.log('TaskDetailView: fetchHistory error: $e');
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
    _scrollController.dispose();
    super.dispose();
  }

  String _repoLabel() {
    // Prefer providerResources directly on the task if available.
    var res = widget.task.providerResources;
    if (res == null || res.isEmpty) {
      res = widget.session?.providerResources;
    }
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
          if (widget.session != null)
            MessageInputBar(
              hintText: 'Reply to this task…',
              onSend: (message) async {
                try {
                  await widget.api.generateAgentSessionResponse(
                    sessionId: widget.session!.sessionId,
                    message: message,
                  );
                  _fetchHistory();
                } on AuthExpiredException {
                  if (mounted) {
                    context.read<AuthManager>().handleAuthError();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to send: $e')),
                    );
                  }
                }
              },
            ),
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
    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: _messages.length,
          itemBuilder: (context, index) {
            final msg = _messages[index];
            return _MessageBubble(message: msg);
          },
        ),
        if (_showScrollToBottom)
          Positioned(
            right: 16,
            bottom: 12,
            child: FloatingActionButton.small(
              onPressed: _scrollToBottom,
              tooltip: 'Scroll to bottom',
              child: const Icon(Icons.arrow_downward),
            ),
          ),
      ],
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

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({required this.message});
  final SessionMessage message;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _toolExpanded = false;

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final isUser = msg.role == 'user';
    final theme = Theme.of(context);

    if (msg.isTool) {
      return _buildToolBubble(theme, msg);
    }

    final formatted = ContentFormatter.format(msg.content);

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
                  if (!isUser && msg.agentName != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        msg.agentName!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  FormattedContentView(content: formatted),
                  if (msg.timestamp != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _formatTime(msg.timestamp!),
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

  Widget _buildToolBubble(ThemeData theme, SessionMessage msg) {
    final label = msg.toolName ?? (msg.isToolUse == true ? 'Tool call' : 'Tool result');
    final icon = msg.isToolUse == true ? Icons.build_outlined : Icons.output_outlined;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withAlpha(120),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => setState(() => _toolExpanded = !_toolExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(icon, size: 16,
                        color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      _toolExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (_toolExpanded && msg.content != null) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  msg.content!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    final h = dt.toLocal().hour.toString().padLeft(2, '0');
    final m = dt.toLocal().minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
