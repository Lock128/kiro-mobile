import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/auth_state.dart';
import '../services/auth_manager.dart';
import '../services/connectivity_monitor.dart';
import 'error_view.dart';
import 'platform_views_stub.dart'
    if (dart.library.js_interop) 'platform_views_web.dart' as platform;

/// Root widget that listens to [AuthManager] state changes and renders
/// the appropriate view ([SignInView], [ContentView], [ErrorView], or a
/// loading indicator). Also integrates [ConnectivityMonitor] to show an
/// offline overlay with a retry button when the device loses connectivity.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  StreamSubscription<bool>? _connectivitySubscription;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _listenToConnectivity();
  }

  void _listenToConnectivity() {
    final monitor = context.read<ConnectivityMonitor>();
    _connectivitySubscription = monitor.isConnected.listen((connected) {
      setState(() {
        _isOffline = !connected;
      });
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  void _onRetryConnectivity() async {
    final monitor = context.read<ConnectivityMonitor>();
    final connected = await monitor.checkConnectivity();
    if (connected) {
      setState(() {
        _isOffline = false;
      });
      // Re-trigger the current auth operation so the app resumes.
      if (mounted) {
        final authManager = context.read<AuthManager>();
        authManager.initialize();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Consumer<AuthManager>(
          builder: (context, authManager, _) {
            return _buildForState(authManager);
          },
        ),
        if (_isOffline) _buildOfflineOverlay(),
      ],
    );
  }

  Widget _buildForState(AuthManager authManager) {
    switch (authManager.state) {
      case AuthState.unknown:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case AuthState.unauthenticated:
        return platform.buildSignInView();
      case AuthState.authenticated:
        return platform.buildContentView();
      case AuthState.error:
        return ErrorView(
          message: 'Something went wrong. Please try again.',
          onRetry: () => authManager.initialize(),
        );
    }
  }

  Widget _buildOfflineOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Card(
            margin: const EdgeInsets.all(32),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No internet connection',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Please check your connection and try again.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _onRetryConnectivity,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
