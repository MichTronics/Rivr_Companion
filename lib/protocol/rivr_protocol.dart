import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import '../models/metrics.dart';
import '../models/chat_message.dart';
import '../models/rivr_node.dart';

/// Families of structured events emitted by the Rivr firmware serial log.
sealed class RivrEvent {}

class MetricsEvent extends RivrEvent {
  final RivrMetrics metrics;
  MetricsEvent(this.metrics);
}

class ChatEvent extends RivrEvent {
  final ChatMessage message;
  ChatEvent(this.message);
}

class NodeEvent extends RivrEvent {
  final RivrNode node;
  NodeEvent(this.node);
}

class RawLineEvent extends RivrEvent {
  final String line;
  RawLineEvent(this.line);
}

// ── Binary Rivr frame constants ────────────────────────────────────────────

const int _kMagic = 0x5256; // 'RV' little-endian
const int _kVersion = 1;
const int _kTtlDefault = 7;
const int _kBroadcast = 0xFFFFFFFF;

// Packet type constants (§6 of the BLE integration guide).
const int _kPktChat      = 1;
const int _kPktBeacon    = 2;
const int _kPktRouteReq  = 3;
const int _kPktRouteRpl  = 4;
const int _kPktAck       = 5;
const int _kPktData      = 6;
const int _kPktProgPush  = 7;
const int _kPktTelemetry = 8;
const int _kPktMailbox   = 9;
const int _kPktAlert     = 10;
const int _kPktMetrics   = 11;

/// A decoded binary Rivr frame (§6 of the BLE integration guide).
class RivrFrame {
  final int magic;
  final int version;
  final int pktType;
  final int flags;
  final int ttl;
  final int srcId;
  final int dstId;
  final int netId;
  final int hopCount;
  final int seq;
  final int pktId;
  final Uint8List payload;

  const RivrFrame({
    required this.magic,
    required this.version,
    required this.pktType,
    required this.flags,
    required this.ttl,
    required this.srcId,
    required this.dstId,
    required this.netId,
    required this.hopCount,
    required this.seq,
    required this.pktId,
    required this.payload,
  });

  bool get isChat      => pktType == _kPktChat;
  bool get isBeacon    => pktType == _kPktBeacon;
  bool get isTelemetry => pktType == _kPktTelemetry;
  bool get isMetrics   => pktType == _kPktMetrics;

  /// Decode a frame from raw bytes.  Returns null if magic or CRC is invalid.
  static RivrFrame? decode(Uint8List bytes) {
    if (bytes.length < 25) return null; // min frame (23 header + 0 payload + 2 CRC)
    final bd = ByteData.sublistView(bytes);

    final magic = bd.getUint16(0, Endian.little);
    if (magic != _kMagic) return null;

    final payloadLen = bytes[21];
    final expectedLen = 23 + payloadLen + 2;
    if (bytes.length < expectedLen) return null;

    // Verify CRC-16/CCITT over bytes [0 .. 23+payloadLen-1]
    final crcData = bytes.sublist(0, 23 + payloadLen);
    final crcGot = bd.getUint16(23 + payloadLen, Endian.little);
    if (_crc16(crcData) != crcGot) return null;

    return RivrFrame(
      magic:     magic,
      version:   bytes[2],
      pktType:   bytes[3],
      flags:     bytes[4],
      ttl:       bytes[5],
      hopCount:  bytes[6],                              // [6]   hop
      netId:     bd.getUint16(7, Endian.little),        // [7-8] net_id
      srcId:     bd.getUint32(9, Endian.little),        // [9-12] src_id
      dstId:     bd.getUint32(13, Endian.little),       // [13-16] dst_id
      seq:       bd.getUint16(17, Endian.little),       // [17-18] seq
      pktId:     bd.getUint16(19, Endian.little),       // [19-20] pkt_id
      payload:   bytes.sublist(23, 23 + payloadLen),    // [23..] payload
    );
  }

  /// Encode this frame to bytes, computing the CRC.
  Uint8List encode() {
    final totalLen = 23 + payload.length + 2;
    final bytes = Uint8List(totalLen);
    final bd = ByteData.sublistView(bytes);

    bd.setUint16(0, _kMagic, Endian.little);
    bytes[2] = _kVersion;
    bytes[3] = pktType;
    bytes[4] = flags;
    bytes[5] = ttl;
    bytes[6] = hopCount;                              // [6]   hop
    bd.setUint16(7, netId, Endian.little);            // [7-8] net_id
    bd.setUint32(9, srcId, Endian.little);            // [9-12] src_id
    bd.setUint32(13, dstId, Endian.little);           // [13-16] dst_id
    bd.setUint16(17, seq, Endian.little);             // [17-18] seq
    bd.setUint16(19, pktId, Endian.little);           // [19-20] pkt_id
    bytes[21] = payload.length;                       // [21] payload_len
    bytes[22] = 0;                                    // [22] loop_guard
    bytes.setRange(23, 23 + payload.length, payload);

    final crc = _crc16(bytes.sublist(0, 23 + payload.length));
    bd.setUint16(23 + payload.length, crc, Endian.little);
    return bytes;
  }

