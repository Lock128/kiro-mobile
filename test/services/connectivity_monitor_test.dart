import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kiro_flutter_auth/services/connectivity_monitor.dart';

/// A fake [Connectivity] that gives tests full control over the values
/// returned by [checkConnectivity] and emitted by [onConnectivityChanged].
class FakeConnectivity implements Connectivity {
  FakeConnectivity({
    List<ConnectivityResult>? initialResult,
  }) : _checkResult = initialResult ?? [ConnectivityResult.wifi];

  List<ConnectivityResult> _checkResult;
  final StreamController<List<ConnectivityResult>> _controller =
      StreamController<List<ConnectivityResult>>.broadcast();

  /// Sets the value that the next [checkConnectivity] call will return.
  set checkResult(List<ConnectivityResult> value) => _checkResult = value;

  /// Pushes a connectivity change event into [onConnectivityChanged].
  void emitChange(List<ConnectivityResult> results) {
    _controller.add(results);
  }

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => _checkResult;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  void dispose() {
    _controller.close();
  }

  // -- Unused Connectivity members --
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('ConnectivityMonitorImpl', () {
    late FakeConnectivity fakeConnectivity;
    late ConnectivityMonitorImpl monitor;

    setUp(() {
      fakeConnectivity = FakeConnectivity();
      monitor = ConnectivityMonitorImpl(connectivity: fakeConnectivity);
    });

    tearDown(() {
      monitor.dispose();
      fakeConnectivity.dispose();
    });

    group('checkConnectivity()', () {
      test('returns true when wifi is available', () async {
        fakeConnectivity.checkResult = [ConnectivityResult.wifi];
        expect(await monitor.checkConnectivity(), isTrue);
      });

      test('returns true when mobile is available', () async {
        fakeConnectivity.checkResult = [ConnectivityResult.mobile];
        expect(await monitor.checkConnectivity(), isTrue);
      });

      test('returns true when ethernet is available', () async {
        fakeConnectivity.checkResult = [ConnectivityResult.ethernet];
        expect(await monitor.checkConnectivity(), isTrue);
      });

      test('returns true when vpn is available', () async {
        fakeConnectivity.checkResult = [ConnectivityResult.vpn];
        expect(await monitor.checkConnectivity(), isTrue);
      });

      test('returns false when no connectivity', () async {
        fakeConnectivity.checkResult = [ConnectivityResult.none];
        expect(await monitor.checkConnectivity(), isFalse);
      });
    });

    group('isConnected stream', () {
      test('emits true when connectivity changes to wifi', () async {
        final future = monitor.isConnected.first;
        fakeConnectivity.emitChange([ConnectivityResult.wifi]);
        expect(await future, isTrue);
      });

      test('emits false when connectivity changes to none', () async {
        final future = monitor.isConnected.first;
        fakeConnectivity.emitChange([ConnectivityResult.none]);
        expect(await future, isFalse);
      });

      test('multiple connectivity changes are reflected in the stream',
          () async {
        final emissions = <bool>[];
        final subscription = monitor.isConnected.listen(emissions.add);

        fakeConnectivity.emitChange([ConnectivityResult.wifi]);
        fakeConnectivity.emitChange([ConnectivityResult.none]);
        fakeConnectivity.emitChange([ConnectivityResult.mobile]);

        // Allow microtasks to process the stream events.
        await Future<void>.delayed(Duration.zero);

        expect(emissions, equals([true, false, true]));

        await subscription.cancel();
      });
    });
  });
}
