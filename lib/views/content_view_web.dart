import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;

import '../services/auth_manager.dart';

/// Web-specific content view that uses an iframe instead of WebView.
class ContentViewWeb extends StatefulWidget {
  const ContentViewWeb({super.key});

  static const String contentUrl = 'https://app.kiro.dev/';

  @override
  State<ContentViewWeb> createState() => _ContentViewWebState();
}

class _ContentViewWebState extends State<ContentViewWeb> {
  bool _isLoading = true;
  String? _errorMessage;

  void _retry() {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
  }

  void _signOut() {
    // Clear browser cookies for the domain.
    try {
      final cookies = web.document.cookie.split(';');
      for (final cookie in cookies) {
        final name = cookie.split('=').first.trim();
        web.document.cookie =
            '$name=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/';
      }
    } catch (_) {}

    final authManager = context.read<AuthManager>();
    authManager.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kiro'),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sign out',
              onPressed: _signOut,
            ),
          ],
        ),
        body: Stack(
          children: [
            if (_errorMessage == null)
              HtmlElementView.fromTagName(
                tagName: 'iframe',
                onElementCreated: (element) {
                  final iframe = element as web.HTMLIFrameElement;
                  iframe.src = ContentViewWeb.contentUrl;
                  iframe.style.border = 'none';
                  iframe.style.width = '100%';
                  iframe.style.height = '100%';

                  iframe.onLoad.listen((_) {
                    if (mounted) {
                      setState(() => _isLoading = false);
                    }
                  });

                  iframe.onError.listen((_) {
                    if (mounted) {
                      setState(() {
                        _isLoading = false;
                        _errorMessage = 'Failed to load content.';
                      });
                    }
                  });
                },
              ),
            if (_errorMessage != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _retry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            if (_isLoading && _errorMessage == null)
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
