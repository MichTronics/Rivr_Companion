import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/app_settings.dart';
import '../protocol/rivr_protocol.dart';

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  static const _darkModeKey         = 'dark_mode';
  static const _advancedKey         = 'advanced_mode';
  static const _callsignKey         = 'callsign';
  static const _bleNameKey          = 'ble_device';
  static const _baudRateKey         = 'baud_rate';
  static const _connTypeKey         = 'conn_type';
  static const _nodeIdKey           = 'phone_node_id';
  static const _webUrlKey           = 'web_upload_url';
  static const _webTokenKey         = 'web_upload_token';
  static const _fahrenheitKey       = 'use_fahrenheit';
  static const _sensorPeriodKey     = 'sensor_period_idx';
  static const _retentionKey        = 'telemetry_retention_days';
  static const _keepScreenAwakeKey  = 'keep_screen_awake';

  @override
  Future<AppSettings> build() async {
    final prefs = await SharedPreferences.getInstance();

    // Generate a stable random node-ID for BLE frames on first launch.
    int phoneNodeId = prefs.getInt(_nodeIdKey) ?? 0;
    if (phoneNodeId == 0) {
      phoneNodeId = RivrFrameCodec.generateNodeId();
      await prefs.setInt(_nodeIdKey, phoneNodeId);
    }

    final keepScreenAwake = prefs.getBool(_keepScreenAwakeKey) ?? false;
    WakelockPlus.toggle(enable: keepScreenAwake);

    return AppSettings(
      darkMode: prefs.getBool(_darkModeKey) ?? false,
      advancedMode: prefs.getBool(_advancedKey) ?? false,
      myCallsign: prefs.getString(_callsignKey) ?? '',
      lastBleDeviceName: prefs.getString(_bleNameKey) ?? '',
      lastUsbBaudRate: prefs.getInt(_baudRateKey) ?? 115200,
      lastConnectionType: ConnectionType.values[prefs.getInt(_connTypeKey) ?? 0],
      phoneNodeId: phoneNodeId,
      webUploadUrl: prefs.getString(_webUrlKey) ?? kDefaultWebUploadUrl,
      webUploadToken: prefs.getString(_webTokenKey) ?? kDefaultWebUploadToken,
      useFahrenheit: prefs.getBool(_fahrenheitKey) ?? false,
      defaultSensorPeriodIndex: prefs.getInt(_sensorPeriodKey) ?? 2,
      telemetryRetentionDays: prefs.getInt(_retentionKey) ?? 7,
      keepScreenAwake: keepScreenAwake,
    );
  }

  Future<void> setDarkMode(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, v);
    state = AsyncData((state.value ?? const AppSettings()).copyWith(darkMode: v));
  }

  Future<void> setAdvancedMode(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_advancedKey, v);
    state = AsyncData((state.value ?? const AppSettings()).copyWith(advancedMode: v));
  }

  Future<void> setCallsign(String v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_callsignKey, v);
    state = AsyncData((state.value ?? const AppSettings()).copyWith(myCallsign: v));
  }

  Future<void> setLastBle(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_bleNameKey, name);
    state = AsyncData((state.value ?? const AppSettings()).copyWith(lastBleDeviceName: name));
  }

  Future<void> setBaudRate(int rate) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_baudRateKey, rate);
    state = AsyncData((state.value ?? const AppSettings()).copyWith(lastUsbBaudRate: rate));
  }

  Future<void> setConnectionType(ConnectionType type) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_connTypeKey, type.index);
    state = AsyncData(
      (state.value ?? const AppSettings()).copyWith(lastConnectionType: type),
    );
  }

  Future<void> setWebUploadUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_webUrlKey, url);
    state = AsyncData((state.value ?? const AppSettings()).copyWith(webUploadUrl: url));
  }

  Future<void> setWebUploadToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_webTokenKey, token);
    state = AsyncData((state.value ?? const AppSettings()).copyWith(webUploadToken: token));
  }

  Future<void> setUseFahrenheit(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_fahrenheitKey, v);
    state = AsyncData((state.value ?? const AppSettings()).copyWith(useFahrenheit: v));
  }

  Future<void> setDefaultSensorPeriodIndex(int v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sensorPeriodKey, v);
    state = AsyncData((state.value ?? const AppSettings()).copyWith(defaultSensorPeriodIndex: v));
  }

  Future<void> setTelemetryRetentionDays(int v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_retentionKey, v);
    state = AsyncData((state.value ?? const AppSettings()).copyWith(telemetryRetentionDays: v));
  }

  Future<void> setKeepScreenAwake(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keepScreenAwakeKey, v);
    WakelockPlus.toggle(enable: v);
    state = AsyncData((state.value ?? const AppSettings()).copyWith(keepScreenAwake: v));
  }
}

/// Synchronous convenience accessor — returns default settings until async load
/// completes.  Screens should use this so they don't need to handle AsyncValue.
final settingsProvider = Provider<AppSettings>((ref) {
  return ref.watch(settingsNotifierProvider).maybeWhen(
        data: (s) => s,
        orElse: () => const AppSettings(),
      );
});

final settingsNotifierProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
