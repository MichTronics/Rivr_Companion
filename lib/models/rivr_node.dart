import 'dart:math' as math;
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
  /// Node role: 0=unknown, 1=client, 2=repeater, 3=gateway
  final int role;
  /// Geographic latitude in decimal degrees; null if not known.
  final double? lat;
  /// Geographic longitude in decimal degrees; null if not known.
  final double? lon;
  /// User-assigned display alias; overrides callsign when set.
  final String? alias;

  const RivrNode({
    required this.nodeId,
    required this.callsign,
    required this.rssiDbm,
    required this.snrDb,
    required this.hopCount,
    required this.linkScore,
    required this.lossPercent,
    required this.lastSeen,
    this.role = 0,
    this.lat,
    this.lon,
    this.alias,
  });

  /// True when both lat and lon are available.
  bool get hasPosition => lat != null && lon != null;

  /// Short display label: alias if set, callsign if non-empty, else truncated hex ID.
  String get displayName =>
      alias?.isNotEmpty == true
          ? alias!
          : callsign.isNotEmpty
              ? callsign
              : '0x${nodeId.toRadixString(16).toUpperCase().padLeft(8, '0')}';

  String get nodeIdHex =>
      '0x${nodeId.toRadixString(16).toUpperCase().padLeft(8, '0')}';

  bool get isRepeater => role == 2;
  bool get isGateway  => role == 3;

  String get roleLabel {
    switch (role) {
      case 2: return 'Repeater';
      case 3: return 'Gateway';
      case 1: return 'Client';
      default: return '';
    }
  }

  bool get isStale => DateTime.now().difference(lastSeen).inSeconds > 60;

  /// Distance in metres to [other], or null if either node lacks a position.
  double? distanceTo(RivrNode other) {
    if (!hasPosition || !other.hasPosition) return null;
    return _haversineMetres(lat!, lon!, other.lat!, other.lon!);
  }

  /// Haversine distance in metres between two WGS-84 coordinate pairs.
  static double _haversineMetres(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180.0;

  RivrNode copyWith({
    int? nodeId,
    String? callsign,
    int? rssiDbm,
    int? snrDb,
    int? hopCount,
    int? linkScore,
    int? lossPercent,
    DateTime? lastSeen,
    int? role,
    Object? lat = _sentinel,
    Object? lon = _sentinel,
    Object? alias = _sentinel,
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
      role: role ?? this.role,
      lat: lat == _sentinel ? this.lat : lat as double?,
      lon: lon == _sentinel ? this.lon : lon as double?,
      alias: alias == _sentinel ? this.alias : alias as String?,
    );
  }

  // Sentinel to distinguish "not passed" from explicit null in copyWith.
  static const Object _sentinel = Object();

  @override
  List<Object?> get props =>
      [nodeId, callsign, rssiDbm, snrDb, hopCount, linkScore, lossPercent, lastSeen, role, lat, lon, alias];
}

