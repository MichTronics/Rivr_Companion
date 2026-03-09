import 'package:equatable/equatable.dart';

enum MessageOrigin { local, remote, system }

class ChatMessage extends Equatable {
  final String id;
  final String text;
  final int senderNodeId;    // 0 = this device / system
  final String senderName;   // callsign or node-ID string
  final DateTime timestamp;
  final MessageOrigin origin;

  const ChatMessage({
    required this.id,
    required this.text,
    required this.senderNodeId,
    required this.senderName,
    required this.timestamp,
    required this.origin,
  });

  bool get isLocal => origin == MessageOrigin.local;
  bool get isSystem => origin == MessageOrigin.system;

  factory ChatMessage.local({required String text, required int myNodeId, required String myCallsign}) {
    return ChatMessage(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      text: text,
      senderNodeId: myNodeId,
      senderName: myCallsign.isNotEmpty ? myCallsign : 'Me',
      timestamp: DateTime.now(),
      origin: MessageOrigin.local,
    );
  }

  factory ChatMessage.system(String text) {
    return ChatMessage(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      text: text,
      senderNodeId: 0,
      senderName: 'System',
      timestamp: DateTime.now(),
      origin: MessageOrigin.system,
    );
  }

  @override
  List<Object?> get props => [id, text, senderNodeId, timestamp, origin];
}
