import 'package:equatable/equatable.dart';

/// A Rivr mesh node discovered via beacons or the `ntable` CLI command.
class RivrNode extends Equatable {
  final int nodeId;         // 32-bit node ID (hex: 0x1A2B3C4D)
  final String callsign;    // Up to 11 chars, empty if unknown
  final int rssiDbm;        // Last heard RSSI in dBm
  final int snrDb;          // Last heard SNR in dB
  final int hopCount;       // Hop distance from this device
  final int linkScore;      // 0-100 composite quality score
  final int lossPercent;    // Packet loss %
  final DateTime lastSeen;  // Timestamp of last received frame

  const RivrNode({
    required this.nodeId,
    required this.callsign,
    required this.rssiDbm,
    required this.snrDb,
    required this.hopCount,
    required this.linkScore,
    required this.lossPercent,
    required this.lastSeen,
  });

  /// Short display label: callsign if non-empty, else truncated hex ID.
  String get displayName =>
      callsign.isNotEmpty ? callsign : '0x${nodeId.toRadixString(16).toUpperCase().padLeft(8, '0')}';

  String get nodeIdHex =>
      '0x${nodeId.toRadixString(16).toUpperCase().padLeft(8, '0')}';

  bool get isStale => DateTime.now().difference(lastSeen).inSeconds > 60;

  RivrNode copyWith({
    int? nodeId,
    String? callsign,
    int? rssiDbm,
    int? snrDb,
    int? hopCount,
    int? linkScore,
    int? lossPercent,
    DateTime? lastSeen,
  }) {
    return RivrNode(
      nodeId: nodeId ?? this.nodeId,
      callsign: callsign ?? this.callsign,
      rssiDbm: rssiDbm ?? this.rssiDbm,
      snrDb: snrDb ?? this.snrDb,
      hopCount: hopCount ?? this.hopCount,
      linkScore: linkScore ?? this.linkScore,
      lossPercent: lossPercent ?? this.lossPercent,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  List<Object?> get props =>
      [nodeId, callsign, rssiDbm, snrDb, hopCount, linkScore, lossPercent, lastSeen];
}
