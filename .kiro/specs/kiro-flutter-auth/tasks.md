# Implementation Plan: Kiro Flutter Auth

## Overview

Implement a Flutter authentication flow that uses WebView to display the Kiro sign-in page, captures credentials, persists them securely per platform, and renders authenticated content. The implementation follows the state-driven architecture defined in the design document, building incrementally from data models through auth logic to UI components.

## Tasks

- [x] 1. Set up project dependencies and core data models
  - [x] 1.1 Add required dependencies to `pubspec.yaml`
    - Add `webview_flutter`, `webview_flutter_web`, `flutter_secure_storage`, `connectivity_plus`, `provider`, and `glados` (dev dependency)
    - _Requirements: 8.1_

  - [x] 1.2 Create `AuthState` enum and `AuthCredentials` model
    - Create `lib/models/auth_state.dart` with the `AuthState` enum (`unknown`, `unauthenticated`, `authenticated`, `error`)
    - Create `lib/models/auth_credentials.dart` with `AuthCredentials` class including `token`, `expiresAt`, `cookies` fields, `isExpired`/`isValid` getters, and `toJson()`/`fromJson()` serialization
    - _Requirements: 1.1, 3.1, 3.2, 3.3_

  - [x] 1.3 Write property test: Credential serialization round trip
    - **Property 1: Credential serialization round trip**
    - Generate random `AuthCredentials` instances and assert `AuthCredentials.fromJson(credentials.toJson())` produces an equivalent object
    - **Validates: Requirements 2.2**

  - [x] 1.4 Write property test: Credential validation correctness
    - **Property 2: Credential validation correctness**
    - Generate random `AuthCredentials` with varying token lengths and expiresAt values, assert `isValid == (token.isNotEmpty && !isExpired)`
    - **Validates: Requirements 3.3, 1.1, 3.1, 3.2**

- [x] 2. Implement CredentialStore with platform-specific storage
  - [x] 2.1 Create `CredentialStore` abstract interface and platform implementations
    - Create `lib/services/credential_store.dart` with abstract `CredentialStore` class defining `load()`, `save()`, `clear()`, and `isAvailable`
    - Create `lib/services/secure_credential_store.dart` implementing `CredentialStore` using `flutter_secure_storage` for iOS Keychain and Android Keystore
    - Create `lib/services/web_credential_store.dart` implementing `CredentialStore` using encrypted localStorage for Web
    - Store credentials as JSON string under key `kiro_auth_credentials`
    - _Requirements: 2.2, 2.3, 8.2, 8.3, 8.4_

  - [x] 2.2 Write unit tests for CredentialStore implementations
    - Test save/load/clear cycle with mocked secure storage
    - Test `isAvailable` returns correct value
    - Test handling of corrupted stored data
    - _Requirements: 2.2, 2.3_

- [x] 3. Implement AuthManager
  - [x] 3.1 Create `AuthManager` implementation
    - Create `lib/services/auth_manager.dart` with concrete `AuthManager` class
    - Implement `initialize()`: load from `CredentialStore`, validate, set state to `authenticated` or `unauthenticated`
    - Implement `handleSignInComplete()`: extract credentials from WebView cookies/navigation, save to store, transition to `authenticated`
    - Implement `extractCredentials()`: read cookies and tokens from WebView controller
    - Implement `validateCredentials()`: check `isValid` on stored credentials
    - Implement `signOut()`: clear `CredentialStore`, clear WebView data, transition to `unauthenticated`
    - Implement `handleAuthError()`: clear credentials, transition to `unauthenticated`
    - Expose `state` and `stateStream` for UI consumption via `ChangeNotifier` or `Stream`
    - _Requirements: 1.1, 2.1, 2.4, 3.1, 3.2, 3.3, 5.2, 5.3, 5.4, 6.1, 6.2_

  - [x] 3.2 Write property test: Initialization with valid credentials yields authenticated state
    - **Property 3: Initialization with valid credentials yields authenticated state**
    - Generate random valid `AuthCredentials`, mock `CredentialStore.load()` to return them, assert `initialize()` results in `AuthState.authenticated`
    - **Validates: Requirements 3.1**

  - [x] 3.3 Write property test: Initialization with invalid or missing credentials yields unauthenticated state
    - **Property 4: Initialization with invalid or missing credentials yields unauthenticated state**
    - Generate random invalid `AuthCredentials` (empty token or past expiry) or null, mock store, assert `initialize()` results in `AuthState.unauthenticated` and `clear()` was called
    - **Validates: Requirements 1.1, 3.2**

  - [x] 3.4 Write property test: Successful credential capture transitions to authenticated
    - **Property 5: Successful credential capture transitions to authenticated**
    - Generate random valid `AuthCredentials`, call `handleSignInComplete()` with mocked extraction, assert state is `authenticated` and `save()` was called
    - **Validates: Requirements 2.1, 2.4**

  - [x] 3.5 Write property test: Sign-out clears credentials and transitions to unauthenticated
    - **Property 6: Sign-out clears credentials and transitions to unauthenticated**
    - Start from authenticated state, call `signOut()`, assert store is cleared and state is `unauthenticated`
    - **Validates: Requirements 5.2, 5.4**

  - [x] 3.6 Write property test: Auth error clears credentials and transitions to unauthenticated
    - **Property 7: Auth error clears credentials and transitions to unauthenticated**
    - Start from authenticated state, call `handleAuthError()`, assert store is cleared and state is `unauthenticated`
    - **Validates: Requirements 6.2**

