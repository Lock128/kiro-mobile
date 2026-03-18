import 'package:glados/glados.dart';
import 'package:kiro_flutter_auth/models/auth_credentials.dart';
import 'package:kiro_flutter_auth/models/auth_state.dart';
import 'package:kiro_flutter_auth/services/auth_manager.dart';
import 'package:kiro_flutter_auth/services/credential_store.dart';

/// A mock [CredentialStore] that records calls and stores credentials in memory.
class MockCredentialStore implements CredentialStore {
  MockCredentialStore({this.storedCredentials});

  AuthCredentials? storedCredentials;
  bool saveCalled = false;
  bool clearCalled = false;

  @override
  Future<AuthCredentials?> load() async => storedCredentials;

  @override
  Future<void> save(AuthCredentials credentials) async {
    storedCredentials = credentials;
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
  /// **Validates: Requirements 6.2**
  ///
  /// Property 7: Auth error clears credentials and transitions to unauthenticated
  /// For any AuthManager in an authenticated state, calling handleAuthError()
  /// should clear all credentials from the CredentialStore and transition the
  /// AuthState to unauthenticated.
  Glados(any.validAuthCredentials, ExploreConfig(numRuns: 100)).test(
    'Property 7: Auth error clears credentials and transitions to unauthenticated',
    (AuthCredentials credentials) async {
      // Precondition: the generated credentials must be valid.
      expect(credentials.isValid, isTrue,
          reason: 'Generator should only produce valid credentials');

      // Set up store with credentials and initialize to authenticated state.
      final store = MockCredentialStore(storedCredentials: credentials);
      final authManager = AuthManager(credentialStore: store);

      await authManager.initialize();
      expect(authManager.state, equals(AuthState.authenticated),
          reason:
              'AuthManager should be authenticated after init with valid credentials');

      // Act: handle auth error (e.g. HTTP 401).
      await authManager.handleAuthError();

      // Assert: state transitions to unauthenticated.
      expect(authManager.state, equals(AuthState.unauthenticated));

      // Assert: store was cleared.
      expect(store.clearCalled, isTrue,
          reason: 'clear() should be called during handleAuthError');
      expect(store.storedCredentials, isNull,
          reason: 'Stored credentials should be null after auth error');

      // Clean up ChangeNotifier to avoid leak warnings.
      authManager.dispose();
    },
  );
}
