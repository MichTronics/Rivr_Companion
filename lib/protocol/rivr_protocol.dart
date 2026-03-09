import 'dart:convert';
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
