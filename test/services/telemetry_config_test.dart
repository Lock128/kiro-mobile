import 'package:flutter_test/flutter_test.dart';
import 'package:kiro_flutter_auth/services/telemetry_config.dart';

void main() {
  group('TelemetryConfig', () {
    test('endpoint has correct default value', () {
      expect(TelemetryConfig.endpoint, 'http://localhost:4317');
    });

    test('protocol has correct default value', () {
      expect(TelemetryConfig.protocol, 'grpc');
    });

    test('serviceName has correct default value', () {
      expect(TelemetryConfig.serviceName, 'kiro-flutter-auth');
    });

    test('serviceVersion has correct default value', () {
      expect(TelemetryConfig.serviceVersion, '1.0.0');
    });
  });
}
