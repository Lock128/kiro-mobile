import 'package:flutterrific_opentelemetry/flutterrific_opentelemetry.dart';

/// Platform-agnostic interface for OpenTelemetry observability.
///
/// Implementations wrap a specific OTel SDK. The abstract contract allows
/// tests to substitute a lightweight mock without pulling in the real SDK.
abstract class TelemetryService {
  /// Initializes the telemetry backend.
  Future<void> initialize({
    required String serviceName,
    required String serviceVersion,
    String? tracerName,
    Map<String, String>? resourceAttributes,
  });

  /// Reports an error to the telemetry backend.
  void reportError(String source, dynamic error, StackTrace? stackTrace);

  /// Returns the underlying OTel tracer for creating custom spans.
  ///
  /// May be `null` before [initialize] is called.
  dynamic get tracer;

  /// Shuts down the telemetry backend and flushes pending data.
  void shutdown();
}

/// Concrete [TelemetryService] backed by [FlutterOTel].
class FlutterOTelTelemetryService implements TelemetryService {
  @override
  Future<void> initialize({
    required String serviceName,
    required String serviceVersion,
    String? tracerName,
    Map<String, String>? resourceAttributes,
  }) async {
    final attrs = resourceAttributes != null
        ? <String, Object>{...resourceAttributes}.toAttributes()
        : null;
    await FlutterOTel.initialize(
      serviceName: serviceName,
      serviceVersion: serviceVersion,
      tracerName: tracerName,
      resourceAttributes: attrs,
    );
  }

  @override
  void reportError(String source, dynamic error, StackTrace? stackTrace) {
    FlutterOTel.reportError(source, error, stackTrace);
  }

  @override
  dynamic get tracer {
    try {
      return FlutterOTel.tracer;
    } catch (_) {
      return null;
    }
  }

  @override
  void shutdown() {
    FlutterOTel.forceFlush();
  }
}
