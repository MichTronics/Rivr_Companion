import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, FileMode, Platform, Process, RandomAccessFile;
import 'dart:typed_data';

// usb_serial: Android/Windows only; calls are guarded by Platform.isLinux checks.
import 'package:usb_serial/usb_serial.dart';

import '../protocol/rivr_protocol.dart';
import 'connection_manager.dart';

/// USB Serial transport (CDC-ACM / CH340 / CP210x / FTDI).
///
/// • Android  – uses `usb_serial` (USB host permission dialog shown automatically)
/// • Linux    – enumerates /dev/ttyUSB* and /dev/ttyACM*, configures via `stty`,
///              reads/writes the character device directly with dart:io
/// • Windows  – uses `usb_serial` COM-port enumeration
///
/// Baud rate defaults to 115200, matching firmware_core/main.c UART config.
class SerialService extends RivrTransport {
  final int baudRate;
  SerialService({this.baudRate = 115200});

  final _stateCtrl = StreamController<RivrConnState>.broadcast();
  final _eventCtrl = StreamController<RivrEvent>.broadcast();
  final _lineBuffer = StringBuffer();

  // Mobile / Windows handles
  UsbPort? _usbPort;
  StreamSubscription<Uint8List>? _usbRxSub;

  // Linux handles
  StreamSubscription<List<int>>? _linuxRxSub;
  RandomAccessFile? _linuxWriteFd;

  @override
  Stream<RivrConnState> get stateStream => _stateCtrl.stream;

  @override
  Stream<RivrEvent> get eventStream => _eventCtrl.stream;

  // ── Scan ──────────────────────────────────────────────────────────────────
  @override
  Future<void> startScan() async {
    _emit(ConnectionStatus.scanning, 'USB scan');
    if (Platform.isLinux) {
      await _linuxScan();
    } else {
      await _mobileScan();
    }
    _emit(ConnectionStatus.disconnected, '');
  }

  Future<void> _linuxScan() async {
    final devDir = Directory('/dev');
    final entries = devDir.listSync();
    for (final entry in entries) {
      final name = entry.path.split('/').last;
      if (name.startsWith('ttyUSB') || name.startsWith('ttyACM')) {
        // Probe a friendly label via udevadm (best-effort, ignore failures)
        String label = name;
        try {
          final result = await Process.run(
              'udevadm', ['info', '--query=property', '--name=${entry.path}']);
          if (result.exitCode == 0) {
            final props = (result.stdout as String)
                .split('\n')
                .where((l) => l.startsWith('ID_MODEL='))
                .toList();
            if (props.isNotEmpty) {
              label = props.first.replaceFirst('ID_MODEL=', '').trim();
            }
          }
        } catch (_) {}
        // Format: USB_SCAN:<path>:<label>
        _eventCtrl
            .add(RawLineEvent('USB_SCAN:${entry.path}:$label'));
      }
    }
  }

  Future<void> _mobileScan() async {
    final devices = await UsbSerial.listDevices();
    for (final d in devices) {
      _eventCtrl.add(RawLineEvent(
          'USB_SCAN:${d.deviceId}:${d.manufacturerName ?? ''}:${d.productName ?? ''}'));
    }
  }

  // ── Connect ───────────────────────────────────────────────────────────────
  @override
  Future<void> connect(String deviceId) async {
    _emit(ConnectionStatus.connecting, deviceId);
    try {
      if (Platform.isLinux) {
        await _linuxConnect(deviceId);
      } else {
        await _mobileConnect(deviceId);
      }
    } catch (e) {
      _emit(ConnectionStatus.error, deviceId, error: e.toString());
    }
  }

  Future<void> _linuxConnect(String path) async {
    // Configure baud rate / raw mode via stty
    final stty = await Process.run(
        'stty', ['-F', path, '$baudRate', 'raw', '-echo', 'cs8', '-parenb', '-cstopb', 'cread', 'clocal']);
    if (stty.exitCode != 0) {
      throw Exception('stty failed: ${stty.stderr}');
    }

    // Open a write file-descriptor
    _linuxWriteFd = await File(path).open(mode: FileMode.writeOnly);

    // Start reading
    _linuxRxSub = File(path).openRead().listen(
      _onBytes,
      onError: (e) => _emit(ConnectionStatus.error, path, error: e.toString()),
      onDone: () => _emit(ConnectionStatus.disconnected, ''),
    );

    _emit(ConnectionStatus.connected, path.split('/').last);
  }

  Future<void> _mobileConnect(String deviceId) async {
    final devices = await UsbSerial.listDevices();
    final device = devices.firstWhere(
      (d) => d.deviceId.toString() == deviceId,
      orElse: () => throw Exception('USB device $deviceId not found'),
    );

    final port = await device.create();
    if (port == null) throw Exception('Failed to open USB port');
    _usbPort = port;

    final ok = await port.open();
    if (!ok) throw Exception('Failed to open port (permission denied?)');

    await port.setPortParameters(
        baudRate, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

    _usbRxSub = port.inputStream?.listen(_onBytes);
    _emit(ConnectionStatus.connected,
        device.productName ?? 'USB device $deviceId');
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
    final data = utf8.encode(command);
    if (Platform.isLinux) {
      await _linuxWriteFd?.writeFrom(data);
    } else {
      await _usbPort?.write(Uint8List.fromList(data));
    }
  }

  // ── Disconnect ────────────────────────────────────────────────────────────
  @override
  Future<void> disconnect() async {
    await _linuxRxSub?.cancel();
    await _linuxWriteFd?.close();
    _linuxRxSub = null;
    _linuxWriteFd = null;

    await _usbRxSub?.cancel();
    await _usbPort?.close();
    _usbRxSub = null;
    _usbPort = null;

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
