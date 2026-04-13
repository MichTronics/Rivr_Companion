import 'package:equatable/equatable.dart';

enum MessageOrigin { local, remote, system }

class ChatMessage extends Equatable {
  final String id;
  final String text;
  final int senderNodeId;    // 0 = this device / system
  final String senderName;   // callsign or node-ID string
  final DateTime timestamp;
  final MessageOrigin origin;
  /// Wire channel_id.  0 = Global (default for legacy PKT_CHAT without
  /// PKT_FLAG_CHANNEL).  Set from the channel_id prefix when PKT_FLAG_CHANNEL
  /// is present in the received frame.
  final int channelId;

  const ChatMessage({
    required this.id,
    required this.text,
    required this.senderNodeId,
    required this.senderName,
    required this.timestamp,
    required this.origin,
    this.channelId = 0,
  });

  bool get isLocal => origin == MessageOrigin.local;
  bool get isSystem => origin == MessageOrigin.system;

  factory ChatMessage.local({
    required String text,
    required int myNodeId,
    required String myCallsign,
    int channelId = 0,
  }) {
    return ChatMessage(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      text: text,
      senderNodeId: myNodeId,
      senderName: myCallsign.isNotEmpty ? myCallsign : 'Me',
      timestamp: DateTime.now(),
      origin: MessageOrigin.local,
      channelId: channelId,
    );
  }

  factory ChatMessage.system(String text, {int channelId = 0}) {
    return ChatMessage(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      text: text,
      senderNodeId: 0,
      senderName: 'System',
      timestamp: DateTime.now(),
      origin: MessageOrigin.system,
      channelId: channelId,
    );
  }

  @override
  List<Object?> get props => [id, text, senderNodeId, timestamp, origin, channelId];
}

