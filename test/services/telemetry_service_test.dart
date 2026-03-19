import 'package:flutter_test/flutter_test.dart';
import 'package:kiro_flutter_auth/models/auth_credentials.dart';
import 'package:kiro_flutter_auth/services/kiro_api.dart';
import 'package:kiro_flutter_auth/services/telemetry_service.dart';

/// A mock [TelemetryService] for testing. Follows the MockCredentialStore
/// pattern: implements the abstract interface with no-op behaviour.
class MockTelemetryService implements TelemetryService {
  bool initializeCalled = false;
  bool shutdownCalled = false;
  List<String> reportedErrors = [];

  @override
  Future<void> initialize({
    required String serviceName,
    required String serviceVersion,
    String? tracerName,
    Map<String, String>? resourceAttributes,
  }) async {
    initializeCalled = true;
  }

  @override
  void reportError(String source, dynamic error, StackTrace? stackTrace) {
    reportedErrors.add('$source: $error');
  }

  @override
  dynamic get tracer => null;

  @override
  void shutdown() {
    shutdownCalled = true;
  }
}

void main() {
  group('MockTelemetryService', () {
    test('can be created without throwing', () {
      final mock = MockTelemetryService();
      expect(mock, isNotNull);
    });

    test('initialize sets flag', () async {
      final mock = MockTelemetryService();
      await mock.initialize(
        serviceName: 'test',
        serviceVersion: '0.0.1',
      );
      expect(mock.initializeCalled, isTrue);
    });

    test('reportError records the error', () {
      final mock = MockTelemetryService();
      mock.reportError('test_source', 'some error', null);
      expect(mock.reportedErrors, ['test_source: some error']);
    });

    test('tracer returns null by default', () {
      final mock = MockTelemetryService();
      expect(mock.tracer, isNull);
    });

    test('shutdown sets flag', () {
      final mock = MockTelemetryService();
      mock.shutdown();
      expect(mock.shutdownCalled, isTrue);
    });
  });

  group('KiroApi with TelemetryService', () {
    test('can be constructed with a MockTelemetryService', () {
      final mock = MockTelemetryService();
      final credentials = AuthCredentials(token: 'test-token');
      final api = KiroApi(
        credentials: credentials,
        telemetryService: mock,
      );
      expect(api, isNotNull);
      api.dispose();
    });

    test('can be constructed without a TelemetryService', () {
      final credentials = AuthCredentials(token: 'test-token');
      final api = KiroApi(credentials: credentials);
      expect(api, isNotNull);
      api.dispose();
    });
  });
}
