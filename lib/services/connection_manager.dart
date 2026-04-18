import 'dart:async';
import 'dart:developer' as dev;
import '../protocol/rivr_protocol.dart';
import '../models/app_settings.dart';

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
      final wasConnected = _lastState.isConnected;
      _lastState = s;
      _stateController.add(s);
      if (!wasConnected && s.isConnected && _pendingConnectionType == ConnectionType.usb) {
        // USB just connected — query the node for its stored identity + position.
        Future.delayed(const Duration(milliseconds: 300), () => send('id\n'));
      }
      if (wasConnected && !s.isConnected) {
        RivrProtocol.resetIdState();
      }
    });
    _eventSub = transport.eventStream.listen(_eventController.add);
  }

  /// Set the connection type hint so the manager knows when to send `id`.
  /// Call this before [connect].
  void setPendingConnectionType(ConnectionType type) {
    _pendingConnectionType = type;
  }

  ConnectionType _pendingConnectionType = ConnectionType.usb;

  Future<void> startScan() => _transport?.startScan() ?? Future.value();
  Future<void> connect(String deviceId) => _transport?.connect(deviceId) ?? Future.value();
  Future<void> disconnect() => _transport?.disconnect() ?? Future.value();
  Future<void> send(String command) {
    if (_transport == null) {
      dev.log('send() called with no active transport — command dropped: $command',
          name: 'ConnectionManager', level: 900);
      return Future.value();
    }
    return _transport!.send(command);
  }

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
