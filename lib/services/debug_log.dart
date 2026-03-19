import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import 'debug_log_share.dart'
    if (dart.library.js_interop) 'debug_log_share_web.dart' as share_impl;

/// Simple in-memory debug log for on-device diagnostics.
///
/// On TestFlight / release builds, use [shareLog] to export the log
/// via the system share sheet (email, AirDrop, Files, etc.).
class DebugLog {
  DebugLog._();

  static const int _maxEntries = 2000;

  static final List<String> _entries = [];

  /// All recorded log entries.
  static List<String> get entries => List.unmodifiable(_entries);

  /// Adds a timestamped entry and also calls [debugPrint].
  static void log(String message) {
    final entry = '${DateTime.now().toIso8601String()} $message';
    _entries.add(entry);
    // Prevent unbounded memory growth.
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    debugPrint('[DebugLog] $message');
  }

  /// Clears all entries.
  static void clear() => _entries.clear();

  /// Returns all entries as a single string.
  static String dump() => _entries.join('\n');

  /// Writes the log to a temporary file and opens the system share sheet.
  ///
  /// On iOS this lets TestFlight users email/AirDrop the log to you.
  /// On web this is a no-op.
  /// Returns `true` if the share sheet was shown successfully.
  static Future<bool> shareLog() => share_impl.shareLogImpl(dump());
}
