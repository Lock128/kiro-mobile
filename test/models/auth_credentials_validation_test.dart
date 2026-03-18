import 'package:glados/glados.dart';
import 'package:kiro_flutter_auth/models/auth_credentials.dart';

/// Custom generator for AuthCredentials that includes BOTH empty and non-empty
/// tokens, and past/future/null expiresAt values, to thoroughly test validation.
extension AuthCredentialsValidationAny on Any {
  /// Generates tokens that can be empty or non-empty.
  Generator<String> get tokenWithEmpty {
    return any.either(
      any.always(''),
      any.nonEmptyLetterOrDigits,
    );
  }

  /// Generates DateTime values that include both past and future dates, or null.
  Generator<DateTime?> get pastOrFutureDateTime {
    final pastDate = any.positiveIntOrZero.map(
      (ms) => DateTime.now().subtract(Duration(milliseconds: ms + 1000)),
    );
    final futureDate = any.positiveIntOrZero.map(
      (ms) => DateTime.now().add(Duration(milliseconds: ms + 60000)),
    );
    return any.either(pastDate, futureDate).nullable;
  }

  Generator<AuthCredentials> get authCredentialsForValidation {
    return combine3(
      any.tokenWithEmpty,
      any.pastOrFutureDateTime,
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
  /// **Validates: Requirements 3.3, 1.1, 3.1, 3.2**
  ///
  /// Property 2: Credential validation correctness
  /// For any AuthCredentials instance, isValid should return true if and only
  /// if the token is non-empty AND the credentials are not expired (either
  /// expiresAt is null or expiresAt is in the future). Conversely, isValid
  /// should return false for any credentials with an empty token or a past
  /// expiresAt.
  Glados(any.authCredentialsForValidation, ExploreConfig(numRuns: 100)).test(
    'Property 2: Credential validation correctness',
    (AuthCredentials credentials) {
      final expected = credentials.token.isNotEmpty && !credentials.isExpired;
      expect(credentials.isValid, equals(expected));
    },
  );
}
