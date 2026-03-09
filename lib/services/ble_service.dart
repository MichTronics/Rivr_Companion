import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../protocol/rivr_protocol.dart';
import 'connection_manager.dart';

/// Nordic UART Service (NUS) — the standard BLE serial-over-GATT profile.
/// Most BLE-capable Rivr builds expose NUS for the serial CLI.
///
/// UUIDs are standard NUS defaults.  Override in config if your firmware
/// uses different UUIDs.
class NusUuids {
  static const service       = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const txCharacteristic = '6e400002-b5a3-f393-e0a9-e50e24dcca9e'; // app → device
  static const rxCharacteristic = '6e400003-b5a3-f393-e0a9-e50e24dcca9e'; // device → app
}

class BleService extends RivrTransport {
  final _stateCtrl = StreamController<RivrConnState>.broadcast();
  final _eventCtrl = StreamController<RivrEvent>.broadcast();

  BluetoothDevice? _device;
  BluetoothCharacteristic? _txChar;   // write to device
  BluetoothCharacteristic? _rxChar;   // notify from device
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  final _lineBuffer = StringBuffer();

  @override
  Stream<RivrConnState> get stateStream => _stateCtrl.stream;

  @override
  Stream<RivrEvent> get eventStream => _eventCtrl.stream;

  // ── Scan ──────────────────────────────────────────────────────────────────
  @override
  Future<void> startScan() async {
    _emit(ConnectionStatus.scanning, 'Scanning…');
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
      withServices: [Guid(NusUuids.service)],
    );
    FlutterBluePlus.scanResults.listen((results) {
      // Surfaces scan results to the UI via eventStream as RawLineEvents so
      // the scan sheet can render them.  The actual connect() call is
      // initiated by the user.
      for (final r in results) {
        _eventCtrl.add(RawLineEvent('BLE_SCAN:${r.device.remoteId}:${r.device.platformName}'));
      }
    });
    FlutterBluePlus.isScanning.listen((scanning) {
      if (!scanning && _device == null) {
        _emit(ConnectionStatus.disconnected, '');
      }
    });
  }

  // ── Connect ───────────────────────────────────────────────────────────────
  @override
  Future<void> connect(String deviceId) async {
    _emit(ConnectionStatus.connecting, deviceId);
    try {
      final device = BluetoothDevice(remoteId: DeviceIdentifier(deviceId));
      _device = device;

      _connSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _emit(ConnectionStatus.disconnected, deviceId);
        }
      });

      await device.connect(timeout: const Duration(seconds: 15));
      await _discoverServices(device);
      _emit(ConnectionStatus.connected, device.platformName.isNotEmpty
          ? device.platformName : deviceId);
    } catch (e) {
      _emit(ConnectionStatus.error, deviceId, error: e.toString());
    }
  }

  Future<void> _discoverServices(BluetoothDevice device) async {
    final services = await device.discoverServices();
    for (final svc in services) {
      if (svc.uuid == Guid(NusUuids.service)) {
        for (final char in svc.characteristics) {
          if (char.uuid == Guid(NusUuids.txCharacteristic)) _txChar = char;
          if (char.uuid == Guid(NusUuids.rxCharacteristic)) {
            _rxChar = char;
            await char.setNotifyValue(true);
            _notifySub = char.onValueReceived.listen(_onBytes);
          }
        }
      }
    }
    if (_txChar == null || _rxChar == null) {
      throw Exception('NUS characteristics not found on device');
    }
  }

  void _onBytes(List<int> bytes) {
    final chunk = utf8.decode(bytes, allowMalformed: true);
    for (final ch in chunk.codeUnits) {
      if (ch == 10 /* \n */) {
        final line = _lineBuffer.toString();
        _lineBuffer.clear();
        final event = RivrProtocol.parseLine(line);
        if (event != null) _eventCtrl.add(event);
      } else {
        _lineBuffer.writeCharCode(ch);
      }
    }
  }

  // ── Send ──────────────────────────────────────────────────────────────────
  @override
  Future<void> send(String command) async {
    if (_txChar == null) return;
    final bytes = utf8.encode(command);
    // BLE MTU is usually 20 bytes in NUS; chunk if needed.
    const chunkSize = 20;
    for (var i = 0; i < bytes.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, bytes.length);
      await _txChar!.write(bytes.sublist(i, end), withoutResponse: _txChar!.properties.writeWithoutResponse);
    }
  }

  // ── Disconnect ─────────────────────────────────────────────────────────────
  @override
  Future<void> disconnect() async {
    await _notifySub?.cancel();
    await _connSub?.cancel();
    await _device?.disconnect();
    _device = null;
    _txChar = null;
    _rxChar = null;
    _emit(ConnectionStatus.disconnected, '');
  }

  @override
  void dispose() {
    disconnect();
    _stateCtrl.close();
    _eventCtrl.close();
  }

  void _emit(ConnectionStatus status, String name, {String? error}) {
    _stateCtrl.add(RivrConnState(
      status: status,
      deviceName: name,
      errorMessage: error,
    ));
  }
}
