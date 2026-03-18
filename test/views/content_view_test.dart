import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'package:kiro_flutter_auth/models/auth_credentials.dart';
import 'package:kiro_flutter_auth/models/auth_state.dart';
import 'package:kiro_flutter_auth/services/auth_manager.dart';
import 'package:kiro_flutter_auth/services/credential_store.dart';
import 'package:kiro_flutter_auth/views/content_view.dart';

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

class FakeAuthManager extends ChangeNotifier implements AuthManager {
  final AuthState _state = AuthState.authenticated;
  bool signOutCalled = false;

  @override
  AuthState get state => _state;

  @override
  AuthCredentials? get credentials => AuthCredentials(
        token: 'test-token',
        cookies: {'session': 'abc'},
      );

  @override
  Stream<AuthState> get stateStream => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> handleSignInComplete(WebViewController controller) async {}
  @override
  Future<AuthCredentials?> extractCredentials(
      WebViewController controller) async => null;
  @override
  Future<void> validateCredentials() async {}

  @override
  Future<void> signOut() async {
    signOutCalled = true;
  }

  @override
  Future<void> handleAuthError() async {}
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
  Future<String?> currentUrl() async => 'https://app.kiro.dev/';
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
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    WebViewPlatform.instance = FakeWebViewPlatform();
  });

  group('ContentView', () {
    late FakeAuthManager authManager;

    setUp(() {
      authManager = FakeAuthManager();
    });

    tearDown(() {
      authManager.dispose();
    });

    Widget buildContentView() {
      return ChangeNotifierProvider<AuthManager>.value(
        value: authManager,
        child: const MaterialApp(home: ContentView()),
      );
    }

    testWidgets('shows AppBar with title and sign-out button',
        (tester) async {
      await tester.pumpWidget(buildContentView());
      // Pump to let async _initWebView complete.
      await tester.pump();

      expect(find.text('Kiro'), findsOneWidget);
      expect(find.byIcon(Icons.logout), findsOneWidget);
      expect(find.byTooltip('Sign out'), findsOneWidget);
    });

    testWidgets('sign-out button calls AuthManager.signOut()',
        (tester) async {
      await tester.pumpWidget(buildContentView());
      await tester.pump();

      await tester.tap(find.byIcon(Icons.logout));
      await tester.pump();

      expect(authManager.signOutCalled, isTrue);
    });

    testWidgets('shows loading indicator initially', (tester) async {
      await tester.pumpWidget(buildContentView());
      await tester.pump();

      // ContentView starts with _isLoading = true.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
