import 'dart:async';
import 'dart:typed_data';
import 'dart:io' show Platform;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../protocol/rivr_protocol.dart';
import 'connection_manager.dart';

/// Nordic UART Service (NUS) UUIDs.
/// Names from the NODE's perspective:
///   RX = node receives  → phone writes to 6e400002
///   TX = node transmits → phone subscribes to notifications on 6e400003
class NusUuids {
  static const service = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const rxChar  = '6e400002-b5a3-f393-e0a9-e50e24dcca9e'; // phone → node
  static const txChar  = '6e400003-b5a3-f393-e0a9-e50e24dcca9e'; // node  → phone
}

/// BLE transport using Nordic UART Service (NUS).
///
/// Carries binary Rivr packet frames — not ASCII text.
///
/// Fixed:
///   • MTU negotiated to 247 (min Rivr frame = 25 B, ATT default = 20 B).
///   • connectionState subscribed AFTER connect() to avoid race condition.
///   • No withServices scan filter — UUID is in scan response, not primary ADV.
///   • Binary _onBytes via RivrFrameCodec (not UTF-8 text parsing).
///   • send() builds PKT_CHAT binary frames (not ASCII 'chat text\n').
///   • Exponential reconnect backoff on unexpected disconnect.
class BleService extends RivrTransport {
  final int phoneNodeId;
  int _seq = 0;

  final _stateCtrl = StreamController<RivrConnState>.broadcast();
  final _eventCtrl = StreamController<RivrEvent>.broadcast();

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;   // 6e400002 — phone writes here
  BluetoothCharacteristic? _notifyChar;  // 6e400003 — node notifies here

  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _isScanSub;

  final _seenScanIds = <String>{};
  bool _disposed = false;
  bool _intentionalDisconnect = false;
  bool _wasConnected = false;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  static const _reconnectDelays = [1, 2, 5];

  BleService({required this.phoneNodeId});

  @override
  Stream<RivrConnState> get stateStream => _stateCtrl.stream;
  @override
  Stream<RivrEvent> get eventStream => _eventCtrl.stream;

  // ── Scan ──────────────────────────────────────────────────────────────────

