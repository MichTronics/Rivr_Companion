import 'package:equatable/equatable.dart';

enum ConnectionType { none, ble, usb }

/// Default web upload endpoint — injected at build time via --dart-define.
/// Never hard-code the token in source; pass it as:
/// ```
///   flutter build <target> --dart-define=INGEST_TOKEN=<token>
/// ```
const kDefaultWebUploadUrl = String.fromEnvironment(
  'INGEST_URL',
  defaultValue: 'https://rivr.co.nl',
);
const kDefaultWebUploadToken = String.fromEnvironment(
  'INGEST_TOKEN',
  defaultValue: '',
);

/// Persistent user preferences.
class AppSettings extends Equatable {
  final bool darkMode;
  final bool advancedMode;      // reveals advanced controls when true
  final ConnectionType lastConnectionType;
  final String lastBleDeviceName;
  final int lastUsbBaudRate;
  final String myCallsign;      // optional display name for this device
  final int phoneNodeId;        // persistent random node-ID for BLE frames

  /// Website ingest URL, e.g. https://rivr.network  — empty = disabled.
  final String webUploadUrl;
  /// Shared secret sent as x-ingest-token header.
  final String webUploadToken;

  /// Show temperatures in Fahrenheit when true (default: false = Celsius).
  final bool useFahrenheit;

  /// Last selected sensor graph period index (0=1h, 1=6h, 2=24h, 3=7d).
  final int defaultSensorPeriodIndex;

  /// How many days of telemetry to retain in the local database.
  final int telemetryRetentionDays;

  /// Keep the screen awake while the app is in the foreground.
  final bool keepScreenAwake;

  const AppSettings({
    this.darkMode = false,
    this.advancedMode = false,
    this.lastConnectionType = ConnectionType.none,
    this.lastBleDeviceName = '',
    this.lastUsbBaudRate = 115200,
    this.myCallsign = '',
    this.phoneNodeId = 0,
    this.webUploadUrl = kDefaultWebUploadUrl,
    this.webUploadToken = kDefaultWebUploadToken,
    this.useFahrenheit = false,
    this.defaultSensorPeriodIndex = 2,
    this.telemetryRetentionDays = 7,
    this.keepScreenAwake = false,
  });

  AppSettings copyWith({
    bool? darkMode,
    bool? advancedMode,
    ConnectionType? lastConnectionType,
    String? lastBleDeviceName,
    int? lastUsbBaudRate,
    String? myCallsign,
    int? phoneNodeId,
    String? webUploadUrl,
    String? webUploadToken,
    bool? useFahrenheit,
    int? defaultSensorPeriodIndex,
    int? telemetryRetentionDays,
    bool? keepScreenAwake,
  }) {
    return AppSettings(
      darkMode: darkMode ?? this.darkMode,
      advancedMode: advancedMode ?? this.advancedMode,
      lastConnectionType: lastConnectionType ?? this.lastConnectionType,
      lastBleDeviceName: lastBleDeviceName ?? this.lastBleDeviceName,
      lastUsbBaudRate: lastUsbBaudRate ?? this.lastUsbBaudRate,
      myCallsign: myCallsign ?? this.myCallsign,
      phoneNodeId: phoneNodeId ?? this.phoneNodeId,
      webUploadUrl: webUploadUrl ?? this.webUploadUrl,
      webUploadToken: webUploadToken ?? this.webUploadToken,
      useFahrenheit: useFahrenheit ?? this.useFahrenheit,
      defaultSensorPeriodIndex: defaultSensorPeriodIndex ?? this.defaultSensorPeriodIndex,
      telemetryRetentionDays: telemetryRetentionDays ?? this.telemetryRetentionDays,
      keepScreenAwake: keepScreenAwake ?? this.keepScreenAwake,
    );
  }

  /// True when web forwarding is fully configured.
  bool get webUploadEnabled =>
      webUploadUrl.isNotEmpty && webUploadToken.isNotEmpty;

  @override
  List<Object?> get props => [
    darkMode, advancedMode, lastConnectionType,
    lastBleDeviceName, lastUsbBaudRate, myCallsign, phoneNodeId,
    webUploadUrl, webUploadToken,
    useFahrenheit, defaultSensorPeriodIndex, telemetryRetentionDays, keepScreenAwake,
  ];
}
