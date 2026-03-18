import 'package:glados/glados.dart';
import 'package:kiro_flutter_auth/models/auth_credentials.dart';
import 'package:kiro_flutter_auth/models/auth_state.dart';
import 'package:kiro_flutter_auth/services/auth_manager.dart';
import 'package:kiro_flutter_auth/services/credential_store.dart';

/// A mock [CredentialStore] that returns pre-configured credentials from
/// [load()] and reports [isAvailable] as true.
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

/// Generators for invalid [AuthCredentials] — empty token OR past expiresAt
/// so that [isValid] is always false.
extension InvalidAuthCredentialsAny on Any {
  /// Generates a [DateTime] in the past (at least 60 seconds ago).
  Generator<DateTime> get pastDateTime {
    return any.positiveIntOrZero.map(
      (ms) => DateTime.now().subtract(Duration(milliseconds: ms + 60000)),
    );
  }

  /// Generates invalid [AuthCredentials] with an empty token and any expiry.
  Generator<AuthCredentials> get emptyTokenCredentials {
    return combine3(
      any.always(''),
      any.pastDateTime.nullable,
      any.map(any.letterOrDigits, any.letterOrDigits),
      (String token, DateTime? expiresAt, Map<String, String> cookies) {
        return AuthCredentials(
          token: token,
          expiresAt: expiresAt,
          cookies: cookies,
        );
      },
    );
  }

  /// Generates invalid [AuthCredentials] with a non-empty token but past expiry.
  Generator<AuthCredentials> get expiredTokenCredentials {
    return combine3(
      any.nonEmptyLetterOrDigits,
      any.pastDateTime,
      any.map(any.letterOrDigits, any.letterOrDigits),
      (String token, DateTime expiresAt, Map<String, String> cookies) {
        return AuthCredentials(
          token: token,
          expiresAt: expiresAt,
          cookies: cookies,
        );
      },
    );
  }

  /// Generates invalid [AuthCredentials] — either empty token or expired.
  Generator<AuthCredentials> get invalidAuthCredentials {
    return any.either(
      any.emptyTokenCredentials,
      any.expiredTokenCredentials,
    );
  }
}

void main() {
  /// **Validates: Requirements 1.1, 3.2**
  ///
  /// Property 4: Initialization with invalid or missing credentials yields
  /// unauthenticated state.
  ///
  /// For any CredentialStore that is empty or contains invalid AuthCredentials
  /// (empty token or expired), calling AuthManager.initialize() should result
  /// in AuthState.unauthenticated and the store being cleared.
  Glados(any.invalidAuthCredentials, ExploreConfig(numRuns: 100)).test(
    'Property 4: Invalid credentials yield unauthenticated state and clear() is called',
    (AuthCredentials credentials) async {
      // Precondition: the generated credentials must be invalid.
      expect(credentials.isValid, isFalse,
          reason: 'Generator should only produce invalid credentials');

      final store = MockCredentialStore(storedCredentials: credentials);
      final authManager = AuthManager(credentialStore: store);

      await authManager.initialize();

      expect(authManager.state, equals(AuthState.unauthenticated));
      expect(store.clearCalled, isTrue,
          reason: 'clear() should be called for non-null invalid credentials');

      authManager.dispose();
    },
  );

  /// Null credentials case — no stored credentials at all.
  test(
    'Property 4: Null credentials yield unauthenticated state',
    () async {
      final store = MockCredentialStore(storedCredentials: null);
      final authManager = AuthManager(credentialStore: store);

      await authManager.initialize();

      expect(authManager.state, equals(AuthState.unauthenticated));
      // clear() should NOT be called when credentials are null.
      expect(store.clearCalled, isFalse,
          reason: 'clear() should not be called when no credentials exist');

      authManager.dispose();
    },
  );
}
