/// Represents the current authentication state of the app.
enum AuthState {
  /// Initial state, checking credentials.
  unknown,

  /// No valid credentials, show sign-in.
  unauthenticated,

  /// Valid credentials, show content.
  authenticated,

  /// Error state (network, storage, etc.).
  error,
}
