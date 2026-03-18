import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'package:kiro_flutter_auth/models/auth_credentials.dart';
import 'package:kiro_flutter_auth/models/auth_state.dart';
import 'package:kiro_flutter_auth/services/auth_manager.dart';
import 'package:kiro_flutter_auth/services/credential_store.dart';
import 'package:kiro_flutter_auth/views/sign_in_view.dart';

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
  final AuthState _state = AuthState.unauthenticated;
  bool handleSignInCompleteCalled = false;

  @override
  AuthState get state => _state;
  @override
  AuthCredentials? get credentials => null;
  @override
  Stream<AuthState> get stateStream => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> handleSignInComplete(WebViewController controller) async {
    handleSignInCompleteCalled = true;
  }
  @override
  Future<AuthCredentials?> extractCredentials(
      WebViewController controller) async => null;
  @override
  Future<void> validateCredentials() async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<void> handleAuthError() async {}
}

// ---------------------------------------------------------------------------
// Fake WebView platform that captures navigation delegate callbacks
// ---------------------------------------------------------------------------

PageEventCallback? _capturedOnPageFinished;
WebResourceErrorCallback? _capturedOnWebResourceError;

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
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {
    _capturedOnPageFinished = onPageFinished;
  }

  @override
  Future<void> setOnWebResourceError(
      WebResourceErrorCallback onWebResourceError) async {
    _capturedOnWebResourceError = onWebResourceError;
  }

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

  setUp(() {
    _capturedOnPageFinished = null;
    _capturedOnWebResourceError = null;
  });

  group('SignInView', () {
    late FakeAuthManager authManager;

    setUp(() {
      authManager = FakeAuthManager();
    });

    tearDown(() {
      authManager.dispose();
    });

    Widget buildSignInView() {
      return ChangeNotifierProvider<AuthManager>.value(
        value: authManager,
        child: const MaterialApp(home: SignInView()),
      );
    }

    testWidgets('shows loading indicator initially', (tester) async {
      await tester.pumpWidget(buildSignInView());

      // SignInView starts with _isLoading = true, so a
      // CircularProgressIndicator should be visible.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('hides loading indicator after page finishes loading',
        (tester) async {
      await tester.pumpWidget(buildSignInView());
      await tester.pump(); // let initState run

      // Simulate page finished callback.
      _capturedOnPageFinished?.call('https://app.kiro.dev/signin');
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows error message on web resource error', (tester) async {
      await tester.pumpWidget(buildSignInView());
      await tester.pump();

      // Simulate a web resource error on the main frame.
      _capturedOnWebResourceError?.call(
        WebResourceError(
          errorCode: -1,
          description: 'Network error',
          isForMainFrame: true,
          errorType: WebResourceErrorType.connect,
        ),
      );
      await tester.pump();

      expect(find.text('Network error'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });
}
