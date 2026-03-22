import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_manager.dart';
import '../services/debug_log.dart';
import '../services/kiro_api.dart';
import 'content_formatter.dart';
import 'formatted_content_view.dart';
import 'message_input_bar.dart';

/// Displays a session's message history, polling for updates.
class SessionDetailView extends StatefulWidget {
  const SessionDetailView({
    super.key,
    required this.api,
    required this.sessionId,
  });

  final KiroApi api;
  final String sessionId;

  @override
  State<SessionDetailView> createState() => _SessionDetailViewState();
}

class _SessionDetailViewState extends State<SessionDetailView> {
  List<SessionMessage> _messages = [];
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;
  final _scrollController = ScrollController();
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchHistory();
    // Poll every 3 seconds for new messages.
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _fetchHistory(),
    );
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
    try {
      final history = await widget.api.listSessionHistory(
        sessionId: widget.sessionId,
      );
      if (mounted) {
        setState(() {
          // Activities contain the conversation messages.
          _messages = history.activities.reversed.toList();
          _loading = false;
          _error = null;
        });
      }
    } on AuthExpiredException {
      DebugLog.log('SessionDetailView: auth expired during fetchHistory');
      if (mounted) {
        context.read<AuthManager>().handleAuthError();
      }
    } catch (e) {
      DebugLog.log('SessionDetailView: fetchHistory error: $e');
      if (mounted && _loading) {
        setState(() {
          _loading = false;
          _error = 'Failed to load session history.';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Session',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              widget.sessionId,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
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
                      )
                    : _messages.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 16),
                                Text('Waiting for agent response…'),
                              ],
                            ),
                          )
                        : Stack(
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
                          ),
          ),
          MessageInputBar(
            hintText: 'Reply to this chat…',
            onSend: (message) async {
              try {
                await widget.api.generateAgentSessionResponse(
                  sessionId: widget.sessionId,
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
