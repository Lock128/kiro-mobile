/// Compile-time configuration for OpenTelemetry.
///
/// Values are read from `--dart-define` flags at build time. For example:
/// ```
/// flutter run --dart-define=OTEL_EXPORTER_OTLP_ENDPOINT=https://collector.example.com:4317
/// ```
class TelemetryConfig {
  TelemetryConfig._();

  static const _defaultEndpoint = 'http://localhost:4317';

  static const endpoint = String.fromEnvironment(
    'OTEL_EXPORTER_OTLP_ENDPOINT',
    defaultValue: _defaultEndpoint,
  );

  /// Whether a real OTLP endpoint was explicitly provided at build time.
  /// When `false`, OTel is skipped entirely to avoid noisy errors.
  static bool get isConfigured => endpoint != _defaultEndpoint;

  static const protocol = String.fromEnvironment(
    'OTEL_EXPORTER_OTLP_PROTOCOL',
    defaultValue: 'grpc',
  );

  static const serviceName = String.fromEnvironment(
    'OTEL_SERVICE_NAME',
    defaultValue: 'kiro-flutter-auth',
  );

  static const serviceVersion = String.fromEnvironment(
    'OTEL_SERVICE_VERSION',
    defaultValue: '1.0.0',
  );
}
