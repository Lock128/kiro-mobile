import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'package:kiro_flutter_auth/models/auth_credentials.dart';
import 'package:kiro_flutter_auth/models/auth_state.dart';
import 'package:kiro_flutter_auth/services/auth_manager.dart';
import 'package:kiro_flutter_auth/services/connectivity_monitor.dart';
import 'package:kiro_flutter_auth/services/credential_store.dart';
import 'package:kiro_flutter_auth/views/app_shell.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class MockCredentialStore implements CredentialStore {
  @override
  Future<AuthCredentials?> load() async => null;
  @override
  Future<void> save(AuthCredentials credentials) async {}
  @override
  Future<void> clear() async {}
  @override
  Future<bool> get isAvailable async => true;
}

/// A fake [AuthManager] that lets tests control state directly.
class FakeAuthManager extends ChangeNotifier implements AuthManager {
  AuthState _state = AuthState.unknown;
  AuthCredentials? _credentials;

  @override
  AuthState get state => _state;

  void setFakeState(AuthState newState) {
    _state = newState;
    notifyListeners();
  }

  @override
  AuthCredentials? get credentials => _credentials;

  @override
  Stream<AuthState> get stateStream => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> handleSignInComplete(WebViewController controller) async {}

  @override
  Future<AuthCredentials?> extractCredentials(
      WebViewController controller) async =>
      null;

  @override
  Future<void> validateCredentials() async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> handleAuthError() async {}
}

/// A fake [ConnectivityMonitor] with controllable stream.
class FakeConnectivityMonitor implements ConnectivityMonitor {
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  @override
  Stream<bool> get isConnected => _controller.stream;

  @override
  Future<bool> checkConnectivity() async => true;

  void emitConnected(bool value) => _controller.add(value);

  @override
  void dispose() => _controller.close();
}

// ---------------------------------------------------------------------------
// Fake WebView platform
// ---------------------------------------------------------------------------

class FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) => FakePlatformWebViewController(params);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => FakePlatformNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => FakePlatformWebViewWidget(params);

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) => FakePlatformCookieManager(params);
}

class FakePlatformWebViewController extends PlatformWebViewController {
  FakePlatformWebViewController(super.params) : super.implementation();

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
      PlatformNavigationDelegate handler) async {}

  @override
  Future<void> loadRequest(LoadRequestParams params) async {}

  @override
  Future<String?> currentUrl() async => 'https://app.kiro.dev/signin';

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async => '""';
}

class FakePlatformNavigationDelegate extends PlatformNavigationDelegate {
  FakePlatformNavigationDelegate(super.params) : super.implementation();

  @override
  Future<void> setOnNavigationRequest(
      NavigationRequestCallback onNavigationRequest) async {}

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {}

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {}

  @override
  Future<void> setOnWebResourceError(
      WebResourceErrorCallback onWebResourceError) async {}

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback onHttpError) async {}

  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async {}

  @override
  Future<void> setOnHttpAuthRequest(
      HttpAuthRequestCallback onHttpAuthRequest) async {}
}

class FakePlatformWebViewWidget extends PlatformWebViewWidget {
  FakePlatformWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class FakePlatformCookieManager extends PlatformWebViewCookieManager {
  FakePlatformCookieManager(super.params) : super.implementation();

  @override
  Future<bool> clearCookies() async => true;

  @override
  Future<void> setCookie(WebViewCookie cookie) async {}
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget buildTestApp({
  required FakeAuthManager authManager,
  required FakeConnectivityMonitor connectivityMonitor,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthManager>.value(value: authManager),
      Provider<ConnectivityMonitor>.value(value: connectivityMonitor),
    ],
    child: const MaterialApp(home: AppShell()),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    WebViewPlatform.instance = FakeWebViewPlatform();
  });

  group('AppShell', () {
    late FakeAuthManager authManager;
    late FakeConnectivityMonitor connectivityMonitor;

    setUp(() {
      authManager = FakeAuthManager();
      connectivityMonitor = FakeConnectivityMonitor();
    });

    tearDown(() {
      authManager.dispose();
      connectivityMonitor.dispose();
    });

    testWidgets('shows loading indicator for AuthState.unknown',
        (tester) async {
      authManager.setFakeState(AuthState.unknown);

      await tester.pumpWidget(
        buildTestApp(
          authManager: authManager,
          connectivityMonitor: connectivityMonitor,
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows SignInView for AuthState.unauthenticated',
        (tester) async {
      authManager.setFakeState(AuthState.unauthenticated);

      await tester.pumpWidget(
        buildTestApp(
          authManager: authManager,
          connectivityMonitor: connectivityMonitor,
        ),
      );
      // Don't use pumpAndSettle — the loading indicator animation never settles.
      await tester.pump();

      // SignInView starts with _isLoading = true, so a
      // CircularProgressIndicator should be visible.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows ContentView for AuthState.authenticated',
        (tester) async {
      authManager.setFakeState(AuthState.authenticated);

      await tester.pumpWidget(
        buildTestApp(
          authManager: authManager,
          connectivityMonitor: connectivityMonitor,
        ),
      );
      // Pump to let async _initWebView complete.
      await tester.pump();

      // ContentView has an AppBar with title 'Kiro' and a sign-out button.
      expect(find.text('Kiro'), findsOneWidget);
      expect(find.byIcon(Icons.logout), findsOneWidget);
    });

    testWidgets('shows ErrorView for AuthState.error', (tester) async {
      authManager.setFakeState(AuthState.error);

      await tester.pumpWidget(
        buildTestApp(
          authManager: authManager,
          connectivityMonitor: connectivityMonitor,
        ),
      );

      expect(find.text('Something went wrong. Please try again.'),
          findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('transitions from unknown to authenticated updates view',
        (tester) async {
      authManager.setFakeState(AuthState.unknown);

      await tester.pumpWidget(
        buildTestApp(
          authManager: authManager,
          connectivityMonitor: connectivityMonitor,
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Transition to authenticated.
      authManager.setFakeState(AuthState.authenticated);
      await tester.pump();

      expect(find.text('Kiro'), findsOneWidget);
    });

    testWidgets('shows offline overlay when connectivity is lost',
        (tester) async {
      authManager.setFakeState(AuthState.unknown);

      await tester.pumpWidget(
        buildTestApp(
          authManager: authManager,
          connectivityMonitor: connectivityMonitor,
        ),
      );

      // Emit offline event.
      connectivityMonitor.emitConnected(false);
      await tester.pump();

      expect(find.text('No internet connection'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    });
  });
}
