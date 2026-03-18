import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;

import '../services/auth_manager.dart';

/// Web-specific sign-in view that uses an iframe instead of WebView.
class SignInViewWeb extends StatefulWidget {
  const SignInViewWeb({super.key});

  static const String signInUrl = 'https://app.kiro.dev/signin';

  @override
  State<SignInViewWeb> createState() => _SignInViewWebState();
}

class _SignInViewWebState extends State<SignInViewWeb> {
  static const String _viewType = 'kiro-sign-in-iframe';
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _navigationPollTimer;

  @override
  void initState() {
    super.initState();
    _registerViewFactory();
    _startNavigationPolling();
  }

  void _registerViewFactory() {
    // ignore: undefined_prefixed_name
    final iframe = web.HTMLIFrameElement()
      ..src = SignInViewWeb.signInUrl
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allow = 'cross-origin-isolated';

    iframe.onLoad.listen((_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    });

    iframe.onError.listen((_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load the sign-in page.';
        });
      }
    });
  }

  /// Polls document.cookie to detect when auth cookies are set after sign-in.
  void _startNavigationPolling() {
    _navigationPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _checkForAuthCookies(),
    );
  }

  void _checkForAuthCookies() {
    try {
      final cookieString = web.document.cookie;
      if (cookieString.contains('kiro_token') ||
          cookieString.contains('session') ||
          cookieString.contains('auth_token')) {
        _navigationPollTimer?.cancel();
        final authManager = context.read<AuthManager>();
        authManager.handleWebSignInComplete();
      }
    } catch (_) {
      // Cross-origin cookie access may fail — that's expected.
    }
  }

  void _retry() {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    // Force iframe reload by re-registering
    _registerViewFactory();
  }

  @override
  void dispose() {
    _navigationPollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Stack(
          children: [
            if (_errorMessage == null)
              HtmlElementView.fromTagName(
                tagName: 'iframe',
                onElementCreated: (element) {
                  final iframe = element as web.HTMLIFrameElement;
                  iframe.src = SignInViewWeb.signInUrl;
                  iframe.style.border = 'none';
                  iframe.style.width = '100%';
                  iframe.style.height = '100%';

                  iframe.onLoad.listen((_) {
                    if (mounted) {
                      setState(() => _isLoading = false);
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
