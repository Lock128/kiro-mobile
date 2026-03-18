import 'credential_store.dart';
import 'web_credential_store.dart';

/// Web platform implementation.
CredentialStore createCredentialStore() => WebCredentialStore();
