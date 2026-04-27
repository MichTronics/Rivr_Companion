import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rivr_companion/models/chat_message.dart';
import 'package:rivr_companion/protocol/rivr_protocol.dart';
import 'package:rivr_companion/services/connection_manager.dart';

class _FakeTransport implements RivrTransport {
  final _stateController = StreamController<RivrConnState>.broadcast();
  final _eventController = StreamController<RivrEvent>.broadcast();

  @override
  Stream<RivrConnState> get stateStream => _stateController.stream;

  @override
  Stream<RivrEvent> get eventStream => _eventController.stream;

  @override
  Future<void> startScan() async {}

  @override
  Future<void> connect(String deviceId) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> send(String command) async {}

  @override
  Future<void> sendRaw(Uint8List bytes) async {}

  @override
  void dispose() {}

  void emitState(RivrConnState state) {
    _stateController.add(state);
  }

  void emitEvent(RivrEvent event) {
    _eventController.add(event);
  }

  Future<void> close() async {
    await _stateController.close();
    await _eventController.close();
  }
}

void main() {
  test('connection manager ignores late transport emissions after dispose', () async {
    final manager = ConnectionManager();
    final transport = _FakeTransport();
    final states = <RivrConnState>[];
    final events = <RivrEvent>[];

    final stateSub = manager.stateStream.listen(states.add);
    final eventSub = manager.eventStream.listen(events.add);

    await manager.useTransport(transport);

    transport.emitState(
      const RivrConnState(
        status: ConnectionStatus.connected,
        deviceName: 'test-node',
      ),
    );
    transport.emitEvent(
      ChatEvent(
        ChatMessage.system('before dispose'),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(states, hasLength(1));
    expect(events, hasLength(1));

    manager.dispose();

    transport.emitState(
      const RivrConnState(
        status: ConnectionStatus.disconnected,
        deviceName: 'late-node',
      ),
    );
    transport.emitEvent(
      ChatEvent(
        ChatMessage.system('after dispose'),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(states, hasLength(1));
    expect(events, hasLength(1));

    await stateSub.cancel();
    await eventSub.cancel();
    await transport.close();
  });
}