import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  SettingsService(this._prefs)
      : _enterToSend = _prefs.getBool(_kEnterToSend) ?? kIsWeb;

  static const _kEnterToSend = 'enter_to_send';
  final SharedPreferences _prefs;

  bool get enterToSend => _enterToSend;
  bool _enterToSend;

  set enterToSend(bool value) {
    if (_enterToSend == value) return;
    _enterToSend = value;
    _prefs.setBool(_kEnterToSend, value);
    notifyListeners();
  }
}
