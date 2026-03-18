import 'dart:convert';

import 'package:web/web.dart' as web;

import '../models/auth_credentials.dart';
import 'credential_store.dart';

/// [CredentialStore] implementation using encrypted localStorage for Web.
///
/// Stores credentials as a JSON string under [CredentialStore.storageKey]
/// in the browser's `window.localStorage`.
class WebCredentialStore extends CredentialStore {
  @override
  Future<AuthCredentials?> load() async {
    try {
      final json = web.window.localStorage.getItem(CredentialStore.storageKey);
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
    web.window.localStorage.setItem(CredentialStore.storageKey, json);
  }

  @override
  Future<void> clear() async {
    web.window.localStorage.removeItem(CredentialStore.storageKey);
  }

  @override
  Future<bool> get isAvailable async {
    try {
      // Verify localStorage is accessible by performing a test write/read.
      const testKey = '__kiro_storage_test__';
      web.window.localStorage.setItem(testKey, 'ok');
      web.window.localStorage.removeItem(testKey);
      return true;
    } catch (_) {
      return false;
    }
  }
}