- [x] 4. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Implement ConnectivityMonitor
  - [x] 5.1 Create `ConnectivityMonitor` implementation
    - Create `lib/services/connectivity_monitor.dart` with `ConnectivityMonitor` class wrapping `connectivity_plus`
    - Expose `isConnected` stream and `checkConnectivity()` method
    - _Requirements: 7.1, 7.2_

  - [x] 5.2 Write unit tests for ConnectivityMonitor
    - Test stream emissions for connectivity changes with mocked `connectivity_plus`
    - _Requirements: 7.1, 7.2_

- [x] 6. Implement UI components
  - [x] 6.1 Create `SignInView` widget
    - Create `lib/views/sign_in_view.dart` with WebView loading `https://app.kiro.dev/signin`
    - Show loading indicator while page loads
    - Show error message with retry button on load failure
    - Monitor URL navigation via `NavigationDelegate` to detect sign-in completion
    - Call `AuthManager.handleSignInComplete()` when sign-in is detected
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 2.1, 6.1_

  - [x] 6.2 Create `ContentView` widget
    - Create `lib/views/content_view.dart` with WebView displaying authenticated Kiro UI
    - Inject `AuthCredentials` (cookies/headers) into WebView requests
    - Show loading indicator while content loads
    - Show error message with retry button on load failure
    - Provide sign-out action (button/menu) that calls `AuthManager.signOut()`
    - Monitor for HTTP 401 responses and call `AuthManager.handleAuthError()`
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 5.1, 6.2_

  - [x] 6.3 Create `ErrorView` widget
    - Create `lib/views/error_view.dart` displaying error messages with retry button
    - Handle credential store unavailable messaging
    - _Requirements: 6.1, 6.3_

  - [x] 6.4 Create `AppShell` root widget
    - Create `lib/views/app_shell.dart` that listens to `AuthManager.stateStream`
    - Render `SignInView`, `ContentView`, `ErrorView`, or loading indicator based on `AuthState`
    - Integrate `ConnectivityMonitor` to show offline overlay with retry
    - _Requirements: 1.1, 3.1, 5.4, 7.1, 7.2, 8.5_

  - [x] 6.5 Write widget tests for UI components
    - Test `AppShell` renders correct view for each `AuthState`
    - Test `SignInView` shows loading indicator and handles errors
    - Test `ContentView` provides sign-out action
    - Test `ErrorView` displays messages and retry button
    - _Requirements: 1.3, 1.4, 4.3, 4.4, 5.1, 6.3_

- [x] 7. Wire everything together in main.dart
  - [x] 7.1 Set up app entry point and dependency injection
    - Update `lib/main.dart` to create `CredentialStore` (platform-appropriate), `AuthManager`, and `ConnectivityMonitor`
    - Provide dependencies via `Provider` to the widget tree
    - Set `AppShell` as the root widget
    - Call `AuthManager.initialize()` on app start
    - _Requirements: 1.1, 3.1, 8.1_

  - [x] 7.2 Handle platform-specific WebView and browser behavior
    - Configure WebView platform-specific settings (iOS, Android, Web)
    - Handle Web platform browser navigation (back button, tab management)
    - _Requirements: 8.1, 8.5, 8.6_

- [x] 8. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests use the `glados` Dart PBT library with 100+ iterations per property
- Unit/widget tests validate specific examples and edge cases
