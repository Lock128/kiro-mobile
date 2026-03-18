import 'credential_store.dart';
import 'secure_credential_store.dart';

/// Non-web (iOS/Android) implementation.
CredentialStore createCredentialStore() => SecureCredentialStore();
