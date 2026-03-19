import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutterrific_opentelemetry/flutterrific_opentelemetry.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';

import 'services/auth_manager.dart';
import 'services/connectivity_monitor.dart';
import 'services/credential_store_factory.dart';
import 'services/debug_log.dart';
import 'services/telemetry_config.dart';
import 'services/telemetry_service.dart';
import 'views/app_shell.dart';

void main() {
  final otelEnabled = TelemetryConfig.isConfigured;

  if (otelEnabled) {
    // Suppress noisy OTel metric exporter logs caused by a frozen-protobuf bug
    // in dartastic_opentelemetry's OtlpHttpMetricExporter.
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      if (record.loggerName.contains('OtlpHttp') &&
          record.level >= Level.SEVERE &&
          record.message.contains('read-only message')) {
        return;
      }
      debugPrint(
          '${record.level.name}: ${record.loggerName}: ${record.message}');
    });
  }

  // Catch Flutter framework errors (rendering, layout, etc.).
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    DebugLog.log('FlutterError: ${details.exceptionAsString()}');
    if (details.stack != null) {
      DebugLog.log(
          'Stack: ${details.stack.toString().split('\n').take(5).join('\n')}');
    }
    if (otelEnabled) {
      FlutterOTel.reportError('FlutterError', details.exception, details.stack);
    }
  };

  // Catch async errors that escape the Flutter framework.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    final TelemetryService telemetryService;

    if (otelEnabled) {
      final otel = FlutterOTelTelemetryService();
      await otel.initialize(
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
      telemetryService = otel;
    } else {
      DebugLog.log('OTel disabled — no OTEL_EXPORTER_OTLP_ENDPOINT configured');
      telemetryService = NoOpTelemetryService();
    }

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
    // Suppress known dartastic_opentelemetry frozen protobuf bug.
    final msg = error.toString();
    if (msg.contains('read-only message') &&
        msg.contains('InstrumentationScope')) {
      return;
    }

    DebugLog.log('Uncaught: $error');
    DebugLog.log('Stack: ${stack.toString().split('\n').take(5).join('\n')}');
    if (otelEnabled) {
      FlutterOTel.reportError('Uncaught', error, stack);
    }
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
