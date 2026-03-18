import 'package:flutter/foundation.dart' show debugPrint;

/// Simple in-memory debug log for on-device diagnostics.
class DebugLog {
  DebugLog._();

  static final List<String> _entries = [];

  /// All recorded log entries.
  static List<String> get entries => List.unmodifiable(_entries);

  /// Adds a timestamped entry and also calls [debugPrint].
  static void log(String message) {
    final entry = '${DateTime.now().toIso8601String()} $message';
    _entries.add(entry);
    debugPrint('[DebugLog] $message');
  }

  /// Clears all entries.
  static void clear() => _entries.clear();

  /// Returns all entries as a single string.
  static String dump() => _entries.join('\n');
}
