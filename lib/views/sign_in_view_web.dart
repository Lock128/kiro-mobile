import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;

import '../services/auth_manager.dart';

/// Web-specific sign-in view that uses a redirect-based OAuth flow.
///
/// The Kiro server sends `X-Frame-Options: DENY` and
/// `frame-ancestors 'none'`, so iframes cannot be used.
///
/// Flow:
/// 1. User clicks "Sign in" → main window redirects to app.kiro.dev/signin
/// 2. OAuth completes → user lands on app.kiro.dev with cookies set
/// 3. A small bootstrap script on the callback page calls GetToken,
///    extracts the bearer/CSRF tokens, and redirects back to the Flutter
///    app with tokens encoded in the URL hash.
/// 4. On startup, the Flutter app checks for tokens in the URL hash and
///    stores them.
///
/// Alternatively, if the user already has tokens in the URL (returning
/// from the redirect), we extract them immediately.
class SignInViewWeb extends StatefulWidget {
  const SignInViewWeb({super.key});

  static const String signInUrl = 'https://app.kiro.dev/signin';

  @override
  State<SignInViewWeb> createState() => _SignInViewWebState();
}

class _SignInViewWebState extends State<SignInViewWeb> {
  bool _isSigningIn = false;
  String? _errorMessage;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // Check if we're returning from a redirect with tokens in the URL hash.
    _checkForReturnTokens();
  }

  /// Checks the URL hash for tokens passed back from the redirect flow.
  void _checkForReturnTokens() {
    try {
      final hash = web.window.location.hash;
      if (hash.startsWith('#kiro_auth=')) {
        final encoded = hash.substring('#kiro_auth='.length);
        final jsonStr = Uri.decodeComponent(encoded);
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        final bearerToken = data['bearerToken'] as String?;
        final csrfToken = data['csrfToken'] as String?;

        // Clear the hash so tokens aren't visible in the URL.
        web.window.history.replaceState(
          ''.toJS,
          '',
          web.window.location.pathname,
        );

        if (bearerToken != null && bearerToken.isNotEmpty) {
          _authenticateWithTokens(bearerToken, csrfToken);
          return;
        }
      }
    } catch (_) {
      // No tokens in URL — show normal sign-in UI.
    }
  }

  /// Stores the extracted tokens and transitions to authenticated state.
  void _authenticateWithTokens(String bearerToken, String? csrfToken) {
    final authManager = context.read<AuthManager>();
    authManager.handleWebSignInWithTokens(
      bearerToken: bearerToken,
      csrfToken: csrfToken,
    );
  }

  void _openSignIn() {
    setState(() {
      _isSigningIn = true;
      _errorMessage = null;
    });

    // Open the sign-in page in a centered popup window.
    const width = 600;
    const height = 700;
    final left = (web.window.screen.width - width) ~/ 2;
    final top = (web.window.screen.height - height) ~/ 2;

    final popup = web.window.open(
      SignInViewWeb.signInUrl,
      'kiro_signin',
      'width=$width,height=$height,left=$left,top=$top,'
          'menubar=no,toolbar=no,location=yes,status=no',
    );

    if (popup == null || popup.closed) {
      setState(() {
        _isSigningIn = false;
        _errorMessage =
            'Could not open the sign-in window. Please allow popups for this site.';
      });
      return;
    }

    // Listen for postMessage from the popup (in case we can inject a
    // token-extraction script).
    _listenForPostMessage();

    // Poll until the popup is closed (user finished or cancelled).
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (popup.closed) {
        _pollTimer?.cancel();
        _onPopupClosed();
      }
    });
  }

  web.EventListener? _messageListener;

  void _listenForPostMessage() {
    _messageListener = ((web.MessageEvent event) {
      try {
        final data = event.data;
        if (data == null) return;
        // Expect: {type: 'kiro_auth', bearerToken: '...', csrfToken: '...'}
        final str = data.toString();
        if (!str.contains('kiro_auth')) return;

        // Try to parse as JSON
        final map = jsonDecode(str) as Map<String, dynamic>;
        if (map['type'] != 'kiro_auth') return;

        final bearerToken = map['bearerToken'] as String?;
        final csrfToken = map['csrfToken'] as String?;
        if (bearerToken != null && bearerToken.isNotEmpty) {
          _pollTimer?.cancel();
          _authenticateWithTokens(bearerToken, csrfToken);
        }
      } catch (_) {
        // Not our message — ignore.
      }
    }).toJS;

    web.window.addEventListener('message', _messageListener!);
  }

  /// Called when the popup window is closed.
  /// Shows a token input dialog since we can't extract tokens cross-origin.
  void _onPopupClosed() {
    if (!mounted) return;

    setState(() => _isSigningIn = false);

    // Show the token input dialog for the user to paste their credentials.
    _showTokenInputDialog();
  }

  /// Shows a dialog where the user can paste their bearer token.
  /// This is needed because the popup authenticates on app.kiro.dev
  /// (different origin) and we can't read its cookies.
  void _showTokenInputDialog() {
    final bearerController = TextEditingController();
    final csrfController = TextEditingController();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Enter Authentication Tokens'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'After signing in, you need to provide your authentication tokens. '
                  'You can find them in the browser DevTools on app.kiro.dev:',
                ),
                const SizedBox(height: 8),
                const Text(
                  '1. Open app.kiro.dev in a new tab\n'
                  '2. Open DevTools (F12) → Application → Cookies\n'
                  '3. Copy the "AccessToken" cookie value',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: bearerController,
                  decoration: const InputDecoration(
                    labelText: 'Bearer Token (AccessToken cookie)',
                    hintText: 'Paste your AccessToken here…',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: csrfController,
                  decoration: const InputDecoration(
                    labelText: 'CSRF Token (optional)',
                    hintText: 'Paste x-csrf-token here…',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final bearer = bearerController.text.trim();
                if (bearer.isEmpty) return;
                Navigator.of(dialogContext).pop();
                _authenticateWithTokens(
                  bearer,
                  csrfController.text.trim().isEmpty
                      ? null
                      : csrfController.text.trim(),
                );
              },
              child: const Text('Sign In'),
            ),
          ],
        );
      },
    );
  }

  void _retry() {
    setState(() {
      _isSigningIn = false;
      _errorMessage = null;
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    if (_messageListener != null) {
      web.window.removeEventListener('message', _messageListener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 64, color: Colors.blueGrey),
                const SizedBox(height: 24),
                Text(
                  'Sign in to Kiro',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'A new window will open for you to sign in securely.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                if (_errorMessage != null) ...[
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.red),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ] else if (_isSigningIn) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text('Waiting for sign-in to complete…'),
                ] else
                  ElevatedButton.icon(
                    onPressed: _openSignIn,
                    icon: const Icon(Icons.login),
                    label: const Text('Sign in'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
