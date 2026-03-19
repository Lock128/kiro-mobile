/// A single captured API call metric — mirrors the timing data from a HAR entry.
class ApiCallMetric {
  ApiCallMetric({
    required this.method,
    required this.url,
    required this.startedAt,
    required this.totalDuration,
    required this.statusCode,
    required this.requestBodySize,
    required this.responseBodySize,
    this.error,
  });

  final String method;
  final String url;
  final DateTime startedAt;

  /// Total round-trip time in milliseconds (equivalent to HAR "time").
  final double totalDuration;

  final int statusCode;
  final int requestBodySize;
  final int responseBodySize;

  /// Non-null if the request threw an exception.
  final String? error;

  /// Short operation name extracted from the URL path (e.g. "createSession").
  String get operation {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final segments = uri.pathSegments;
    return segments.isNotEmpty ? segments.last : uri.path;
  }

  Map<String, dynamic> toJson() => {
        'method': method,
        'operation': operation,
        'url': url,
        'startedAt': startedAt.toIso8601String(),
        'totalDurationMs': totalDuration.toStringAsFixed(2),
        'statusCode': statusCode,
        'requestBodySize': requestBodySize,
        'responseBodySize': responseBodySize,
        if (error != null) 'error': error,
      };

  @override
  String toString() =>
      '$method $operation ${totalDuration.toStringAsFixed(0)}ms '
      'status=$statusCode req=${requestBodySize}B res=${responseBodySize}B';
}
