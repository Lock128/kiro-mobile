# Tech Stack

## Framework
- Flutter (Dart SDK ^3.11.1)
- Material 3 with `ColorScheme.fromSeed`

## Key Dependencies
| Package | Purpose |
|---|---|
| `provider` | State management via ChangeNotifier |
| `webview_flutter` | WebView for mobile OAuth flow |
| `flutter_secure_storage` | Encrypted credential storage (mobile) |
| `connectivity_plus` | Network state monitoring |
| `http` | HTTP client for API calls |
| `uuid` | Unique ID generation |
| `web` | Dart web interop |
| `flutterrific_opentelemetry` | OpenTelemetry observability (traces, metrics, logs) |
| `dartastic_opentelemetry` | OpenTelemetry SDK (transitive) |

## Dev Dependencies
| Package | Purpose |
|---|---|
| `flutter_lints` | Lint rules (flutter.yaml preset) |
| `glados` | Property-based testing |
| `flutter_launcher_icons` | App icon generation |
| `webview_flutter_platform_interface` | WebView mocking in tests |
| `flutter_secure_storage_platform_interface` | Secure storage mocking in tests |

## Linting
Uses `package:flutter_lints/flutter.yaml` via `analysis_options.yaml`. No custom rules enabled beyond defaults.

## Common Commands
```bash
# Install dependencies
flutter pub get

# Run on device/emulator
flutter run

# Run on web
flutter run -d chrome

# Run all tests
flutter test

# Static analysis
flutter analyze

# Generate app icons
flutter pub run flutter_launcher_icons
```

## Testing Approach
- Unit and widget tests in `test/` mirroring `lib/` structure
- Property-based tests using `glados` with custom `Generator` extensions on `Any`
- Mock implementations of abstract service interfaces (e.g. `MockCredentialStore implements CredentialStore`)
- Tests are organized per-concern (e.g. `auth_manager_init_valid_test.dart`, `auth_manager_sign_out_test.dart`)

## OpenTelemetry Configuration
The app uses OpenTelemetry for observability via `flutterrific_opentelemetry`. The OTLP exporter is configured at build time using `--dart-define` flags:

| Flag | Default | Description |
|---|---|---|
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:4317` | OTLP collector endpoint |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `grpc` | OTLP transport protocol |
| `OTEL_SERVICE_NAME` | `kiro-flutter-auth` | Service name reported to OTel |
| `OTEL_SERVICE_VERSION` | `1.0.0` | Service version reported to OTel |
| `OTEL_ENVIRONMENT` | `development` | Deployment environment attribute |

Example:
```bash
flutter run --dart-define=OTEL_EXPORTER_OTLP_ENDPOINT=https://collector.example.com:4317 --dart-define=OTEL_ENVIRONMENT=production
```
