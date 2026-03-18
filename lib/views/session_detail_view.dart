import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/kiro_api.dart';

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

  @override
  void initState() {
    super.initState();
    _fetchHistory();
    // Poll every 3 seconds for new messages.
    _pollTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _fetchHistory(),
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
    } catch (e) {
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
      body: _loading
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
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        return _MessageBubble(message: msg);
                      },
                    ),
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

    // Try to extract readable text from the content.
    String displayText;
    try {
      // Content might be JSON like {"text": "actual message"}
      if (message.content != null && message.content!.startsWith('{')) {
        final parsed =
            Map<String, dynamic>.from(_tryParseJson(message.content!));
        displayText = parsed['text'] as String? ?? message.content!;
      } else {
        displayText = message.content ?? '(no content)';
      }
    } catch (_) {
      displayText = message.content ?? '(no content)';
    }

    // Truncate very long tool results.
    if (displayText.length > 500) {
      displayText = '${displayText.substring(0, 500)}…';
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
