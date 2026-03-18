import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/auth_credentials.dart';
import 'credential_store.dart';

/// [CredentialStore] implementation using `flutter_secure_storage`
/// for iOS Keychain and Android Keystore.
class SecureCredentialStore extends CredentialStore {
  SecureCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<AuthCredentials?> load() async {
    try {
      final json = await _storage.read(key: CredentialStore.storageKey);
      if (json == null) return null;
      final map = jsonDecode(json) as Map<String, dynamic>;
      return AuthCredentials.fromJson(map);
    } catch (_) {
      // Corrupted or unreadable data — return null rather than throwing.
      return null;
    }
  }

  @override
  Future<void> save(AuthCredentials credentials) async {
    final json = jsonEncode(credentials.toJson());
    await _storage.write(key: CredentialStore.storageKey, value: json);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: CredentialStore.storageKey);
  }

  @override
  Future<bool> get isAvailable async {
    try {
      // Attempt a no-op read to verify the storage backend is accessible.
      await _storage.read(key: CredentialStore.storageKey);
      return true;
    } catch (_) {
      return false;
    }
  }
}
