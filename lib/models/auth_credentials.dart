/// Model holding the extracted authentication data.
class AuthCredentials {
  AuthCredentials({
    required this.token,
    this.expiresAt,
    this.cookies = const {},
    this.csrfToken,
    this.bearerToken,
  });

  /// Primary auth token (JWT or session token).
  final String token;

  /// Token expiration timestamp (null if no expiry).
  final DateTime? expiresAt;

  /// Cookies extracted from WebView after sign-in.
  final Map<String, String> cookies;

  /// CSRF token for API requests.
  final String? csrfToken;

  /// Bearer token for API authorization header.
  final String? bearerToken;

  /// Whether the credentials have expired.
  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// Whether the credentials are valid (non-empty token and not expired).
  bool get isValid => token.isNotEmpty && !isExpired;

  /// Serializes credentials to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'token': token,
        'expiresAt': expiresAt?.toIso8601String(),
        'cookies': cookies,
        'csrfToken': csrfToken,
        'bearerToken': bearerToken,
      };

  /// Deserializes credentials from a JSON map.
  factory AuthCredentials.fromJson(Map<String, dynamic> json) =>
      AuthCredentials(
        token: json['token'] as String,
        expiresAt: json['expiresAt'] != null
            ? DateTime.parse(json['expiresAt'] as String)
            : null,
        cookies: Map<String, String>.from(json['cookies'] as Map? ?? {}),
        csrfToken: json['csrfToken'] as String?,
        bearerToken: json['bearerToken'] as String?,
      );
}
