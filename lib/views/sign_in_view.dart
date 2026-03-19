import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/auth_manager.dart';
import '../services/debug_log.dart';

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
  State<SignInView> createState() => SignInViewState();
}

class SignInViewState extends State<SignInView> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _errorMessage;
  bool _hasNavigatedPastSignIn = false;
  Timer? _urlPollTimer;

  /// Force credential extraction from the WebView. Called externally
  /// (e.g. when the user taps a tab) to retry auth detection.
  void tryExtractCredentials() {
    // Only retry if we haven't already triggered sign-in completion.
    if (_signInCompleteTriggered) {
      DebugLog.log('SignInView: tryExtractCredentials skipped — already triggered');
      return;
    }
    DebugLog.log('SignInView: tryExtractCredentials called externally');
    _checkCurrentUrl();
  }

  @override
  void initState() {
    super.initState();
    _initWebView();
    // Poll the WebView URL to detect SPA route changes that don't
    // trigger onNavigationRequest or onPageFinished.
    _urlPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkCurrentUrl();
    });
  }

  @override
  void dispose() {
    _urlPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkCurrentUrl() async {
    if (_signInCompleteTriggered) return;
    try {
      final url = await _controller.currentUrl();
      if (url != null) {
        _handleNavigation(url);
      }
    } catch (_) {
      // Controller may not be ready yet.
    }
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
          onPageFinished: (url) {
            setState(() {
              _isLoading = false;
            });
            // Also check for sign-in completion here — SPA route changes
            // and JS-based redirects may not trigger onNavigationRequest
            // on iOS, but onPageFinished fires reliably.
            _handleNavigation(url);
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

            // Allow navigation to the Kiro domain and OAuth providers.
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.navigate;

            final allowedHosts = {
              'app.kiro.dev',
              'oidc.us-east-1.amazonaws.com',
              'view.awsapps.com',
              'us-east-1.signin.aws',
              'signin.aws',
            };

            if (uri.host.isEmpty ||
                allowedHosts.contains(uri.host) ||
                uri.host.endsWith('.signin.aws') ||
                uri.host.endsWith('.awsapps.com') ||
                uri.host.endsWith('.amazonaws.com')) {
              return NavigationDecision.navigate;
            }

            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(SignInView.signInUrl));
  }

  bool _signInCompleteTriggered = false;

  /// Routes that indicate the OAuth flow is still in progress and
  /// sign-in has NOT yet completed.
  static const _authInProgressPaths = {
    '/signin/oauth',
    '/signin/sso',
    '/signin/callback',
    '/signin/redirect',
  };

  /// Detects when the WebView navigates away from the sign-in page,
  /// indicating that sign-in is complete.
  void _handleNavigation(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    final signInUri = Uri.parse(SignInView.signInUrl);

    final isSignInPage =
        uri.host == signInUri.host && uri.path == signInUri.path;

    // Ignore intermediate OAuth redirects — these are still part of
    // the sign-in flow, not the authenticated app.
    final isAuthInProgress = uri.host == signInUri.host &&
        _authInProgressPaths.any((p) => uri.path.startsWith(p));

    if (!isSignInPage && !isAuthInProgress && uri.host == signInUri.host) {
      DebugLog.log('SignInView: navigated past sign-in to ${uri.path}');
      if (!_hasNavigatedPastSignIn) {
        setState(() => _hasNavigatedPastSignIn = true);
      }
      if (!_signInCompleteTriggered) {
        _signInCompleteTriggered = true;
        _urlPollTimer?.cancel();
        DebugLog.log('SignInView: triggering handleSignInComplete');
        // Give the page time to finish loading, execute its own
        // GetToken call, and populate its internal token state.
        Future.delayed(const Duration(seconds: 3), () {
          if (!mounted) return;
          final authManager = context.read<AuthManager>();
          authManager.handleSignInComplete(_controller);
        });
      }
    }
  }

  void _forceReAuth() {
    setState(() {
      _hasNavigatedPastSignIn = false;
      _signInCompleteTriggered = false;
      _isLoading = true;
      _errorMessage = null;
    });
    // Restart URL polling.
    _urlPollTimer?.cancel();
    _urlPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkCurrentUrl();
    });
    // Clear cookies so the WebView starts a fresh sign-in.
    final authManager = context.read<AuthManager>();
    authManager.signOut();
    _controller.loadRequest(Uri.parse(SignInView.signInUrl));
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
    return PopScope(
      canPop: !kIsWeb,
      child: Stack(
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

          // Loading indicator — use an opaque background so the WebView's
          // own loading spinner doesn't show through, avoiding two visible
          // spinners at the same time.
          if (_isLoading && _errorMessage == null)
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),

          // Floating re-auth button when stuck on the Kiro web page
          if (_hasNavigatedPastSignIn && !_isLoading && _errorMessage == null)
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Center(
                child: SafeArea(
                  child: ElevatedButton.icon(
                    onPressed: _forceReAuth,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Sign in again'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.surface,
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      elevation: 4,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
