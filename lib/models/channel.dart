import 'package:equatable/equatable.dart';

// ── Channel kind ───────────────────────────────────────────────────────────

enum ChannelKind {
  public,
  group,
  emergency,
  system,
  restricted,
}

// ── Channel config flags ───────────────────────────────────────────────────

const int chanFlagEncrypted  = 0x0001;
const int chanFlagTwoMember  = 0x0002;
const int chanFlagPriority   = 0x0004;

// ── Compile-time channel bounds ────────────────────────────────────────────

const int kMaxChannels       = 8;
const int kChanGlobal        = 0;
const int kChanTxNone        = 0xFF;

// ── Default channel table ──────────────────────────────────────────────────

const List<ChannelConfig> kDefaultChannels = [
  ChannelConfig(id: 0, kind: ChannelKind.public,    flags: 0,                  keySlot: 0, name: 'Global'),
  ChannelConfig(id: 1, kind: ChannelKind.group,     flags: 0,                  keySlot: 0, name: 'Ops'),
  ChannelConfig(id: 2, kind: ChannelKind.group,     flags: 0,                  keySlot: 0, name: 'Local'),
  ChannelConfig(id: 3, kind: ChannelKind.emergency, flags: chanFlagPriority,   keySlot: 0, name: 'Emergency'),
  ChannelConfig(id: 4, kind: ChannelKind.group,     flags: 0,                  keySlot: 0, name: 'Sensor'),
  ChannelConfig(id: 5, kind: ChannelKind.group,     flags: 0,                  keySlot: 0, name: ''),
  ChannelConfig(id: 6, kind: ChannelKind.group,     flags: 0,                  keySlot: 0, name: ''),
  ChannelConfig(id: 7, kind: ChannelKind.group,     flags: 0,                  keySlot: 0, name: ''),
];

const List<ChannelMembership> kDefaultMembership = [
  ChannelMembership(channelId: 0, joined: true,  muted: false, hidden: false, txDefault: true),
  ChannelMembership(channelId: 1, joined: true,  muted: false, hidden: false, txDefault: false),
  ChannelMembership(channelId: 2, joined: false, muted: false, hidden: false, txDefault: false),
  ChannelMembership(channelId: 3, joined: true,  muted: false, hidden: false, txDefault: false),
  ChannelMembership(channelId: 4, joined: true,  muted: false, hidden: false, txDefault: false),
  ChannelMembership(channelId: 5, joined: false, muted: false, hidden: true,  txDefault: false),
  ChannelMembership(channelId: 6, joined: false, muted: false, hidden: true,  txDefault: false),
  ChannelMembership(channelId: 7, joined: false, muted: false, hidden: true,  txDefault: false),
];

// ── ChannelConfig ──────────────────────────────────────────────────────────

class ChannelConfig extends Equatable {
  final int channelId;  // wire channel_id (u16)
  final ChannelKind kind;
  final int flags;      // chanFlag* bitmask
  final int keySlot;    // 0 = plaintext
  final String name;

  const ChannelConfig({
    required int id,
    required this.kind,
    required this.flags,
    required this.keySlot,
    required this.name,
  }) : channelId = id;

  bool get isEncrypted  => (flags & chanFlagEncrypted) != 0;
  bool get isTwoMember  => (flags & chanFlagTwoMember) != 0;
  bool get isPriority   => (flags & chanFlagPriority)  != 0 || kind == ChannelKind.emergency;

  String get displayName => name.isNotEmpty ? name : 'Channel $channelId';

  ChannelConfig copyWith({
    int? id,
    ChannelKind? kind,
    int? flags,
    int? keySlot,
    String? name,
  }) => ChannelConfig(
    id:      id      ?? channelId,
    kind:    kind    ?? this.kind,
    flags:   flags   ?? this.flags,
    keySlot: keySlot ?? this.keySlot,
    name:    name    ?? this.name,
  );

  @override
  List<Object?> get props => [channelId, kind, flags, keySlot, name];
}

// ── ChannelMembership ──────────────────────────────────────────────────────

class ChannelMembership extends Equatable {
  final int channelId;
  final bool joined;
  final bool muted;
  final bool hidden;
  final bool txDefault;

  const ChannelMembership({
    required this.channelId,
    required this.joined,
    required this.muted,
    required this.hidden,
    required this.txDefault,
  });

  ChannelMembership copyWith({
    bool? joined,
    bool? muted,
    bool? hidden,
    bool? txDefault,
  }) => ChannelMembership(
    channelId: channelId,
    joined:    joined    ?? this.joined,
    muted:     muted     ?? this.muted,
    hidden:    hidden    ?? this.hidden,
    txDefault: txDefault ?? this.txDefault,
  );

  @override
  List<Object?> get props => [channelId, joined, muted, hidden, txDefault];
}

// ── ChannelMessage ─────────────────────────────────────────────────────────

/// A chat message that belongs to a specific channel.
/// All user-visible messages are ChannelMessages; channel 0 = Global.
enum MessageOrigin { local, remote, system }

class ChannelMessage extends Equatable {
  final String id;
  final String text;
  final int senderNodeId;    // 0 = this device / system
  final String senderName;
  final DateTime timestamp;
  final MessageOrigin origin;
  final int channelId;       // wire channel_id; 0 = Global

  const ChannelMessage({
    required this.id,
    required this.text,
    required this.senderNodeId,
    required this.senderName,
    required this.timestamp,
    required this.origin,
    required this.channelId,
  });

  bool get isLocal  => origin == MessageOrigin.local;
  bool get isSystem => origin == MessageOrigin.system;

  factory ChannelMessage.local({
    required String text,
    required int myNodeId,
    required String myCallsign,
    required int channelId,
  }) {
    return ChannelMessage(
      id:           '${DateTime.now().microsecondsSinceEpoch}',
      text:         text,
      senderNodeId: myNodeId,
      senderName:   myCallsign.isNotEmpty ? myCallsign : 'Me',
      timestamp:    DateTime.now(),
      origin:       MessageOrigin.local,
      channelId:    channelId,
    );
  }

  factory ChannelMessage.system(String text, {int channelId = kChanGlobal}) {
    return ChannelMessage(
      id:           '${DateTime.now().microsecondsSinceEpoch}',
      text:         text,
      senderNodeId: 0,
      senderName:   'System',
      timestamp:    DateTime.now(),
      origin:       MessageOrigin.system,
      channelId:    channelId,
    );
  }

  factory ChannelMessage.remote({
    required String id,
    required String text,
    required int senderNodeId,
    required String senderName,
    required DateTime timestamp,
    required int channelId,
  }) {
    return ChannelMessage(
      id:           id,
      text:         text,
      senderNodeId: senderNodeId,
      senderName:   senderName,
      timestamp:    timestamp,
      origin:       MessageOrigin.remote,
      channelId:    channelId,
    );
  }

  @override
  List<Object?> get props => [id, text, senderNodeId, timestamp, origin, channelId];
}

// ── ChannelState ──────────────────────────────────────────────────────────

/// Complete observable state for one channel.
class ChannelState extends Equatable {
  final ChannelConfig config;
  final ChannelMembership membership;
  final int unreadCount;

  const ChannelState({
    required this.config,
    required this.membership,
    this.unreadCount = 0,
  });

  ChannelState copyWith({
    ChannelConfig? config,
    ChannelMembership? membership,
    int? unreadCount,
  }) => ChannelState(
    config:      config      ?? this.config,
    membership:  membership  ?? this.membership,
    unreadCount: unreadCount ?? this.unreadCount,
  );

  @override
  List<Object?> get props => [config, membership, unreadCount];
}
