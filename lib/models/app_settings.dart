import 'package:equatable/equatable.dart';

enum ConnectionType { none, ble, usb }

/// Default web upload endpoint — injected at build time via --dart-define.
/// Never hard-code the token in source; pass it as:
///   flutter build <target> --dart-define=INGEST_TOKEN=<token>
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
  ];
}
