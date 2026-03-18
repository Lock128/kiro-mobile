import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiro_flutter_auth/models/auth_credentials.dart';
import 'package:kiro_flutter_auth/services/credential_store.dart';
import 'package:kiro_flutter_auth/services/secure_credential_store.dart';

/// A test platform that can optionally throw on every operation,
/// used to simulate storage failures for [isAvailable] testing.
class ThrowingSecureStoragePlatform extends FlutterSecureStoragePlatform {
  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      throw Exception('Storage unavailable');

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async =>
      throw Exception('Storage unavailable');

  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      throw Exception('Storage unavailable');

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      throw Exception('Storage unavailable');

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      throw Exception('Storage unavailable');

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async =>
      throw Exception('Storage unavailable');
}

void main() {
  group('SecureCredentialStore', () {
    late SecureCredentialStore store;

    setUp(() {
      // Initialize with empty mock storage before each test.
      FlutterSecureStorage.setMockInitialValues({});
      store = SecureCredentialStore();
    });

    group('save/load/clear cycle', () {
      test('save() stores credentials and load() returns them', () async {
        final credentials = AuthCredentials(
          token: 'test-token-123',
          expiresAt: DateTime.utc(2099, 12, 31),
          cookies: {'session': 'abc', 'csrf': 'xyz'},
        );

        await store.save(credentials);
        final loaded = await store.load();

        expect(loaded, isNotNull);
        expect(loaded!.token, equals('test-token-123'));
        expect(loaded.expiresAt, equals(DateTime.utc(2099, 12, 31)));
        expect(loaded.cookies, equals({'session': 'abc', 'csrf': 'xyz'}));
      });

      test('clear() removes stored credentials', () async {
        final credentials = AuthCredentials(
          token: 'to-be-cleared',
          expiresAt: DateTime.utc(2099, 1, 1),
        );

        await store.save(credentials);
        await store.clear();
        final loaded = await store.load();

        expect(loaded, isNull);
      });

      test('save() overwrites previously stored credentials', () async {
        final first = AuthCredentials(token: 'first-token');
        final second = AuthCredentials(
          token: 'second-token',
          cookies: {'key': 'value'},
        );

        await store.save(first);
        await store.save(second);
        final loaded = await store.load();

        expect(loaded, isNotNull);
        expect(loaded!.token, equals('second-token'));
        expect(loaded.cookies, equals({'key': 'value'}));
      });
    });

    group('load() edge cases', () {
      test('returns null when storage is empty', () async {
        final loaded = await store.load();
        expect(loaded, isNull);
      });

      test('returns null when stored data is invalid JSON', () async {
        // Manually write corrupted data into the mock storage.
        FlutterSecureStorage.setMockInitialValues({
          CredentialStore.storageKey: 'not-valid-json{{{',
        });
        store = SecureCredentialStore();

        final loaded = await store.load();
        expect(loaded, isNull);
      });

      test('returns null when stored JSON is missing required fields',
          () async {
        // Valid JSON but missing the 'token' field.
        FlutterSecureStorage.setMockInitialValues({
          CredentialStore.storageKey: jsonEncode({'cookies': {}}),
        });
        store = SecureCredentialStore();

        final loaded = await store.load();
        expect(loaded, isNull);
      });

      test('returns null when stored JSON has wrong types', () async {
        FlutterSecureStorage.setMockInitialValues({
          CredentialStore.storageKey: jsonEncode({
            'token': 12345, // should be String
            'expiresAt': 'not-a-date',
            'cookies': 'not-a-map',
          }),
        });
        store = SecureCredentialStore();

        final loaded = await store.load();
        expect(loaded, isNull);
      });
    });

    group('isAvailable', () {
      test('returns true when storage works', () async {
        final available = await store.isAvailable;
        expect(available, isTrue);
      });

      test('returns false when storage throws', () async {
        // Replace the platform with one that always throws.
        final originalPlatform = FlutterSecureStoragePlatform.instance;
        FlutterSecureStoragePlatform.instance =
            ThrowingSecureStoragePlatform();

        final failingStore = SecureCredentialStore();
        final available = await failingStore.isAvailable;
        expect(available, isFalse);

        // Restore original platform for other tests.
        FlutterSecureStoragePlatform.instance = originalPlatform;
      });
    });
  });
}
