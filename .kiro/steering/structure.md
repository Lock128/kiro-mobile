# Project Structure

```
lib/
  main.dart                 # Entry point — sets up providers and runs KiroApp
  models/                   # Data classes (immutable where possible)
    auth_credentials.dart   # Auth token/cookie model with JSON serialization
    auth_state.dart         # Enum for auth lifecycle states
  services/                 # Business logic and platform abstractions
    auth_manager.dart       # Core auth lifecycle (ChangeNotifier + Stream)
    connectivity_monitor.dart # Abstract interface + connectivity_plus impl
    credential_store.dart   # Abstract CredentialStore interface
    credential_store_factory.dart # Conditional import dispatcher
    credential_store_factory_stub.dart # Mobile factory (SecureCredentialStore)
    credential_store_factory_web.dart  # Web factory (WebCredentialStore)
    secure_credential_store.dart       # flutter_secure_storage impl
    web_credential_store.dart          # Browser localStorage impl
    kiro_api.dart           # HTTP client for Kiro backend
    debug_log.dart          # Debug logging utility
  views/                    # UI layer (StatefulWidget / StatelessWidget)
    app_shell.dart          # Root scaffold with NavigationBar and auth routing
    home_view.dart          # Authenticated home tabs (Create, Chats, Tasks)
    sign_in_view.dart       # Mobile WebView sign-in
    sign_in_view_web.dart   # Web popup sign-in
    sign_in_view_stub.dart  # Stub for conditional import
    content_view.dart       # Mobile authenticated content
    content_view_web.dart   # Web authenticated content
    session_detail_view.dart
    task_detail_view.dart
    error_view.dart
test/                       # Mirrors lib/ structure
  models/                   # Model serialization and validation tests
  services/                 # Service unit tests (one file per concern)
  views/                    # Widget tests
scripts/
  compliance_check.sh       # Compliance checking script
assets/
  kiro_ghost.jpg            # App icon source
```

## Architecture Patterns
- **State management**: `Provider` + `ChangeNotifier` (AuthManager). Views use `Consumer<AuthManager>` and `context.read<T>()`.
- **Platform abstraction**: Conditional imports via `if (dart.library.js_interop)` for web vs mobile implementations. Each platform concern has a factory, a stub, and a web variant.
- **Service interfaces**: Abstract classes define contracts (`CredentialStore`, `ConnectivityMonitor`). Concrete implementations are injected via constructors.
- **View routing**: `AppShell` switches body content based on `AuthState` enum. Authenticated content uses `IndexedStack` for tab persistence.
- **Naming**: Files use `snake_case`. Web-specific files are suffixed `_web.dart`, stubs `_stub.dart`. Tests are suffixed `_test.dart` and named by concern (e.g. `auth_manager_sign_in_test.dart`).
