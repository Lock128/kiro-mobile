import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/debug_log.dart';

/// A reusable error screen that displays an error icon, a message, and
/// an optional retry button. Includes a "Show Debug Log" button for
/// on-device diagnostics.
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.onSignInAgain,
  });

  /// The error message shown to the user.
  final String message;

  /// Called when the user taps the retry button.
  /// If `null`, the retry button is hidden.
  final VoidCallback? onRetry;

  /// Called when the user taps "Sign in again".
  /// If `null`, the button is hidden.
  final VoidCallback? onSignInAgain;

  void _showDebugLog(BuildContext context) {
    final log = DebugLog.dump();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Text(
                    'Debug Log',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.share),
                    tooltip: 'Share log file',
                    onPressed: () => DebugLog.shareLog(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy to clipboard',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: log));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: log.isEmpty
                  ? const Center(child: Text('No log entries yet.'))
                  : ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(12),
                      children: [
                        SelectableText(
                          log,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
            if (onSignInAgain != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onSignInAgain,
                icon: const Icon(Icons.login, size: 18),
                label: const Text('Sign in again'),
              ),
            ],
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () => _showDebugLog(context),
              icon: const Icon(Icons.bug_report, size: 18),
              label: const Text('Show Debug Log'),
            ),
          ],
        ),
      ),
    );
  }
}
