import 'package:glados/glados.dart';
import 'package:kiro_flutter_auth/models/auth_credentials.dart';
import 'package:kiro_flutter_auth/models/auth_state.dart';
import 'package:kiro_flutter_auth/services/auth_manager.dart';
import 'package:kiro_flutter_auth/services/credential_store.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// A mock [CredentialStore] that records calls and stores credentials in memory.
class MockCredentialStore implements CredentialStore {
  MockCredentialStore({this.storedCredentials});

  AuthCredentials? storedCredentials;
  bool saveCalled = false;
  bool clearCalled = false;
  AuthCredentials? savedCredentials;

  @override
  Future<AuthCredentials?> load() async => storedCredentials;

  @override
  Future<void> save(AuthCredentials credentials) async {
    storedCredentials = credentials;
    savedCredentials = credentials;
    saveCalled = true;
  }

  @override
  Future<void> clear() async {
    storedCredentials = null;
    clearCalled = true;
  }

  @override
  Future<bool> get isAvailable async => true;
}

/// A testable subclass of [AuthManager] that overrides [extractCredentials]
/// to return pre-configured credentials, avoiding the need for a real WebView.
class TestableAuthManager extends AuthManager {
  TestableAuthManager({
    required super.credentialStore,
    this.credentialsToExtract,
  });

  AuthCredentials? credentialsToExtract;

  @override
  Future<AuthCredentials?> extractCredentials(
      WebViewController controller) async {
    return credentialsToExtract;
  }
}

/// A fake [WebViewPlatform] so that [WebViewController] can be instantiated
/// in a test environment without a real platform plugin.
class FakeWebViewPlatform extends WebViewPlatform {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return FakePlatformWebViewController(params);
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    throw UnimplementedError();
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    throw UnimplementedError();
  }

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) {
    throw UnimplementedError();
  }
}

/// Minimal fake controller that satisfies the platform interface.
class FakePlatformWebViewController extends PlatformWebViewController {
  FakePlatformWebViewController(super.params) : super.implementation();
}

/// Generators for valid [AuthCredentials].
extension ValidAuthCredentialsAny on Any {
  Generator<DateTime?> get futureOrNullDateTime {
    final futureDate = any.positiveIntOrZero.map(
      (ms) => DateTime.now().add(Duration(milliseconds: ms + 60000)),
    );
    return futureDate.nullable;
  }

  Generator<AuthCredentials> get validAuthCredentials {
    return combine3(
      any.nonEmptyLetterOrDigits,
      any.futureOrNullDateTime,
      any.map(any.nonEmptyLetterOrDigits, any.letterOrDigits),
      (String token, DateTime? expiresAt, Map<String, String> cookies) {
        return AuthCredentials(
          token: token,
          expiresAt: expiresAt,
          cookies: cookies,
        );
      },
    );
  }
}

void main() {
  setUpAll(() {
    WebViewPlatform.instance = FakeWebViewPlatform();
  });

  /// **Validates: Requirements 2.1, 2.4**
  ///
  /// Property 5: Successful credential capture transitions to authenticated
  /// For any valid AuthCredentials extracted from a sign-in flow, calling
  /// AuthManager.handleSignInComplete() should store the credentials in the
  /// CredentialStore and transition the AuthState to authenticated.
  Glados(any.validAuthCredentials, ExploreConfig(numRuns: 100)).test(
    'Property 5: Successful credential capture transitions to authenticated',
    (AuthCredentials credentials) async {
      // Precondition: the generated credentials must be valid.
      expect(credentials.isValid, isTrue,
          reason: 'Generator should only produce valid credentials');

      final store = MockCredentialStore();
      final authManager = TestableAuthManager(
        credentialStore: store,
        credentialsToExtract: credentials,
      );

      // Create a dummy controller — it won't be used since
      // extractCredentials is overridden.
      final controller = WebViewController();

      await authManager.handleSignInComplete(controller);

      expect(authManager.state, equals(AuthState.authenticated));
      expect(store.saveCalled, isTrue,
          reason: 'save() should be called with the extracted credentials');
      expect(store.savedCredentials?.token, equals(credentials.token),
          reason: 'The saved credentials should match the extracted ones');

      authManager.dispose();
    },
  );
}
