import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_metrics.dart';
import 'debug_log.dart';

/// HTTP client wrapper that captures per-request timing metrics
/// equivalent to what a browser HAR file records.
///
/// Wraps any [http.Client] and records [ApiCallMetric] for every request.
/// Metrics are logged via [DebugLog] and stored in-memory for export.
class InstrumentedHttpClient extends http.BaseClient {
  InstrumentedHttpClient({http.Client? inner})
      : _inner = inner ?? http.Client();

  final http.Client _inner;

  static const int _maxMetrics = 500;

  final List<ApiCallMetric> _metrics = [];

  /// All captured metrics (oldest first).
  List<ApiCallMetric> get metrics => List.unmodifiable(_metrics);

  /// Clears all captured metrics.
  void clearMetrics() => _metrics.clear();

  /// Returns all metrics as a JSON-encoded string (for export/sharing).
  String dumpMetricsJson() =>
      const JsonEncoder.withIndent('  ')
          .convert(_metrics.map((m) => m.toJson()).toList());

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final startedAt = DateTime.now();
    final stopwatch = Stopwatch()..start();
    final requestBodySize = _requestBodySize(request);

    try {
      final response = await _inner.send(request);
      stopwatch.stop();

      // Read the response body so we can measure size, then re-wrap it
      // as a new StreamedResponse so the caller still gets the bytes.
      final bodyBytes = await response.stream.toBytes();
      final metric = ApiCallMetric(
        method: request.method,
        url: request.url.toString(),
        startedAt: startedAt,
        totalDuration: stopwatch.elapsedMicroseconds / 1000.0,
        statusCode: response.statusCode,
        requestBodySize: requestBodySize,
        responseBodySize: bodyBytes.length,
      );

      _record(metric);

      // Re-emit the body bytes as a new stream.
      return http.StreamedResponse(
        Stream.value(bodyBytes),
        response.statusCode,
        contentLength: bodyBytes.length,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (e) {
      stopwatch.stop();
      final metric = ApiCallMetric(
        method: request.method,
        url: request.url.toString(),
        startedAt: startedAt,
        totalDuration: stopwatch.elapsedMicroseconds / 1000.0,
        statusCode: -1,
        requestBodySize: requestBodySize,
        responseBodySize: 0,
        error: e.toString(),
      );
      _record(metric);
      rethrow;
    }
  }

  void _record(ApiCallMetric metric) {
    _metrics.add(metric);
    if (_metrics.length > _maxMetrics) {
      _metrics.removeRange(0, _metrics.length - _maxMetrics);
    }
    DebugLog.log('[API] $metric');
  }

  int _requestBodySize(http.BaseRequest request) {
    if (request is http.Request) return request.bodyBytes.length;
    if (request.contentLength != null) return request.contentLength!;
    return 0;
  }

  @override
  void close() => _inner.close();
}
