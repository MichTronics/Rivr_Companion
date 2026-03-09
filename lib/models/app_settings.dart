import 'package:equatable/equatable.dart';

enum ConnectionType { none, ble, usb }

/// Persistent user preferences.
class AppSettings extends Equatable {
  final bool darkMode;
  final bool advancedMode;      // reveals advanced controls when true
  final ConnectionType lastConnectionType;
  final String lastBleDeviceName;
  final int lastUsbBaudRate;
  final String myCallsign;      // optional display name for this device

  const AppSettings({
    this.darkMode = false,
    this.advancedMode = false,
    this.lastConnectionType = ConnectionType.none,
    this.lastBleDeviceName = '',
    this.lastUsbBaudRate = 115200,
    this.myCallsign = '',
  });

  AppSettings copyWith({
    bool? darkMode,
    bool? advancedMode,
    ConnectionType? lastConnectionType,
    String? lastBleDeviceName,
    int? lastUsbBaudRate,
    String? myCallsign,
  }) {
    return AppSettings(
      darkMode: darkMode ?? this.darkMode,
      advancedMode: advancedMode ?? this.advancedMode,
      lastConnectionType: lastConnectionType ?? this.lastConnectionType,
      lastBleDeviceName: lastBleDeviceName ?? this.lastBleDeviceName,
      lastUsbBaudRate: lastUsbBaudRate ?? this.lastUsbBaudRate,
      myCallsign: myCallsign ?? this.myCallsign,
    );
  }

  @override
  List<Object?> get props => [
    darkMode, advancedMode, lastConnectionType,
    lastBleDeviceName, lastUsbBaudRate, myCallsign,
  ];
}
