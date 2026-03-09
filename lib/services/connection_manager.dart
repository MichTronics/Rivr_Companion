import 'dart:async';
import '../protocol/rivr_protocol.dart';

/// Connection state snapshot.
enum ConnectionStatus {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

class RivrConnState {
  final ConnectionStatus status;
  final String deviceName;
  final String? errorMessage;

  const RivrConnState({
    required this.status,
    this.deviceName = '',
    this.errorMessage,
  });

  bool get isConnected => status == ConnectionStatus.connected;
  bool get isScanning => status == ConnectionStatus.scanning;
}

/// Abstract interface for a Rivr transport layer (BLE or USB Serial).
///
/// Implementors must:
///   • expose a [stateStream] of [RivrConnState] snapshots
///   • expose an [eventStream] of parsed [RivrEvent] objects
///   • implement [connect], [disconnect], and [send]
abstract class RivrTransport {
  Stream<RivrConnState> get stateStream;
  Stream<RivrEvent> get eventStream;

  Future<void> startScan();
  Future<void> connect(String deviceId);
  Future<void> disconnect();
  Future<void> send(String command);

  void dispose();
}

/// Top-level connection manager: owns the active transport and re-exposes its
/// streams.  Switch transports at runtime by calling [useTransport].
///
/// Obtain via Riverpod: `ref.watch(connectionManagerProvider)`.
class ConnectionManager {
  RivrTransport? _transport;

  final _stateController = StreamController<RivrConnState>.broadcast();
  final _eventController = StreamController<RivrEvent>.broadcast();

  StreamSubscription<RivrConnState>? _stateSub;
  StreamSubscription<RivrEvent>? _eventSub;

  RivrConnState _lastState = const RivrConnState(status: ConnectionStatus.disconnected);

  Stream<RivrConnState> get stateStream => _stateController.stream;
  Stream<RivrEvent> get eventStream => _eventController.stream;
  RivrConnState get currentState => _lastState;

  /// Replace the active transport.  Disconnects the previous one first.
  Future<void> useTransport(RivrTransport transport) async {
    await _detach();
    _transport = transport;
    _stateSub = transport.stateStream.listen((s) {
      _lastState = s;
      _stateController.add(s);
    });
    _eventSub = transport.eventStream.listen(_eventController.add);
  }

  Future<void> startScan() => _transport?.startScan() ?? Future.value();
  Future<void> connect(String deviceId) => _transport?.connect(deviceId) ?? Future.value();
  Future<void> disconnect() => _transport?.disconnect() ?? Future.value();
  Future<void> send(String command) => _transport?.send(command) ?? Future.value();

  Future<void> _detach() async {
    await _stateSub?.cancel();
    await _eventSub?.cancel();
    _transport?.dispose();
    _transport = null;
    _stateSub = null;
    _eventSub = null;
  }

  void dispose() {
    _detach();
    _stateController.close();
    _eventController.close();
  }
}