  /// CRC-16/CCITT-FALSE: poly=0x1021, init=0xFFFF, refIn=false, refOut=false.
  static int _crc16(Uint8List data) {
    int crc = 0xFFFF;
    for (final byte in data) {
      crc ^= (byte & 0xFF) << 8;
      for (var i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc;
  }
}

/// Codec for building and parsing binary frames over BLE.
class RivrFrameCodec {
  /// Parse a received BLE notification (one complete binary frame) into a
  /// [RivrEvent], or return null if invalid / unrecognised.
  static RivrEvent? parseFrame(Uint8List bytes) {
    final frame = RivrFrame.decode(bytes);
    if (frame == null) return null;

    if (frame.isChat) {
      // PKT_CHAT payload is raw UTF-8 text — no header prefix
      if (frame.payload.isEmpty) return null;
      final text = utf8.decode(frame.payload, allowMalformed: true).trim();
      if (text.isEmpty) return null;
      final srcHex = '0x${frame.srcId.toRadixString(16).toUpperCase().padLeft(8, '0')}';
      return ChatEvent(ChatMessage(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        text: text,
        senderNodeId: frame.srcId,
        senderName: srcHex,
        timestamp: DateTime.now(),
        origin: MessageOrigin.remote,
      ));
    }

    // PKT_BEACON: advertises node presence — extract src_id and emit a NodeEvent.
    if (frame.isBeacon) {
      final node = RivrNode(
        nodeId: frame.srcId,
        callsign: '',
        rssiDbm: -120,
        snrDb: 0,
        hopCount: frame.hopCount,
        linkScore: 0,
        lossPercent: 0,
        lastSeen: DateTime.now(),
      );
      return NodeEvent(node);
    }

    // PKT_METRICS: compact 48-byte binary metrics snapshot (firmware pushes every 5 s)
    if (frame.isMetrics) {
      // Payload layout (all little-endian, packed struct, 48 bytes):
      // [0-3]   node_id         u32
      // [4]     dc_pct          u8
      // [5]     q_depth         u8
      // [6-9]   tx_total        u32
      // [10-13] rx_total        u32
      // [14]    route_cache     u8
      // [15]    lnk_cnt         u8
      // [16]    lnk_best        u8
      // [17]    lnk_rssi        i8
      // [18]    lnk_loss        u8
      // [19]    relay_density   u8
      // [20-23] relay_skip      u32
      // [24-27] rx_fail         u32
      // [28-31] rx_dup          u32
      // [32-35] ble_conn        u32
      // [36-39] ble_rx          u32
      // [40-43] ble_tx          u32
      // [44-47] ble_err         u32
      if (frame.payload.length < 48) return null;
      final pd = ByteData.sublistView(frame.payload);
      return MetricsEvent(RivrMetrics(
        nodeId:        pd.getUint32(0,  Endian.little),
        dcPct:         frame.payload[4],
        qDepth:        frame.payload[5],
        txTotal:       pd.getUint32(6,  Endian.little),
        rxTotal:       pd.getUint32(10, Endian.little),
        routeCache:    frame.payload[14],
        lnkCnt:        frame.payload[15],
        lnkBest:       frame.payload[16],
        lnkRssi:       pd.getInt8(17),
        lnkLoss:       frame.payload[18],
        relayDensity:  frame.payload[19],
        relaySkip:     pd.getUint32(20, Endian.little),
        rxDecodeFail:  pd.getUint32(24, Endian.little),
        rxDedupeDrop:  pd.getUint32(28, Endian.little),
        bleConn:       pd.getUint32(32, Endian.little),
        bleRx:         pd.getUint32(36, Endian.little),
        bleTx:         pd.getUint32(40, Endian.little),
        bleErr:        pd.getUint32(44, Endian.little),
        // fields not in the compact BLE payload—excluded to save space:
        relayDelay:    0, relayFwd:  0, relaySel:      0, relayCan:      0,
        rxTtlDrop:     0, rxBadType: 0, rxBadHop:      0,
        txQueueFull:   0, dutyBlocked: 0, noRoute:     0, loopDetectDrop: 0,
        radioHardReset: 0, radioTxFail: 0, radioCrcFail: 0,
        routeCacheHit: 0, routeCacheMiss: 0,
        ackTx: 0, ackRx: 0, retryAttempt: 0, retrySuccess: 0, retryFail: 0,
        collectedAt:   DateTime.now(),
      ));
    }

    // Return as raw for other types (telemetry, routing, alert, etc.)
    return RawLineEvent('BLE_FRAME:type=${frame.pktType},src=0x${frame.srcId.toRadixString(16).toUpperCase()}');
  }

  /// Build a PKT_CHAT frame for sending via BLE.
  ///
  /// [srcId] must be the phone's persistent virtual node ID.
  /// [seq] is the per-origin incrementing sequence counter.
  static Uint8List buildChatFrame({
    required int srcId,
    required int seq,
    required String text,
    int dstId = _kBroadcast,
  }) {
    // PKT_CHAT payload is raw UTF-8 text — no header prefix
    final payload = Uint8List.fromList(utf8.encode(text));

    return RivrFrame(
      magic:    _kMagic,
      version:  _kVersion,
      pktType:  _kPktChat,
      flags:    0,
      ttl:      _kTtlDefault,
      srcId:    srcId,
      dstId:    dstId,
      netId:    0,
      hopCount: 0,
      seq:      seq & 0xFFFF,
      pktId:    0,
      payload:  payload,
    ).encode();
  }

  /// Generate a random 32-bit node ID for the phone (call once, then persist).
  static int generateNodeId() => Random.secure().nextInt(0xFFFFFFFF - 1) + 1;
}

/// Parses raw text lines from the Rivr firmware serial output and emits typed
/// [RivrEvent] objects.
///
/// The parser is stateless — call [parseLine] for each line received.
class RivrProtocol {
  // ── @MET JSON ──────────────────────────────────────────────────────────────
  // Example:  @MET {"node":3735928559,"dc":12,"qdep":0,...}
  static final _metPattern = RegExp(r'^@MET\s+(\{.+\})\s*$');

  // ── @CHT JSON (primary – always emitted by firmware) ───────────────────────
  // Example:  @CHT {"src":"0xDEADBEEF","dst":"0xFFFFFFFF","rssi":-87,"len":5,"text":"hello"}
  static final _chtPattern = RegExp(r'^@CHT\s+(\{.+\})\s*$');

  // ── [CHAT][NODEID]: text  (human-readable fallback, client build) ─────────
  // Example:  [CHAT][DEADBEEF]: hello world
  static final _chatRxPattern = RegExp(
      r'\[CHAT\]\[([0-9A-Fa-f]+)\]:\s*(.+)',
      caseSensitive: false);

  // ── Beacon / node info in ntable output ───────────────────────────────────
  // Example:  0x1A2B3C4D  ALICE    1  -87  +8  72  15s  123
  static final _ntableRowPattern = RegExp(
      r'(0x[0-9A-Fa-f]{8})\s+(\S*)\s+(\d+)\s+(-?\d+)\s+(-?\d+)\s+(\d+)',
      caseSensitive: false);

  /// Parse one line of firmware output and return an event, or null if the
  /// line carries no structured information of interest.
  static RivrEvent? parseLine(String line) {
    line = line.trim();
    if (line.isEmpty) return null;

    // @MET JSON
    final metMatch = _metPattern.firstMatch(line);
    if (metMatch != null) {
      final metrics = _parseMetrics(metMatch.group(1)!);
      if (metrics != null) return MetricsEvent(metrics);
    }

    // @CHT JSON (primary)
    final chtMatch = _chtPattern.firstMatch(line);
    if (chtMatch != null) {
      final event = _parseCht(chtMatch.group(1)!);
      if (event != null) return event;
    }

    // ntable row → node update
    final nbMatch = _ntableRowPattern.firstMatch(line);
    if (nbMatch != null) {
      final nodeId = _parseHex(nbMatch.group(1)!) ?? 0;
      final callsign = nbMatch.group(2) ?? '';
      final hops = int.tryParse(nbMatch.group(3)!) ?? 0;
      final rssi = int.tryParse(nbMatch.group(4)!) ?? -120;
      final snr = int.tryParse(nbMatch.group(5)!) ?? 0;
      final score = int.tryParse(nbMatch.group(6)!) ?? 0;
      final node = RivrNode(
        nodeId: nodeId,
        callsign: callsign == '-' ? '' : callsign,
        rssiDbm: rssi,
        snrDb: snr,
        hopCount: hops,
        linkScore: score,
        lossPercent: 0,
        lastSeen: DateTime.now(),
      );
      return NodeEvent(node);
    }

    return RawLineEvent(line);
  }

  // ── @CHT JSON parser ─────────────────────────────────────────────────────
  static ChatEvent? _parseCht(String json) {
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      final srcStr = (m['src'] as String? ?? '0x0');
      final nodeId = _parseHex(srcStr) ?? 0;
      final text = (m['text'] as String? ?? '').trim();
      if (text.isEmpty) return null;
      final name = '0x${nodeId.toRadixString(16).toUpperCase().padLeft(8, '0')}';
      final msg = ChatMessage(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        text: text,
        senderNodeId: nodeId,
        senderName: name,
        timestamp: DateTime.now(),
        origin: MessageOrigin.remote,
      );
      return ChatEvent(msg);
    } catch (_) {
      return null;
    }
  }

  // ── Hex parser: accepts '0xDEADBEEF' or 'DEADBEEF' ────────────────────────
  static int? _parseHex(String s) {
    final stripped = s.startsWith('0x') || s.startsWith('0X')
        ? s.substring(2)
        : s;
    return int.tryParse(stripped, radix: 16);
  }

  // ── Parse @MET fields ─────────────────────────────────────────────────────
  static RivrMetrics? _parseMetrics(String json) {
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return RivrMetrics(
        nodeId:          _i(m, 'node_id'),       // "node_id"
        dcPct:           _i(m, 'dc_pct'),        // "dc_pct"
        qDepth:          _i(m, 'q_depth'),       // "q_depth"
        txTotal:         _i(m, 'tx_total'),      // "tx_total"
        rxTotal:         _i(m, 'rx_total'),      // "rx_total"
        routeCache:      _i(m, 'route_cache'),   // "route_cache"
        lnkCnt:          _i(m, 'lnk_cnt'),      // "lnk_cnt"
        lnkBest:         _i(m, 'lnk_best'),     // "lnk_best"
        lnkRssi:         _i(m, 'lnk_rssi'),     // "lnk_rssi"
        lnkLoss:         _i(m, 'lnk_loss'),     // "lnk_loss"
        relaySkip:       _i(m, 'relay_skip'),    // "relay_skip"
        relayDelay:      _i(m, 'relay_delay'),   // "relay_delay"
        relayDensity:    _i(m, 'relay_density'), // "relay_density"
        relayFwd:        _i(m, 'relay_fwd'),     // "relay_fwd"
        relaySel:        _i(m, 'relay_sel'),     // "relay_sel"
        relayCan:        _i(m, 'relay_can'),     // "relay_can"
        rxDecodeFail:    _i(m, 'rx_fail'),       // "rx_fail"
        rxDedupeDrop:    _i(m, 'rx_dup'),        // "rx_dup"
        rxTtlDrop:       _i(m, 'rx_ttl'),        // "rx_ttl"
        rxBadType:       _i(m, 'rx_bad_type'),   // "rx_bad_type"
        rxBadHop:        _i(m, 'rx_bad_hop'),    // "rx_bad_hop"
        txQueueFull:     _i(m, 'tx_full'),       // "tx_full"
        dutyBlocked:     _i(m, 'dc_blk'),        // "dc_blk"
        noRoute:         _i(m, 'no_route'),      // "no_route"
        loopDetectDrop:  _i(m, 'loop_drop_total'), // "loop_drop_total"
        radioHardReset:  _i(m, 'rad_rst'),       // "rad_rst"
        radioTxFail:     _i(m, 'rad_txfail'),    // "rad_txfail"
        radioCrcFail:    _i(m, 'rad_crc'),       // "rad_crc"
        routeCacheHit:   _i(m, 'rc_hit'),        // "rc_hit"
        routeCacheMiss:  _i(m, 'rc_miss'),       // "rc_miss"
        ackTx:           _i(m, 'ack_tx'),        // "ack_tx"
        ackRx:           _i(m, 'ack_rx'),        // "ack_rx"
        retryAttempt:    _i(m, 'retry_att'),     // "retry_att"
        retrySuccess:    _i(m, 'retry_ok'),      // "retry_ok"
        retryFail:       _i(m, 'retry_fail'),    // "retry_fail"
        bleConn:         _i(m, 'ble_conn'),      // "ble_conn"
        bleRx:           _i(m, 'ble_rx'),        // "ble_rx"
        bleTx:           _i(m, 'ble_tx'),        // "ble_tx"
        bleErr:          _i(m, 'ble_err'),       // "ble_err"
        collectedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  static int _i(Map<String, dynamic> m, String key) {
    final v = m[key];
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  /// Build the serial command to send a chat message.
  static String buildChatCommand(String text) => 'chat $text\n';

  /// Request the node table printout.
  static const String cmdNtable = 'ntable\n';

  /// Request a metrics snapshot.
  static const String cmdMetrics = 'metrics\n';

  /// Request the forward-candidate set status.
  static const String cmdFwdset = 'fwdset\n';

  /// Request a routing stats snapshot.
  static const String cmdRtstats = 'rtstats\n';
}
