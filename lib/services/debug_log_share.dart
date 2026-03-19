import 'dart:io' show File;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:share_plus/share_plus.dart';

/// Mobile implementation — writes to a temp file and opens the share sheet.
Future<bool> shareLogImpl(String logContent) async {
  try {
    final dir = await path_provider.getTemporaryDirectory();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File('${dir.path}/kiro_debug_log_$timestamp.txt');
    await file.writeAsString(logContent);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Kiro Debug Log $timestamp',
    );
    return true;
  } catch (e) {
    debugPrint('[DebugLog] shareLog failed: $e');
    return false;
  }
}