  @override
  Future<void> startScan() async {
    await _ensurePermissions();
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    await _isScanSub?.cancel();
    _seenScanIds.clear();

    _emit(ConnectionStatus.scanning, 'Scanning…');

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        // device.platformName is a cached system name — empty on first discovery.
        // advertisementData.advName comes directly from the ADV packet and is
        // the reliable source for the live "RIVR-XXXX" name.
        final advName = r.advertisementData.advName;
        final name = advName.isNotEmpty ? advName : r.device.platformName;
        if (!name.startsWith('RIVR-')) continue; // only Rivr nodes
        final id = r.device.remoteId.str;
        if (_seenScanIds.add(id)) {
          _safeAddEvent(RawLineEvent('BLE_SCAN:$id:$name'));
        }
      }
    });

    _isScanSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (!scanning && _device == null) {
        _emit(ConnectionStatus.disconnected, '');
      }
    });

    // No withServices filter: UUID is in scan response, not primary ADV.
    // Android hardware scan filters only check primary ADV packets, so
    // filtering by UUID silently drops every Rivr node.
    // Low-latency scan mode ensures Android's duty-cycle window overlaps
    // with the 100-200 ms advertising interval.
    unawaited(
      FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        androidScanMode: AndroidScanMode.lowLatency,
      ),
    );
  }

  // ── Connect ───────────────────────────────────────────────────────────────

  @override
  Future<void> connect(String deviceId) async {
    _intentionalDisconnect = false;
    _wasConnected = false;
    _reconnectTimer?.cancel();
    _reconnectAttempt = 0;
    await _doConnect(deviceId);
  }

  Future<void> _doConnect(String deviceId) async {
    _emit(ConnectionStatus.connecting, deviceId);
    try {
      await _ensurePermissions();
      await FlutterBluePlus.stopScan();
      await _scanSub?.cancel();
      await _isScanSub?.cancel();
      _scanSub = null;
      _isScanSub = null;

      final device = BluetoothDevice(remoteId: DeviceIdentifier(deviceId));
      _device = device;

      // connect() first — subscribing to connectionState before this causes
      // the stream's initial disconnected event to fire as a false failure.
      await device.connect(
        timeout: const Duration(seconds: 20),
        autoConnect: false,
      );

      _connSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected &&
            !_intentionalDisconnect) {
          _handleUnexpectedDisconnect(deviceId);
        }
      });

      // Mandatory MTU negotiation — min Rivr frame is 25 bytes, the ATT
      // default payload of 20 bytes would truncate every incoming frame.
      await device.requestMtu(247);

      _wasConnected = true;
      _reconnectAttempt = 0;
      await _discoverServices(device);

      _emit(
        ConnectionStatus.connected,
        device.platformName.isNotEmpty ? device.platformName : deviceId,
      );
    } catch (e) {
      _device = null;
      _writeChar = null;
      _notifyChar = null;
      final s = e.toString();
      final msg = (s.contains('133') || s.toLowerCase().contains('timeout'))
          ? 'Timed out — press the button on the node to open BLE window'
          : s;
      _emit(ConnectionStatus.error, deviceId, error: msg);
    }
  }

  void _handleUnexpectedDisconnect(String deviceId) {
    _connSub?.cancel();
    _notifySub?.cancel();
    _connSub = null;
    _notifySub = null;
    _writeChar = null;
    _notifyChar = null;
    if (!_wasConnected || _reconnectAttempt >= _reconnectDelays.length) {
      _emit(ConnectionStatus.disconnected, deviceId);
      return;
    }
    final delaySec = _reconnectDelays[_reconnectAttempt++];
    _emit(ConnectionStatus.connecting, 'Reconnecting in ${delaySec}s…');
    _reconnectTimer =
        Timer(Duration(seconds: delaySec), () => _doConnect(deviceId));
  }

  Future<void> _discoverServices(BluetoothDevice device) async {
    final services = await device.discoverServices();
    for (final svc in services) {
      if (svc.uuid == Guid(NusUuids.service)) {
        for (final char in svc.characteristics) {
          if (char.uuid == Guid(NusUuids.rxChar)) _writeChar = char;
          if (char.uuid == Guid(NusUuids.txChar)) {
            _notifyChar = char;
            await char.setNotifyValue(true);
            _notifySub = char.onValueReceived.listen(_onBytes);
          }
        }
      }
    }
    if (_writeChar == null || _notifyChar == null) {
      throw Exception('NUS characteristics not found — Rivr BLE build required');
    }
  }

  // ── Receive: binary Rivr frames ───────────────────────────────────────────

  void _onBytes(List<int> bytes) {
    final event = RivrFrameCodec.parseFrame(Uint8List.fromList(bytes));
    if (event != null) _safeAddEvent(event);
  }

  // ── Send: binary Rivr frames ──────────────────────────────────────────────

  /// Converts 'chat $text\n' into a binary PKT_CHAT frame and writes it.
  /// Non-chat commands are ignored — BLE carries frames, not serial CLI.
  @override
  Future<void> send(String command) async {
    if (_writeChar == null) return;
    if (!command.startsWith('chat ')) return;
    final text = command.substring(5).trimRight();
    if (text.isEmpty) return;
    final frameBytes = RivrFrameCodec.buildChatFrame(
      srcId: phoneNodeId,
      seq: _seq++,
      text: text,
    );
    await _writeChar!.write(
      frameBytes.toList(),
      withoutResponse: _writeChar!.properties.writeWithoutResponse,
    );
  }

  // ── Disconnect ────────────────────────────────────────────────────────────

  @override
  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    await _isScanSub?.cancel();
    await _notifySub?.cancel();
    await _connSub?.cancel();
    await _device?.disconnect();
    _scanSub = null;
    _isScanSub = null;
    _notifySub = null;
    _connSub = null;
    _device = null;
    _writeChar = null;
    _notifyChar = null;
    _seenScanIds.clear();
    _emit(ConnectionStatus.disconnected, '');
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    unawaited(_shutdown());
    _stateCtrl.close();
    _eventCtrl.close();
  }

  Future<void> _shutdown() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    await _isScanSub?.cancel();
    await _notifySub?.cancel();
    await _connSub?.cancel();
    await _device?.disconnect();
  }

  Future<void> _ensurePermissions() async {
    if (!Platform.isAndroid) return;

    // Android 12+ (API 31+): BLUETOOTH_SCAN and BLUETOOTH_CONNECT are the only
    // permissions required for BLE scanning.  BLUETOOTH_SCAN is declared with
    // neverForLocation in the manifest, so ACCESS_FINE_LOCATION is not needed.
    // Android ≤ 11: BLUETOOTH_SCAN maps to the legacy BLUETOOTH permission
    // (auto-granted at install time) and ACCESS_FINE_LOCATION IS needed for BLE.
    //
    // Strategy: treat the two BT permissions as mandatory (throw on denial),
    // and request location opportunistically — silently ignored if denied on
    // Android 12+ where it is not in the manifest for API > 30.
    final btStatuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    final denied = btStatuses.entries
        .where((e) => !e.value.isGranted)
        .map((e) => e.key.toString())
        .toList();
    if (denied.isNotEmpty) {
      throw Exception('BLE permissions not granted: ${denied.join(', ')}');
    }

    // Non-fatal: required on Android ≤ 11 for BLE, not needed on Android 12+.
    await Permission.locationWhenInUse.request();
  }

  void _emit(ConnectionStatus status, String name, {String? error}) {
    if (_disposed || _stateCtrl.isClosed) return;
    _stateCtrl.add(RivrConnState(
      status: status,
      deviceName: name,
      errorMessage: error,
    ));
  }

  void _safeAddEvent(RivrEvent event) {
    if (_disposed || _eventCtrl.isClosed) return;
    _eventCtrl.add(event);
  }
}
