import 'credential_store.dart';
import 'credential_store_factory_stub.dart'
    if (dart.library.html) 'credential_store_factory_web.dart'
    if (dart.library.js_interop) 'credential_store_factory_web.dart'
    as platform;

/// Creates the platform-appropriate [CredentialStore].
///
/// On web, returns a [WebCredentialStore].
/// On iOS/Android, returns a [SecureCredentialStore].
CredentialStore createCredentialStore() => platform.createCredentialStore();
