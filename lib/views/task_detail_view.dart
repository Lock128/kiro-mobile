import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_manager.dart';
import '../services/debug_log.dart';
import '../services/kiro_api.dart';
import 'message_input_bar.dart';

/// Displays task (autonomous space) details and its linked session.
class TaskDetailView extends StatefulWidget {
  const TaskDetailView({
    super.key,
    required this.api,
    required this.space,
    required this.sessionId,
  });

  final KiroApi api;
  final Space space;
  final String sessionId;

  @override
  State<TaskDetailView> createState() => _TaskDetailViewState();
}

class _TaskDetailViewState extends State<TaskDetailView> {
  SessionResources? _resources;
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;
  final _scrollController = ScrollController();
  bool _showScrollToBottom = false;

  bool get _isActive => widget.space.status?.toUpperCase() == 'ACTIVE';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchResources();
    if (_isActive) {
      _pollTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _fetchResources(),
      );
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

  Future<void> _fetchResources() async {
    try {
      final resources = await widget.api.getSessionResources(
        spaceId: widget.space.spaceId,
        sessionId: widget.sessionId,
      );
      if (mounted) {
        setState(() {
          _resources = resources;
          _loading = false;
          _error = null;
        });
      }
    } on AuthExpiredException {
      DebugLog.log('TaskDetailView: auth expired during fetchResources');
      if (mounted) {
        context.read<AuthManager>().handleAuthError();
      }
    } catch (e) {
      DebugLog.log('TaskDetailView: fetchResources error: $e');
      if (mounted && _loading) {
        setState(() {
          _loading = false;
          _error = 'Failed to load session resources.';
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
    if (widget.space.githubRepo != null) {
      final fullName = widget.space.githubRepo!['fullName'] as String?;
      if (fullName != null && fullName.isNotEmpty) return fullName;
    }
    final res = widget.space.providerResources;
    if (res == null || res.isEmpty) return '';
    if (res.length > 1) return '${res.length} repos';
    return res.first['name'] as String? ?? '';
  }

  Widget _statusChip(ThemeData theme) {
    final label = widget.space.status ?? 'unknown';
    final isActive = label.toUpperCase() == 'ACTIVE';
    final Color color;
    final IconData icon;
    if (isActive) {
      color = Colors.green;
      icon = Icons.check_circle_outline;
    } else {
      color = theme.colorScheme.onSurfaceVariant;
      icon = Icons.circle_outlined;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ],
    );
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
    final space = widget.space;
    final repo = _repoLabel();

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
                  space.name,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    _statusChip(theme),
                    if (repo.isNotEmpty)
                      _InfoChip(icon: Icons.folder_outlined, label: repo),
                    if (space.createdAt != null)
                      _InfoChip(
                        icon: Icons.calendar_today_outlined,
                        label: 'Created ${_formatDate(space.createdAt!)}',
                      ),
                    if (space.updatedAt != null)
                      _InfoChip(
                        icon: Icons.update,
                        label: 'Updated ${_formatDate(space.updatedAt!)}',
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Resources
          Expanded(child: _buildContent(theme)),
          MessageInputBar(
            hintText: 'Reply to this task…',
            onSend: (message) async {
              try {
                await widget.api.streamSendMessage(
                  spaceId: widget.space.spaceId,
                  sessionId: widget.sessionId,
                  message: message,
                );
                _fetchResources();
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

  Widget _buildContent(ThemeData theme) {
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
                _fetchResources();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_resources == null || _resources!.pullRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isActive) const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_isActive
                ? 'Waiting for agent response…'
                : 'No resources yet.'),
          ],
        ),
      );
    }
    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: _resources!.pullRequests.length,
          itemBuilder: (context, index) {
            final pr = _resources!.pullRequests[index];
            return _PullRequestTile(pr: pr);
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

class _PullRequestTile extends StatelessWidget {
  const _PullRequestTile({required this.pr});
  final PullRequest pr;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.merge, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${pr.owner ?? ''}/${pr.repo ?? ''} #${pr.prId ?? ''}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            if (pr.state != null)
              Text(
                pr.state!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
