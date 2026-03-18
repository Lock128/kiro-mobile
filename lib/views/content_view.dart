import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/auth_manager.dart';

/// Displays authenticated Kiro UI content inside a WebView.
///
/// Injects [AuthCredentials] cookies into the WebView, shows a loading
/// indicator while content loads, displays an error with retry on failure,
/// provides a sign-out action, and monitors for HTTP 401 responses.
class ContentView extends StatefulWidget {
  const ContentView({super.key});

  /// The URL of the authenticated Kiro app.
  static const String contentUrl = 'https://app.kiro.dev/';

  @override
  State<ContentView> createState() => _ContentViewState();
}

class _ContentViewState extends State<ContentView> {
  late WebViewController _controller;
  bool _isLoading = true;
  bool _controllerReady = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    await _injectCookies();

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
            if (error.isForMainFrame ?? true) {
              setState(() {
                _isLoading = false;
                _errorMessage =
                    error.description.isNotEmpty
                        ? error.description
                        : 'Failed to load content.';
              });
            }
          },
          onHttpError: (HttpResponseError error) {
            if (error.response?.statusCode == 401) {
              final authManager = context.read<AuthManager>();
              authManager.handleAuthError();
            }
          },
          onNavigationRequest: (request) {
            // Block navigation to external domains to prevent new tabs
            // from breaking the authenticated session (Requirement 8.6).
            final uri = Uri.tryParse(request.url);
            final contentUri = Uri.parse(ContentView.contentUrl);
            if (uri != null && uri.host.isNotEmpty && uri.host != contentUri.host) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(ContentView.contentUrl));

    if (mounted) {
      setState(() {
        _controllerReady = true;
      });
    }
  }

  /// Injects stored cookies into the WebView cookie manager so that
  /// authenticated requests include the user's credentials.
  Future<void> _injectCookies() async {
    final authManager = context.read<AuthManager>();
    final credentials = authManager.credentials;
    if (credentials == null) return;

    final cookieManager = WebViewCookieManager();
    final uri = Uri.parse(ContentView.contentUrl);

    for (final entry in credentials.cookies.entries) {
      await cookieManager.setCookie(
        WebViewCookie(
          name: entry.key,
          value: entry.value,
          domain: uri.host,
          path: '/',
        ),
      );
    }
  }

  void _retry() {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _controllerReady = false;
    });
    _initWebView();
  }

  void _signOut() {
    final authManager = context.read<AuthManager>();
    authManager.signOut();
  }

  @override
  Widget build(BuildContext context) {
    // On Web, prevent the browser back button from navigating away
    // from the authenticated content (Requirement 8.6).
    return PopScope(
      canPop: !kIsWeb,
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
            // WebView is always in the tree so it can load in the background.
            if (_errorMessage == null && _controllerReady)
              WebViewWidget(controller: _controller),

            // Error state
            if (_errorMessage != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Colors.red,
                      ),
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
