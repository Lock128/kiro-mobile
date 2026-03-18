import '../models/auth_credentials.dart';

/// Platform-agnostic interface for secure credential persistence.
///
/// Implementations use platform-appropriate secure storage:
/// - iOS: Keychain via `flutter_secure_storage`
/// - Android: Keystore via `flutter_secure_storage`
/// - Web: Encrypted localStorage
abstract class CredentialStore {
  /// Storage key used for persisting credentials.
  static const storageKey = 'kiro_auth_credentials';

  /// Loads stored credentials, or returns `null` if none exist
  /// or the stored data is corrupted.
  Future<AuthCredentials?> load();

  /// Saves [credentials] to the platform-specific secure store.
  Future<void> save(AuthCredentials credentials);

  /// Removes all stored credentials.
  Future<void> clear();

  /// Whether the underlying secure storage is available on this platform.
  Future<bool> get isAvailable;
}
