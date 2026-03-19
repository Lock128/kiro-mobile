# Kiro Mobile (kiro_flutter_auth)

> **ALPHA SOFTWARE -- NOT SECURITY VALIDATED**
>
> This project is in an **alpha** stage of development. It has **not** undergone a formal security audit or validation. Use it at your own risk and do not rely on it for production workloads or sensitive data without performing your own thorough security review. APIs, behavior, and storage mechanisms may change without notice.

## About

Kiro Mobile is a cross-platform Flutter application that authenticates users through the [Kiro web sign-in flow](https://app.kiro.dev/signin). After sign-in, the app captures authentication credentials from a WebView, persists them securely using platform-native storage, and renders authenticated Kiro UI content within the app.

## Features

- **Web-based sign-in** -- Authenticates users via the Kiro sign-in page displayed in a WebView.
- **Secure credential storage** -- Persists credentials per platform (iOS Keychain, Android Keystore, encrypted localStorage on Web).
- **Authenticated content rendering** -- Displays Kiro UI content inside the app after successful authentication.
- **Network connectivity monitoring** -- Detects and responds to changes in network state.
- **State management with Provider** -- Uses the Provider package for reactive, clean state management.

## Supported Platforms

| Platform | Status |
|----------|--------|
| iOS      | Supported |
| Android  | Supported |
| Web      | Supported |

## Architecture

The app follows a service-oriented architecture with clear separation of concerns:

- **AppShell** -- Root widget that renders the appropriate view based on authentication state.
- **AuthManager** -- Manages the full authentication lifecycle (sign-in, session, sign-out).
- **CredentialStore** -- Abstracts platform-specific secure storage behind a unified interface.
- **SignInView** -- Displays the Kiro sign-in page in a WebView and captures credentials.
- **ContentView** -- Renders authenticated Kiro UI content.
- **ConnectivityMonitor** -- Monitors network connectivity and surfaces state changes.

## Project Structure

```
lib/
  main.dart          # App entry point
  models/            # Data models
  services/          # Auth, credential storage, connectivity services
  views/             # UI screens (SignInView, ContentView, AppShell)
test/                # Unit and widget tests
assets/              # Static assets
android/             # Android platform project
ios/                 # iOS platform project
web/                 # Web platform project
```

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart SDK ^3.11.1)
- For iOS: Xcode and CocoaPods
- For Android: Android Studio and the Android SDK
- For Web: A modern browser (Chrome recommended)

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

3. **Run the app**

   ```bash
   # Web
   flutter run -d chrome

   # iOS (macOS only)
   flutter run -d ios

   # Android
   flutter run -d android
   ```

## Running Tests

```bash
flutter test
```

## Key Dependencies

| Package | Purpose |
|---------|---------|
| [webview_flutter](https://pub.dev/packages/webview_flutter) | WebView for sign-in and content rendering |
| [webview_flutter_web](https://pub.dev/packages/webview_flutter_web) | WebView support on the web platform |
| [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) | Secure credential storage |
| [connectivity_plus](https://pub.dev/packages/connectivity_plus) | Network connectivity monitoring |
| [provider](https://pub.dev/packages/provider) | State management |
| [http](https://pub.dev/packages/http) | HTTP requests |

## License

This project is licensed under the Apache License 2.0. See the [LICENSE](LICENSE) file for details.
