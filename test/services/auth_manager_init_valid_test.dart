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

/// Generators for valid [AuthCredentials] — non-empty token with future or
/// null expiresAt so that [isValid] is always true.
extension ValidAuthCredentialsAny on Any {
  /// Generates a [DateTime] in the future (at least 60 seconds from now).
  Generator<DateTime?> get futureOrNullDateTime {
    final futureDate = any.positiveIntOrZero.map(
      (ms) => DateTime.now().add(Duration(milliseconds: ms + 60000)),
    );
    return futureDate.nullable;
  }

  /// Generates valid [AuthCredentials] — non-empty token, future or null
  /// expiry, and random cookies.
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
  /// **Validates: Requirements 3.1**
  ///
  /// Property 3: Initialization with valid credentials yields authenticated state
  /// For any CredentialStore containing valid (non-expired, non-empty token)
  /// AuthCredentials, calling AuthManager.initialize() should result in the
  /// AuthState being authenticated.
  Glados(any.validAuthCredentials, ExploreConfig(numRuns: 100)).test(
    'Property 3: Initialization with valid credentials yields authenticated state',
    (AuthCredentials credentials) async {
      // Precondition: the generated credentials must be valid.
      expect(credentials.isValid, isTrue,
          reason: 'Generator should only produce valid credentials');

      final store = MockCredentialStore(storedCredentials: credentials);
      final authManager = AuthManager(credentialStore: store);

      await authManager.initialize();

      expect(authManager.state, equals(AuthState.authenticated));

      // Clean up ChangeNotifier to avoid leak warnings.
      authManager.dispose();
    },
  );
}
