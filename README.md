# kiro_flutter_auth

A cross-platform Flutter mobile application providing authentication and session management for the Kiro platform.

> **Alpha Version** -- This project is currently in an alpha stage of development. Features may be incomplete, APIs may change without notice, and the application has **not undergone any security validation or audit**. Do not use this application in production environments or with sensitive credentials until a formal security review has been completed.

## Overview

`kiro_flutter_auth` is built with Flutter and targets Android, iOS, and Web platforms. It provides:

- **Authentication flow** -- Sign-in views with WebView-based authentication
- **Secure credential storage** -- Platform-specific credential storage (using `flutter_secure_storage` on mobile, web-based storage on the web)
- **Session management** -- View and manage active sessions
- **Connectivity monitoring** -- Detect and respond to network state changes
- **Task management** -- View task details within the app

## Project Structure

```
lib/
  main.dart                  # Application entry point
  models/
    auth_credentials.dart    # Authentication credential models
    auth_state.dart          # Authentication state model
  services/
    auth_manager.dart        # Core authentication logic
    connectivity_monitor.dart# Network connectivity monitoring
    credential_store.dart    # Credential storage interface
    credential_store_factory.dart
    credential_store_factory_stub.dart
    credential_store_factory_web.dart
    secure_credential_store.dart  # Mobile secure storage implementation
    web_credential_store.dart     # Web storage implementation
    debug_log.dart           # Debug logging utility
    kiro_api.dart            # Kiro backend API client
  views/
    app_shell.dart           # Main app shell / scaffold
    home_view.dart           # Home screen
    sign_in_view.dart        # Mobile sign-in view
    sign_in_view_web.dart    # Web sign-in view
    content_view.dart        # Content display (mobile)
    content_view_web.dart    # Content display (web)
    session_detail_view.dart # Session details screen
    task_detail_view.dart    # Task details screen
    error_view.dart          # Error display
```

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart SDK ^3.11.1)
- Android Studio or Xcode (for mobile builds)
- A web browser (for web builds)

## Getting Started

1. **Clone the repository**

   ```bash
   git clone https://github.com/Lock128/kiro-mobile.git
   cd kiro-mobile
   ```

2. **Install dependencies**

   ```bash
   flutter pub get
   ```

3. **Run the application**

   ```bash
   # Android / iOS
   flutter run

   # Web
   flutter run -d chrome
   ```

## Key Dependencies

| Package | Purpose |
|---|---|
| `webview_flutter` | WebView integration for authentication flows |
| `flutter_secure_storage` | Encrypted credential storage on mobile |
| `connectivity_plus` | Network connectivity detection |
| `provider` | State management |
| `http` | HTTP networking for API calls |

## Testing

```bash
flutter test
```

The project uses `flutter_test` and `glados` (property-based testing).

## Disclaimer

This software is provided as-is in an **alpha** state. It has **not been security validated**, penetration tested, or audited. Use it at your own risk. The authors make no guarantees regarding the safety or reliability of authentication flows, credential storage, or data handling within this application.
