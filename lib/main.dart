import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterrific_opentelemetry/flutterrific_opentelemetry.dart';
import 'package:provider/provider.dart';

import 'services/auth_manager.dart';
import 'services/connectivity_monitor.dart';
import 'services/credential_store_factory.dart';
import 'services/debug_log.dart';
import 'services/telemetry_config.dart';
import 'services/telemetry_service.dart';
import 'views/app_shell.dart';

void main() {
  // Catch Flutter framework errors (rendering, layout, etc.).
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    DebugLog.log('FlutterError: ${details.exceptionAsString()}');
    if (details.stack != null) {
      DebugLog.log('Stack: ${details.stack.toString().split('\n').take(5).join('\n')}');
    }
    FlutterOTel.reportError(
      'FlutterError',
      details.exception,
      details.stack,
    );
  };

  // Catch async errors that escape the Flutter framework.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    final telemetryService = FlutterOTelTelemetryService();
    await telemetryService.initialize(
      serviceName: TelemetryConfig.serviceName,
      serviceVersion: TelemetryConfig.serviceVersion,
      tracerName: 'kiro-app',
      resourceAttributes: {
        'deployment.environment': const String.fromEnvironment(
          'OTEL_ENVIRONMENT',
          defaultValue: 'development',
        ),
        'service.namespace': 'kiro-mobile',
      },
    );

    DebugLog.telemetryService = telemetryService;

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
          Provider<TelemetryService>.value(value: telemetryService),
        ],
        child: const KiroApp(),
      ),
    );
  }, (error, stack) {
    DebugLog.log('Uncaught: $error');
    DebugLog.log('Stack: ${stack.toString().split('\n').take(5).join('\n')}');
    FlutterOTel.reportError('Uncaught', error, stack);
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
