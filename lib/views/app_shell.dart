import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/auth_state.dart';
import '../services/auth_manager.dart';
import '../services/connectivity_monitor.dart';
import '../services/kiro_api.dart';
import '../services/instrumented_http_client.dart';
import '../services/debug_log.dart';
import '../services/telemetry_service.dart';
import 'error_view.dart';
import 'home_view.dart';
import 'settings_view.dart';
import 'sign_in_view.dart';
import 'sign_in_view_stub.dart'
    if (dart.library.js_interop) 'sign_in_view_web.dart';

/// Root widget that always shows a bottom tab bar (Create, Chats, Tasks)
/// and swaps the body content based on [AuthManager] state.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  StreamSubscription<bool>? _connectivitySubscription;
  bool _isOffline = false;
  int _currentIndex = 0;
  final _signInKey = GlobalKey<SignInViewState>();
  final _authenticatedBodyKey = GlobalKey<_AuthenticatedBodyState>();

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
      if (mounted) {
        context.read<AuthManager>().initialize();
      }
    }
  }

  void _showDebugLogSheet(BuildContext context) {
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

  void _showApiMetricsSheet(BuildContext context) {
    final client = _authenticatedBodyKey.currentState?.httpClient;
    if (client == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No API metrics available yet.')),
      );
      return;
    }
    final metrics = client.metrics;
    final json = client.dumpMetricsJson();

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
                  Text(
                    'API Metrics (${metrics.length})',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy JSON to clipboard',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: json));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('API metrics copied to clipboard')),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Clear metrics',
                    onPressed: () {
                      client.clearMetrics();
                      Navigator.pop(ctx);
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
              child: metrics.isEmpty
                  ? const Center(child: Text('No API calls recorded yet.'))
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: metrics.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        // Show newest first.
                        final m = metrics[metrics.length - 1 - i];
                        final color = m.statusCode == 200
                            ? Colors.green
                            : (m.error != null ? Colors.red : Colors.orange);
                        return ListTile(
                          dense: true,
                          leading: Icon(Icons.circle, color: color, size: 12),
                          title: Text(
                            '${m.operation}  ${m.totalDuration.toStringAsFixed(0)}ms',
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 13),
                          ),
                          subtitle: Text(
                            '${m.method} ${m.statusCode} · '
                            'req ${m.requestBodySize}B · res ${m.responseBodySize}B\n'
                            '${m.startedAt.toIso8601String()}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Consumer<AuthManager>(
          builder: (context, authManager, _) {
            return GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: Scaffold(
              appBar: authManager.state == AuthState.authenticated
                  ? AppBar(
                      title: const Text('Kiro'),
                      actions: [
                        if (_currentIndex == 1 || _currentIndex == 2)
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Reload',
                            onPressed: () => _authenticatedBodyKey
                                .currentState
                                ?.reloadCurrentTab(),
                          ),
                        IconButton(
                          icon: const Icon(Icons.speed_outlined),
                          tooltip: 'API Metrics',
                          onPressed: () => _showApiMetricsSheet(context),
                        ),
                        IconButton(
                          icon: const Icon(Icons.bug_report_outlined),
                          tooltip: 'Debug Log',
                          onPressed: () => _showDebugLogSheet(context),
                        ),
                        IconButton(
                          icon: const Icon(Icons.settings_outlined),
                          tooltip: 'Settings',
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const SettingsView(),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.logout),
                          tooltip: 'Sign out',
                          onPressed: () => authManager.signOut(),
                        ),
                      ],
                    )
                  : null,
              body: _buildBody(authManager),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: (i) {
                    setState(() => _currentIndex = i);
                    // If still showing the sign-in WebView, try to
                    // extract credentials — the user may have logged in
                    // via the SPA without us detecting it.
                    if (!kIsWeb &&
                        authManager.state == AuthState.unauthenticated) {
                      _signInKey.currentState?.tryExtractCredentials();
                    }
                  },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.add_circle_outline),
                    selectedIcon: Icon(Icons.add_circle),
                    label: 'Create',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.chat_bubble_outline),
                    selectedIcon: Icon(Icons.chat_bubble),
                    label: 'Chats',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.task_outlined),
                    selectedIcon: Icon(Icons.task),
                    label: 'Tasks',
                  ),
                ],
              ),
            ),
            );
          },
        ),
        if (_isOffline) _buildOfflineOverlay(),
      ],
    );
  }

  Widget _buildBody(AuthManager authManager) {
    switch (authManager.state) {
      case AuthState.unknown:
        return const Center(child: CircularProgressIndicator());
      case AuthState.unauthenticated:
        return kIsWeb
            ? const SignInViewWeb()
            : SignInView(key: _signInKey);
      case AuthState.authenticated:
        return _AuthenticatedBody(
          key: _authenticatedBodyKey,
          currentIndex: _currentIndex,
          authManager: authManager,
        );
      case AuthState.error:
        return ErrorView(
          message: 'Something went wrong. Please try again.',
          onRetry: () => authManager.initialize(),
          onSignInAgain: () => authManager.signOut(),
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
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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

/// The authenticated tab body. Manages [KiroApi] lifecycle and renders
/// the correct tab content via [IndexedStack].
class _AuthenticatedBody extends StatefulWidget {
  const _AuthenticatedBody({
    super.key,
    required this.currentIndex,
    required this.authManager,
  });

  final int currentIndex;
  final AuthManager authManager;

  @override
  State<_AuthenticatedBody> createState() => _AuthenticatedBodyState();
}

class _AuthenticatedBodyState extends State<_AuthenticatedBody> {
  KiroApi? _api;
  InstrumentedHttpClient? _httpClient;
  final _chatsKey = GlobalKey<ChatsTabState>();
  final _tasksKey = GlobalKey<TasksTabState>();

  @override
  void initState() {
    super.initState();
    final credentials = widget.authManager.credentials;
    if (credentials != null) {
      final telemetry = context.read<TelemetryService>();
      _api = KiroApi(credentials: credentials, telemetryService: telemetry);
    }
  }

  /// Exposes the instrumented client so the debug sheet can read metrics.
  InstrumentedHttpClient? get httpClient => _httpClient;

  void reloadCurrentTab() {
    switch (widget.currentIndex) {
      case 1:
        _chatsKey.currentState?.reload();
        break;
      case 2:
        _tasksKey.currentState?.reload();
        break;
    }
  }

  @override
  void dispose() {
    _api?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_api == null) {
      return const Center(child: Text('No credentials available.'));
    }
    return IndexedStack(
      index: widget.currentIndex,
      children: [
        CreateTab(api: _api!),
        ChatsTab(key: _chatsKey, api: _api!),
        TasksTab(key: _tasksKey, api: _api!),
      ],
    );
  }
}
