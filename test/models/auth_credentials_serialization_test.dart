import 'package:glados/glados.dart';
import 'package:kiro_flutter_auth/models/auth_credentials.dart';

/// Custom generator for AuthCredentials.
///
/// Generates random instances with:
/// - Random non-empty strings for token (letters/digits)
/// - Random `DateTime` or null for expiresAt
/// - Random cookie maps (`Map<String, String>`)
extension AuthCredentialsAny on Any {
  Generator<AuthCredentials> get authCredentials {
    return combine3(
      any.nonEmptyLetterOrDigits,
      any.dateTime.nullable,
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
  /// **Validates: Requirements 2.2**
  ///
  /// Property 1: Credential serialization round trip
  /// For any valid AuthCredentials instance, serializing to JSON via toJson()
  /// and then deserializing via AuthCredentials.fromJson() should produce an
  /// equivalent AuthCredentials object with the same token, expiresAt, and
  /// cookies values.
  Glados(any.authCredentials, ExploreConfig(numRuns: 100)).test(
    'Property 1: Credential serialization round trip',
    (AuthCredentials credentials) {
      final json = credentials.toJson();
      final restored = AuthCredentials.fromJson(json);

      expect(restored.token, equals(credentials.token));
      expect(restored.expiresAt, equals(credentials.expiresAt));
      expect(restored.cookies, equals(credentials.cookies));
    },
  );
}
