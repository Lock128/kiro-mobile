import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Abstract interface for monitoring network connectivity.
///
/// Provides a reactive stream of connectivity state and an on-demand check.
abstract class ConnectivityMonitor {
  /// A broadcast stream that emits `true` when the device is connected
  /// to a network and `false` when it is not.
  Stream<bool> get isConnected;

  /// Checks the current connectivity status on demand.
  ///
  /// Returns `true` if the device has network connectivity, `false` otherwise.
  Future<bool> checkConnectivity();

  /// Releases resources held by this monitor.
  void dispose();
}

/// Concrete implementation of [ConnectivityMonitor] using the
/// `connectivity_plus` package.
class ConnectivityMonitorImpl implements ConnectivityMonitor {
  ConnectivityMonitorImpl({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity() {
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _controller.add(_isConnectedFromResults(results));
    });
  }

  final Connectivity _connectivity;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  late final StreamSubscription<List<ConnectivityResult>> _subscription;

  @override
  Stream<bool> get isConnected => _controller.stream;

  @override
  Future<bool> checkConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    return _isConnectedFromResults(results);
  }

  @override
  void dispose() {
    _subscription.cancel();
    _controller.close();
  }

  /// Maps a list of [ConnectivityResult] values to a single boolean.
  ///
  /// Returns `true` if any result indicates a real network connection
  /// (wifi, mobile, ethernet, vpn), `false` otherwise.
  static bool _isConnectedFromResults(List<ConnectivityResult> results) {
    return results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet ||
        r == ConnectivityResult.vpn);
  }
}
