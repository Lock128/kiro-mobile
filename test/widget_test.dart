import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:kiro_flutter_auth/main.dart';
import 'package:kiro_flutter_auth/services/auth_manager.dart';
import 'package:kiro_flutter_auth/services/connectivity_monitor.dart';
import 'package:kiro_flutter_auth/services/credential_store.dart';
import 'package:kiro_flutter_auth/models/auth_credentials.dart';

import 'dart:async';

/// Minimal fake implementations for the smoke test.
class _FakeCredentialStore extends CredentialStore {
  @override
  Future<AuthCredentials?> load() async => null;
  @override
  Future<void> save(AuthCredentials credentials) async {}
  @override
  Future<void> clear() async {}
  @override
  Future<bool> get isAvailable async => true;
}

class _FakeConnectivityMonitor implements ConnectivityMonitor {
  @override
  Stream<bool> get isConnected => const Stream.empty();
  @override
  Future<bool> checkConnectivity() async => true;
  @override
  void dispose() {}
}

void main() {
  testWidgets('KiroApp renders without crashing', (WidgetTester tester) async {
    final authManager = AuthManager(credentialStore: _FakeCredentialStore());
    final connectivityMonitor = _FakeConnectivityMonitor();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthManager>.value(value: authManager),
          Provider<ConnectivityMonitor>.value(value: connectivityMonitor),
        ],
        child: const KiroApp(),
      ),
    );

    // The app should render — initially showing a loading indicator
    // while AuthManager is in the unknown state.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
