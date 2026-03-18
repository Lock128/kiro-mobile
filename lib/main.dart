import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/auth_manager.dart';
import 'services/connectivity_monitor.dart';
import 'services/credential_store_factory.dart';
import 'views/app_shell.dart';

void main() {
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
