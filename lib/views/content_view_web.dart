import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;

import '../services/auth_manager.dart';

/// Web-specific content view that redirects to the Kiro app in the
/// current window instead of using an iframe.
///
/// The Kiro server sends `X-Frame-Options: DENY`, so iframes are blocked.
/// On web, the simplest approach is to navigate the current window to the
/// Kiro app URL, since the user is already authenticated via cookies.
class ContentViewWeb extends StatefulWidget {
  const ContentViewWeb({super.key});

  static const String contentUrl = 'https://app.kiro.dev/';

  @override
  State<ContentViewWeb> createState() => _ContentViewWebState();
}

class _ContentViewWebState extends State<ContentViewWeb> {
  @override
  void initState() {
    super.initState();
    // Redirect the browser to the Kiro app now that we're authenticated.
    _navigateToKiro();
  }

  void _navigateToKiro() {
    web.window.location.href = ContentViewWeb.contentUrl;
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
    // This screen is shown briefly while the redirect happens.
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
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Redirecting to Kiro…'),
            ],
          ),
        ),
      ),
    );
  }
}
