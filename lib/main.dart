import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/auth_manager.dart';
import 'services/connectivity_monitor.dart';
import 'services/credential_store_factory.dart';
import 'services/debug_log.dart';
import 'views/app_shell.dart';

void main() {
  // Catch Flutter framework errors (rendering, layout, etc.).
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    DebugLog.log('FlutterError: ${details.exceptionAsString()}');
    if (details.stack != null) {
      DebugLog.log('Stack: ${details.stack.toString().split('\n').take(5).join('\n')}');
    }
  };

  // Catch async errors that escape the Flutter framework.
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();

    final credentialStore = createCredentialStore();
    final authManager = AuthManager(credentialStore: credentialStore);
    final connectivityMonitor = ConnectivityMonitorImpl();

    // Kick off credential loading in the background.
    authManager.initialize();

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthManager>.value(value: authManager),
          Provider<ConnectivityMonitor>.value(value: connectivityMonitor),
        ],
        child: const KiroApp(),
      ),
    );
  }, (error, stack) {
    DebugLog.log('Uncaught: $error');
    DebugLog.log('Stack: ${stack.toString().split('\n').take(5).join('\n')}');
  });
}

class KiroApp extends StatelessWidget {
  const KiroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kiro',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const AppShell(),
    );
  }
}
