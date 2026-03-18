import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/auth_manager.dart';

/// Displays the Kiro sign-in page inside a WebView.
///
/// Shows a loading indicator while the page loads, an error message with
/// a retry button on failure, and monitors URL navigation to detect
/// sign-in completion.
class SignInView extends StatefulWidget {
  const SignInView({super.key});

  /// The URL of the Kiro sign-in page.
  static const String signInUrl = 'https://app.kiro.dev/signin';

  @override
  State<SignInView> createState() => _SignInViewState();
}

class _SignInViewState extends State<SignInView> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            setState(() {
              _isLoading = true;
              _errorMessage = null;
            });
          },
          onPageFinished: (_) {
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (error) {
            // Only treat main frame errors as page-level failures.
            if (error.isForMainFrame ?? true) {
              setState(() {
                _isLoading = false;
                _errorMessage =
                    error.description.isNotEmpty
                        ? error.description
                        : 'Failed to load the sign-in page.';
              });
            }
          },
          onNavigationRequest: (request) {
            _handleNavigation(request.url);

            // Block navigation to external domains to prevent new tabs
            // from breaking the auth flow (Requirement 8.6).
            final uri = Uri.tryParse(request.url);
            final signInUri = Uri.parse(SignInView.signInUrl);
            if (uri != null && uri.host.isNotEmpty && uri.host != signInUri.host) {
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(SignInView.signInUrl));
  }

  /// Detects when the WebView navigates away from the sign-in page,
  /// indicating that sign-in is complete.
  void _handleNavigation(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    final signInUri = Uri.parse(SignInView.signInUrl);

    // If the host matches but the path has moved away from /signin,
    // the user has completed the sign-in flow.
    final isSignInPage =
        uri.host == signInUri.host && uri.path == signInUri.path;

    if (!isSignInPage && uri.host == signInUri.host) {
      final authManager = context.read<AuthManager>();
      authManager.handleSignInComplete(_controller);
    }
  }

  void _retry() {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    _controller.loadRequest(Uri.parse(SignInView.signInUrl));
  }

  @override
  Widget build(BuildContext context) {
    // On Web, prevent the browser back button from navigating away
    // during the sign-in flow (Requirement 8.6).
    return PopScope(
      canPop: !kIsWeb,
      child: Scaffold(
        body: Stack(
          children: [
            // WebView is always in the tree so it can load in the background.
            if (_errorMessage == null) WebViewWidget(controller: _controller),

            // Error state
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

            // Loading indicator
            if (_isLoading && _errorMessage == null)
              const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
