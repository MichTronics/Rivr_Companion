import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  static const _darkModeKey = 'dark_mode';
  static const _advancedKey = 'advanced_mode';
  static const _callsignKey = 'callsign';
  static const _bleNameKey = 'ble_device';
  static const _baudRateKey = 'baud_rate';
  static const _connTypeKey = 'conn_type';

  @override
  Future<AppSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      darkMode: prefs.getBool(_darkModeKey) ?? false,
      advancedMode: prefs.getBool(_advancedKey) ?? false,
      myCallsign: prefs.getString(_callsignKey) ?? '',
      lastBleDeviceName: prefs.getString(_bleNameKey) ?? '',
      lastUsbBaudRate: prefs.getInt(_baudRateKey) ?? 115200,
      lastConnectionType: ConnectionType.values[prefs.getInt(_connTypeKey) ?? 0],
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
