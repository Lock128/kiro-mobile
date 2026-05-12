import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_manager.dart';
import '../services/debug_log.dart';
import '../services/kiro_api.dart';
import 'message_input_bar.dart';

/// Displays a space session's message history, polling for updates.
class SessionDetailView extends StatefulWidget {
  const SessionDetailView({
    super.key,
    required this.api,
    required this.spaceId,
    required this.sessionId,
  });

  final KiroApi api;
  final String spaceId;
  final String sessionId;

  @override
  State<SessionDetailView> createState() => _SessionDetailViewState();
}

class _SessionDetailViewState extends State<SessionDetailView> {
  SessionResources? _resources;
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;
  final _scrollController = ScrollController();
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchResources();
    // Poll every 3 seconds for updates.
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _fetchResources(),
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

  Future<void> _fetchResources() async {
    try {
      final resources = await widget.api.getSessionResources(
        spaceId: widget.spaceId,
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
      DebugLog.log('SessionDetailView: auth expired during fetchResources');
      if (mounted) {
        context.read<AuthManager>().handleAuthError();
      }
    } catch (e) {
      DebugLog.log('SessionDetailView: fetchResources error: $e');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Space',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              widget.spaceId,
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
                                _fetchResources();
                              },
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _resources == null || _resources!.pullRequests.isEmpty
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
                          ),
          ),
          MessageInputBar(
            hintText: 'Send a message…',
            onSend: (message) async {
              try {
                await widget.api.streamSendMessage(
                  spaceId: widget.spaceId,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
              ],
            ),
            if (pr.state != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  pr.state!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
