import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_config.dart';

class ConfigService {
  static const String _configKey = 'app_config';
  late SharedPreferences _prefs;
  late AppConfig _config;

  AppConfig get config => _config;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _load();
  }

  void _load() {
    final jsonStr = _prefs.getString(_configKey);
    if (jsonStr != null) {
      try {
        _config = AppConfig.fromJson(
            json.decode(jsonStr) as Map<String, dynamic>);
      } catch (_) {
        _config = AppConfig();
      }
    } else {
      _config = AppConfig();
    }
  }

  Future<void> save() async {
    await _prefs.setString(_configKey, json.encode(_config.toJson()));
  }

  Future<void> update(AppConfig Function(AppConfig) updater) async {
    _config = updater(_config);
    await save();
  }

  T get<T>(T Function(AppConfig) selector) => selector(_config);
}
