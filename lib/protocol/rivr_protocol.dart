import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import '../models/metrics.dart';
import '../models/chat_message.dart';
import '../models/rivr_node.dart';
import '../models/telemetry_reading.dart';

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

class TelemetryEvent extends RivrEvent {
  final TelemetryReading reading;
  TelemetryEvent(this.reading);
}

class DeviceInfoEvent extends RivrEvent {
  final int nodeId;
  final String callsign;
  /// Geographic position decoded from the `id` CLI response; null if not set.
  final double? lat;
  final double? lon;
  /// Node role: 0=unknown, 1=client, 2=repeater, 3=gateway.
  final int role;
  DeviceInfoEvent({
    required this.nodeId,
    required this.callsign,
    this.lat,
    this.lon,
    this.role = 0,
  });
}

class RivrLogFormatter {
  static String? toUsbLikeRawLine(RivrEvent event) {
    if (event is RawLineEvent) return event.line;

    if (event is ChatEvent) {
      final message = event.message;
      return '@CHT ${jsonEncode({
        'src': _hex32(message.senderNodeId),
        'text': message.text,
        'chan': message.channelId,
      })}';
    }

    if (event is TelemetryEvent) {
      final reading = event.reading;
      return '@TEL ${jsonEncode({
        'src': _hex32(reading.srcNodeId),
        'sid': reading.sensorId,
        'val': reading.valueX100,
        'unit': reading.unitCode,
        'ts': reading.timestampS,
      })}';
    }

    if (event is NodeEvent) {
      final node = event.node;
      final payload = <String, dynamic>{
        'src': _hex32(node.nodeId),
        'cs': node.callsign,
        'rssi': node.rssiDbm,
        'snr': node.snrDb,
        'hop': max(node.hopCount - 1, 0),
        'score': node.linkScore,
        'role': node.role,
      };
      if (node.lat != null) payload['lat'] = node.lat;
      if (node.lon != null) payload['lon'] = node.lon;
      return '@BCN ${jsonEncode(payload)}';
    }

    if (event is MetricsEvent) {
      final metrics = event.metrics;
      return '@MET ${jsonEncode({
        'node_id': metrics.nodeId,
        'dc_pct': metrics.dcPct,
        'q_depth': metrics.qDepth,
        'tx_total': metrics.txTotal,
        'rx_total': metrics.rxTotal,
        'route_cache': metrics.routeCache,
        'lnk_cnt': metrics.lnkCnt,
        'lnk_best': metrics.lnkBest,
        'lnk_rssi': metrics.lnkRssi,
        'lnk_loss': metrics.lnkLoss,
        'relay_skip': metrics.relaySkip,
        'relay_delay': metrics.relayDelay,
        'relay_density': metrics.relayDensity,
        'relay_fwd': metrics.relayFwd,
        'relay_sel': metrics.relaySel,
        'relay_can': metrics.relayCan,
        'rx_fail': metrics.rxDecodeFail,
        'rx_dup': metrics.rxDedupeDrop,
        'rx_ttl': metrics.rxTtlDrop,
        'rx_bad_type': metrics.rxBadType,
        'rx_bad_hop': metrics.rxBadHop,
        'tx_full': metrics.txQueueFull,
        'dc_blk': metrics.dutyBlocked,
        'no_route': metrics.noRoute,
        'loop_drop_total': metrics.loopDetectDrop,
        'rad_rst': metrics.radioHardReset,
        'rad_txfail': metrics.radioTxFail,
        'rad_crc': metrics.radioCrcFail,
        'rc_hit': metrics.routeCacheHit,
        'rc_miss': metrics.routeCacheMiss,
        'ack_tx': metrics.ackTx,
        'ack_rx': metrics.ackRx,
        'retry_att': metrics.retryAttempt,
        'retry_ok': metrics.retrySuccess,
        'retry_fail': metrics.retryFail,
        'ble_conn': metrics.bleConn,
        'ble_rx': metrics.bleRx,
        'ble_tx': metrics.bleTx,
        'ble_err': metrics.bleErr,
      })}';
    }

    return null;
  }

  static String _hex32(int value) =>
      '0x${value.toRadixString(16).toUpperCase().padLeft(8, '0')}';
}

// ── Binary Rivr frame constants ────────────────────────────────────────────

const int _kMagic = 0x5256; // 'RV' little-endian
const int _kVersion = 1;
const int _kTtlDefault = 7;
const int _kBroadcast = 0;

// Packet type constants (§6 of the BLE integration guide).
const int _kPktChat = 1;
const int _kPktBeacon = 2;
const int _kPktTelemetry = 8;
const int _kPktMetrics = 11;
const int _kCompanionMagic = 0x4352; // 'RC' little-endian
const int _kCompanionVersion = 1;
const int _kCompanionHdrLen = 5;
const int _kBleFragMagic0 = 0x52; // 'R'
const int _kBleFragMagic1 = 0x42; // 'B'
const int _kBleFragVersion = 1;
const int _kBleFragHdrLen = 6;
const int _kBleFragRxSlots = 4;

const int _kCpCmdAppStart = 0x01;
const int _kCpCmdDeviceQuery = 0x02;
const int _kCpCmdSetCallsign = 0x03;
const int _kCpCmdGetNeighbors = 0x04;
const int _kCpCmdSetPosition = 0x05;
const int _kCpCmdClearPosition = 0x06;

const int _kCpPktOk = 0x80;
const int _kCpPktErr = 0x81;
const int _kCpPktDeviceInfo = 0x82;
const int _kCpPktNodeInfo = 0x83;
const int _kCpPktNodeListDone = 0x84;
const int _kCpPktChatRx = 0x85;
const int _kCpPktTelemetry = 0x86;

class RivrBleReassembler {
  final List<_BleFragmentSlot> _slots =
      List.generate(_kBleFragRxSlots, (_) => _BleFragmentSlot());
  int _nextSlot = 0;

  static bool isFragmentPacket(Uint8List bytes) {
    if (bytes.length < _kBleFragHdrLen) return false;
    return bytes[0] == _kBleFragMagic0 &&
        bytes[1] == _kBleFragMagic1 &&
        bytes[2] == _kBleFragVersion;
  }

  void reset() {
    for (final slot in _slots) {
      slot.reset();
    }
    _nextSlot = 0;
  }

  Uint8List? ingest(Uint8List packet) {
    if (!isFragmentPacket(packet)) {
      return packet;
    }

    final messageId = packet[3];
    final offset = packet[4];
    final totalLen = packet[5];
    final fragmentLen = packet.length - _kBleFragHdrLen;

    if (totalLen == 0 || totalLen > 255) {
      throw const FormatException('Invalid BLE fragment total length');
    }
    if (fragmentLen == 0 || offset >= totalLen) {
      throw const FormatException('Invalid BLE fragment layout');
    }
    if (offset + fragmentLen > totalLen) {
      throw const FormatException('BLE fragment overruns total length');
    }

    var slot = _findSlot(messageId);
    if (slot == null) {
      if (offset != 0) {
        throw const FormatException('BLE fragment stream started mid-message');
      }
      slot = _allocSlot();
      slot.start(messageId, totalLen);
    } else if (offset == 0) {
      slot.start(messageId, totalLen);
    } else if (slot.totalLen != totalLen) {
      slot.reset();
      throw const FormatException(
          'BLE fragment total length changed mid-stream');
    }

    if (offset != slot.receivedLen) {
      slot.reset();
      throw const FormatException('BLE fragment stream is out of order');
    }

    final buffer = slot.buffer!;
    buffer.setRange(
      offset,
      offset + fragmentLen,
      packet,
      _kBleFragHdrLen,
    );
    slot.receivedLen += fragmentLen;

    if (slot.receivedLen < totalLen) {
      return null;
    }

    final completed = Uint8List.fromList(buffer);
    slot.reset();
    return completed;
  }

  _BleFragmentSlot? _findSlot(int messageId) {
    for (final slot in _slots) {
      if (slot.active && slot.messageId == messageId) {
        return slot;
      }
    }
    return null;
  }

  _BleFragmentSlot _allocSlot() {
    for (final slot in _slots) {
      if (!slot.active) {
        return slot;
      }
    }

    final slot = _slots[_nextSlot];
    _nextSlot = (_nextSlot + 1) % _slots.length;
    slot.reset();
    return slot;
  }
}

class _BleFragmentSlot {
  bool active = false;
  int? messageId;
  int? totalLen;
  int receivedLen = 0;
  Uint8List? buffer;

  void reset() {
    active = false;
    messageId = null;
    totalLen = null;
    receivedLen = 0;
    buffer = null;
  }

  void start(int newMessageId, int newTotalLen) {
    active = true;
    messageId = newMessageId;
    totalLen = newTotalLen;
    receivedLen = 0;
    buffer = Uint8List(newTotalLen);
  }
}

class RivrBleFragmentCodec {
  static Iterable<Uint8List> encode(Uint8List payload,
      {required int linkPayloadLimit, required int messageId}) sync* {
    if (payload.isEmpty || payload.length > 255) {
      throw const FormatException('BLE payload length out of range');
    }
    if (linkPayloadLimit <= 0) {
      throw const FormatException('BLE payload limit unavailable');
    }
    if (payload.length <= linkPayloadLimit) {
      yield payload;
      return;
    }
    if (linkPayloadLimit <= _kBleFragHdrLen) {
      throw const FormatException('BLE payload limit too small for fragments');
    }

    final fragmentPayloadLimit = linkPayloadLimit - _kBleFragHdrLen;
    for (var offset = 0;
        offset < payload.length;
        offset += fragmentPayloadLimit) {
      final chunkLen = min(fragmentPayloadLimit, payload.length - offset);
      final fragment = Uint8List(_kBleFragHdrLen + chunkLen);
      fragment[0] = _kBleFragMagic0;
      fragment[1] = _kBleFragMagic1;
      fragment[2] = _kBleFragVersion;
      fragment[3] = messageId & 0xFF;
      fragment[4] = offset & 0xFF;
      fragment[5] = payload.length & 0xFF;
      fragment.setRange(
        _kBleFragHdrLen,
        fragment.length,
        payload,
        offset,
      );
      yield fragment;
    }
  }
}

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

  bool get isChat => pktType == _kPktChat;
  bool get isBeacon => pktType == _kPktBeacon;
  bool get isTelemetry => pktType == _kPktTelemetry;
  bool get isMetrics => pktType == _kPktMetrics;

  /// Decode a frame from raw bytes.  Returns null if magic or CRC is invalid.
  static RivrFrame? decode(Uint8List bytes) {
    if (bytes.length < 25) {
      return null; // min frame (23 header + 0 payload + 2 CRC)
    }
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
      magic: magic,
      version: bytes[2],
      pktType: bytes[3],
      flags: bytes[4],
      ttl: bytes[5],
      hopCount: bytes[6], // [6]   hop
      netId: bd.getUint16(7, Endian.little), // [7-8] net_id
      srcId: bd.getUint32(9, Endian.little), // [9-12] src_id
      dstId: bd.getUint32(13, Endian.little), // [13-16] dst_id
      seq: bd.getUint16(17, Endian.little), // [17-18] seq
      pktId: bd.getUint16(19, Endian.little), // [19-20] pkt_id
      payload: bytes.sublist(23, 23 + payloadLen), // [23..] payload
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
    bytes[6] = hopCount; // [6]   hop
    bd.setUint16(7, netId, Endian.little); // [7-8] net_id
    bd.setUint32(9, srcId, Endian.little); // [9-12] src_id
    bd.setUint32(13, dstId, Endian.little); // [13-16] dst_id
    bd.setUint16(17, seq, Endian.little); // [17-18] seq
    bd.setUint16(19, pktId, Endian.little); // [19-20] pkt_id
    bytes[21] = payload.length; // [21] payload_len
    bytes[22] = 0; // [22] loop_guard
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
  static const int _kLegacyBleMetricsLen = 48;
  static const int _kFullBleMetricsLen = 132;

  static const _pktTypeNames = {
    1: 'CHAT',
    2: 'BEACON',
    3: 'ROUTE_REQ',
    4: 'ROUTE_RPL',
    5: 'ACK',
    6: 'DATA',
    7: 'PROG_PUSH',
    8: 'TELEMETRY',
    9: 'MAILBOX',
    10: 'ALERT',
    11: 'METRICS',
  };

  static String describeFrame(Uint8List bytes, {required String direction}) {
    final frame = RivrFrame.decode(bytes);
    final hex = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');

    if (frame == null) {
      return '$direction BLE_FRAME invalid len=${bytes.length} hex=$hex';
    }

    final typeName =
        _pktTypeNames[frame.pktType] ?? 'TYPE${frame.pktType}';
    final src =
        '0x${frame.srcId.toRadixString(16).toUpperCase().padLeft(8, '0')}';
    final dst =
        '0x${frame.dstId.toRadixString(16).toUpperCase().padLeft(8, '0')}';

    final base = '$direction BLE_$typeName'
        ' src=$src'
        ' dst=$dst'
        ' seq=${frame.seq}'
        ' hop=${frame.hopCount}'
        ' len=${frame.payload.length}';

    // Decode beacon payload inline so it is readable without a hex editor.
    if (frame.pktType == _kPktBeacon && frame.payload.length >= 12) {
      final csBytes = frame.payload.sublist(0, 10);
      final nullIdx = csBytes.indexOf(0);
      final csEnd = nullIdx >= 0 ? nullIdx : 10;
      final callsign =
          String.fromCharCodes(csBytes.sublist(0, csEnd)).trim();
      final role = frame.payload[11];
      const roleNames = {1: 'client', 2: 'repeater', 3: 'gateway'};
      final roleName = roleNames[role] ?? 'role$role';

      String posStr = '';
      const int kFlagHasPos = 0x10;
      if ((frame.flags & kFlagHasPos) != 0 && frame.payload.length >= 20) {
        final bpd = ByteData.sublistView(frame.payload);
        final latE7 = bpd.getInt32(12, Endian.little);
        final lonE7 = bpd.getInt32(16, Endian.little);
        if (latE7 != -2147483648 && lonE7 != -2147483648) {
          posStr =
              ' lat=${(latE7 / 1e7).toStringAsFixed(5)} lon=${(lonE7 / 1e7).toStringAsFixed(5)}';
        }
      }
      return '$base cs=${callsign.isEmpty ? '?' : callsign} role=$roleName$posStr';
    }

    // Decode chat payload inline.
    if (frame.pktType == _kPktChat && frame.payload.isNotEmpty) {
      const int kFlagChannel = 0x08;
      const int kChanHdrLen = 2;
      int channelId = 0;
      String text;
      if ((frame.flags & kFlagChannel) != 0 &&
          frame.payload.length >= kChanHdrLen) {
        channelId = frame.payload[0] | (frame.payload[1] << 8);
        text = utf8.decode(frame.payload.sublist(kChanHdrLen),
            allowMalformed: true);
      } else {
        text = utf8.decode(frame.payload, allowMalformed: true);
      }
      return '$base ch=$channelId "${text.trim()}"';
    }

    return '$base hex=$hex';
  }

  /// Parse a received BLE notification (one complete binary frame) into a
  /// [RivrEvent], or return null if invalid / unrecognised.
  static RivrEvent? parseFrame(Uint8List bytes) {
    final frame = RivrFrame.decode(bytes);
    if (frame == null) return null;

    if (frame.isChat) {
      // PKT_CHAT payload with optional channel prefix (PKT_FLAG_CHANNEL = 0x08).
      //
      // When PKT_FLAG_CHANNEL is set:
      //   payload[0..1]  channel_id  u16 LE
      //   payload[2..]   utf-8 text
      //
      // When not set (legacy v1 behaviour):
      //   payload[0..]   utf-8 text → channel_id = 0 (Global)
      const int kFlagChannel = 0x08;
      const int kChanHdrLen  = 2;

      int channelId;
      String text;

      if ((frame.flags & kFlagChannel) != 0 && frame.payload.length >= kChanHdrLen) {
        channelId = frame.payload[0] | (frame.payload[1] << 8);
        final textBytes = frame.payload.sublist(kChanHdrLen);
        if (textBytes.isEmpty) return null;
        text = utf8.decode(textBytes, allowMalformed: true).trim();
      } else {
        channelId = 0; // Global — legacy frame
        if (frame.payload.isEmpty) return null;
        text = utf8.decode(frame.payload, allowMalformed: true).trim();
      }

      if (text.isEmpty) return null;
      final srcHex =
          '0x${frame.srcId.toRadixString(16).toUpperCase().padLeft(8, '0')}';
      return ChatEvent(ChatMessage(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        text: text,
        senderNodeId: frame.srcId,
        senderName: srcHex,
        timestamp: DateTime.now(),
        origin: MessageOrigin.remote,
        channelId: channelId,
      ));
    }

    // PKT_BEACON: advertises node presence — extract src_id and emit a NodeEvent.
    // Payload layout (protocol.h BEACON_PAYLOAD_LEN = 12):
    //   [0..9]  callsign (ASCII, NUL-padded, max 10 chars)
    //   [10]    hop_count (0 at origin)
    //   [11]    role (1=client, 2=repeater, 3=gateway)
    //   [12..19] optional lat/lon when PKT_FLAG_HAS_POS (0x10) is set
    if (frame.isBeacon) {
      const int kFlagHasPos = 0x10;
      String beaconCallsign = '';
      int beaconRole = 0;
      if (frame.payload.length >= 12) {
        // Extract NUL-terminated callsign from bytes 0..9
        final csBytes = frame.payload.sublist(0, 10);
        final nullIdx = csBytes.indexOf(0);
        final csEnd = nullIdx >= 0 ? nullIdx : 10;
        beaconCallsign = String.fromCharCodes(csBytes.sublist(0, csEnd)).trim();
        beaconRole = frame.payload[11];
      }
      double? beaconLat, beaconLon;
      if ((frame.flags & kFlagHasPos) != 0 && frame.payload.length >= 20) {
        final bpd = ByteData.sublistView(frame.payload);
        final latE7 = bpd.getInt32(12, Endian.little);
        final lonE7 = bpd.getInt32(16, Endian.little);
        if (latE7 != -2147483648 && lonE7 != -2147483648) {
          beaconLat = latE7 / 1e7;
          beaconLon = lonE7 / 1e7;
        }
      }
      final node = RivrNode(
        nodeId: frame.srcId,
        callsign: beaconCallsign,
        rssiDbm: -120,
        snrDb: 0,
        hopCount: frame.hopCount + 1,
        linkScore: 0,
        lossPercent: 0,
        role: beaconRole,
        lastSeen: DateTime.now(),
        lat: beaconLat,
        lon: beaconLon,
      );
      return NodeEvent(node);
    }

    // PKT_METRICS: BLE binary metrics snapshot (firmware pushes every 5 s)
    if (frame.isMetrics) {
      // Backward-compatible parser:
      // legacy payload: 48 bytes
      // full payload:   132 bytes
      if (frame.payload.length < _kLegacyBleMetricsLen) return null;
      final pd = ByteData.sublistView(frame.payload);
      if (frame.payload.length >= _kFullBleMetricsLen) {
        return MetricsEvent(RivrMetrics(
          nodeId: pd.getUint32(0, Endian.little),
          dcPct: frame.payload[4],
          qDepth: frame.payload[5],
          txTotal: pd.getUint32(6, Endian.little),
          rxTotal: pd.getUint32(10, Endian.little),
          routeCache: frame.payload[14],
          lnkCnt: frame.payload[15],
          lnkBest: frame.payload[16],
          lnkRssi: pd.getInt8(17),
          lnkLoss: frame.payload[18],
          relaySkip: pd.getUint32(19, Endian.little),
          relayDelay: pd.getUint32(23, Endian.little),
          relayDensity: frame.payload[27],
          relayFwd: pd.getUint32(28, Endian.little),
          relaySel: pd.getUint32(32, Endian.little),
          relayCan: pd.getUint32(36, Endian.little),
          rxDecodeFail: pd.getUint32(40, Endian.little),
          rxDedupeDrop: pd.getUint32(44, Endian.little),
          rxTtlDrop: pd.getUint32(48, Endian.little),
          rxBadType: pd.getUint32(52, Endian.little),
          rxBadHop: pd.getUint32(56, Endian.little),
          txQueueFull: pd.getUint32(60, Endian.little),
          dutyBlocked: pd.getUint32(64, Endian.little),
          noRoute: pd.getUint32(68, Endian.little),
          loopDetectDrop: pd.getUint32(72, Endian.little),
          radioHardReset: pd.getUint32(76, Endian.little),
          radioTxFail: pd.getUint32(80, Endian.little),
          radioCrcFail: pd.getUint32(84, Endian.little),
          routeCacheHit: pd.getUint32(88, Endian.little),
          routeCacheMiss: pd.getUint32(92, Endian.little),
          ackTx: pd.getUint32(96, Endian.little),
          ackRx: pd.getUint32(100, Endian.little),
          retryAttempt: pd.getUint32(104, Endian.little),
          retrySuccess: pd.getUint32(108, Endian.little),
          retryFail: pd.getUint32(112, Endian.little),
          bleConn: pd.getUint32(116, Endian.little),
          bleRx: pd.getUint32(120, Endian.little),
          bleTx: pd.getUint32(124, Endian.little),
          bleErr: pd.getUint32(128, Endian.little),
          collectedAt: DateTime.now(),
        ));
      }

      return MetricsEvent(RivrMetrics(
        nodeId: pd.getUint32(0, Endian.little),
        dcPct: frame.payload[4],
        qDepth: frame.payload[5],
        txTotal: pd.getUint32(6, Endian.little),
        rxTotal: pd.getUint32(10, Endian.little),
        routeCache: frame.payload[14],
        lnkCnt: frame.payload[15],
        lnkBest: frame.payload[16],
        lnkRssi: pd.getInt8(17),
        lnkLoss: frame.payload[18],
        relayDensity: frame.payload[19],
        relaySkip: pd.getUint32(20, Endian.little),
        rxDecodeFail: pd.getUint32(24, Endian.little),
        rxDedupeDrop: pd.getUint32(28, Endian.little),
        bleConn: pd.getUint32(32, Endian.little),
        bleRx: pd.getUint32(36, Endian.little),
        bleTx: pd.getUint32(40, Endian.little),
        bleErr: pd.getUint32(44, Endian.little),
        // fields not in the compact BLE payload—excluded to save space:
        relayDelay: 0, relayFwd: 0, relaySel: 0, relayCan: 0,
        rxTtlDrop: 0, rxBadType: 0, rxBadHop: 0,
        txQueueFull: 0, dutyBlocked: 0, noRoute: 0, loopDetectDrop: 0,
        radioHardReset: 0, radioTxFail: 0, radioCrcFail: 0,
        routeCacheHit: 0, routeCacheMiss: 0,
        ackTx: 0, ackRx: 0, retryAttempt: 0, retrySuccess: 0, retryFail: 0,
        collectedAt: DateTime.now(),
      ));
    }

    // Return as raw for other types (telemetry, routing, alert, etc.)
    return RawLineEvent(
        'BLE_FRAME:type=${frame.pktType},src=0x${frame.srcId.toRadixString(16).toUpperCase()}');
  }

  /// Build a PKT_CHAT frame for sending via BLE.
  ///
  /// [srcId] must be the phone's persistent virtual node ID.
  /// [seq] is the per-origin incrementing sequence counter.
  /// [channelId] when > 0 sets PKT_FLAG_CHANNEL and prepends the 2-byte
  /// channel_id LE header to the payload.
  static Uint8List buildChatFrame({
    required int srcId,
    required int seq,
    required String text,
    int dstId = _kBroadcast,
    int channelId = 0,
  }) {
    final textBytes = utf8.encode(text);
    final Uint8List payload;
    final int flags;

    if (channelId > 0) {
      // PKT_FLAG_CHANNEL = 0x08: prepend u16 LE channel_id
      payload = Uint8List(2 + textBytes.length)
        ..[0] = channelId & 0xFF
        ..[1] = (channelId >> 8) & 0xFF;
      payload.setRange(2, payload.length, textBytes);
      flags = 0x08;
    } else {
      payload = Uint8List.fromList(textBytes);
      flags = 0;
    }

    return RivrFrame(
      magic: _kMagic,
      version: _kVersion,
      pktType: _kPktChat,
      flags: flags,
      ttl: _kTtlDefault,
      srcId: srcId,
      dstId: dstId,
      netId: 0,
      hopCount: 0,
      seq: seq & 0xFFFF,
      pktId: seq & 0xFFFF,
      payload: payload,
    ).encode();
  }

  /// Generate a random 32-bit node ID for the phone (call once, then persist).
  static int generateNodeId() => Random.secure().nextInt(0xFFFFFFFF - 1) + 1;
}

class RivrCompanionCodec {
  static bool isCompanionPacket(Uint8List bytes) {
    if (bytes.length < _kCompanionHdrLen) return false;
    final bd = ByteData.sublistView(bytes);
    return bd.getUint16(0, Endian.little) == _kCompanionMagic;
  }

  static Uint8List _buildPacket(int type, [Uint8List? payload]) {
    final body = payload ?? Uint8List(0);
    final bytes = Uint8List(_kCompanionHdrLen + body.length);
    final bd = ByteData.sublistView(bytes);
    bd.setUint16(0, _kCompanionMagic, Endian.little);
    bytes[2] = _kCompanionVersion;
    bytes[3] = type & 0xFF;
    bytes[4] = 0;
    if (body.isNotEmpty) {
      bytes.setRange(_kCompanionHdrLen, bytes.length, body);
    }
    return bytes;
  }

  static Uint8List buildAppStart() => _buildPacket(_kCpCmdAppStart);
  static Uint8List buildDeviceQuery() => _buildPacket(_kCpCmdDeviceQuery);

  /// Build a BLE companion SET_POSITION command (lat/lon in degrees).
  static Uint8List buildSetPositionBle(double lat, double lon) {
    final latE7 = (lat * 1e7).round();
    final lonE7 = (lon * 1e7).round();
    final body = ByteData(8);
    body.setInt32(0, latE7, Endian.little);
    body.setInt32(4, lonE7, Endian.little);
    return _buildPacket(_kCpCmdSetPosition, body.buffer.asUint8List());
  }

  /// Build a BLE companion CLEAR_POSITION command.
  static Uint8List buildClearPositionBle() =>
      _buildPacket(_kCpCmdClearPosition);
  static Uint8List buildSetCallsign(String callsign) => _buildPacket(
      _kCpCmdSetCallsign, Uint8List.fromList(utf8.encode(callsign)));
  static Uint8List buildGetNeighbors() => _buildPacket(_kCpCmdGetNeighbors);

  static String describePacket(Uint8List bytes, {required String direction}) {
    if (!isCompanionPacket(bytes)) {
      return '$direction BLE_CP invalid len=${bytes.length}';
    }
    final type = bytes[3];
    final status = bytes[4];
    return '$direction BLE_CP type=0x${type.toRadixString(16).padLeft(2, '0').toUpperCase()}'
        ' status=$status len=${bytes.length - _kCompanionHdrLen}';
  }

  static RivrEvent? parsePacket(Uint8List bytes) {
    if (!isCompanionPacket(bytes)) return null;
    if (bytes[2] != _kCompanionVersion) {
      return RawLineEvent('BLE_CP:unsupported_version:${bytes[2]}');
    }

    final type = bytes[3];
    final payload = bytes.sublist(_kCompanionHdrLen);
    final pd = ByteData.sublistView(payload);

    switch (type) {
      case _kCpPktOk:
        final cmd = payload.isNotEmpty ? payload[0] : 0;
        return RawLineEvent(
            'BLE_CP:ok:0x${cmd.toRadixString(16).padLeft(2, '0')}');

      case _kCpPktErr:
        final cmd = payload.isNotEmpty ? payload[0] : 0;
        final msg = payload.length > 1
            ? utf8.decode(payload.sublist(1), allowMalformed: true)
            : 'error';
        return RawLineEvent(
            'BLE_CP:err:0x${cmd.toRadixString(16).padLeft(2, '0')}:$msg');

      case _kCpPktDeviceInfo:
        final infoStr = utf8.decode(payload, allowMalformed: true);
        try {
          final m = jsonDecode(infoStr) as Map<String, dynamic>;
          final nodeIdStr = (m['node_id'] as String?)?.replaceFirst('0x', '') ?? '';
          final nodeId = int.tryParse(nodeIdStr, radix: 16) ?? 0;
          final callsign = (m['callsign'] as String?) ?? '';
          final lat = (m['lat'] as num?)?.toDouble();
          final lon = (m['lon'] as num?)?.toDouble();
          final role = RivrProtocol._parseRoleValue(m['role']);
          return DeviceInfoEvent(
            nodeId: nodeId,
            callsign: callsign,
            lat: lat,
            lon: lon,
            role: role,
          );
        } catch (_) {
          return RawLineEvent('BLE_CP:device:$infoStr');
        }

      case _kCpPktNodeInfo:
        if (payload.length < 22) return null;
        final callsignBytes =
            payload.sublist(10, 22).takeWhile((b) => b != 0).toList();
        double? cpLat, cpLon;
        if (payload.length >= 30) {
          final latE7 = pd.getInt32(22, Endian.little);
          final lonE7 = pd.getInt32(26, Endian.little);
          if (latE7 != -2147483648 && lonE7 != -2147483648) {
            cpLat = latE7 / 1e7;
            cpLon = lonE7 / 1e7;
          }
        }
        return NodeEvent(RivrNode(
          nodeId: pd.getUint32(0, Endian.little),
          callsign: utf8.decode(callsignBytes, allowMalformed: true),
          rssiDbm: pd.getInt8(4),
          snrDb: pd.getInt8(5),
          hopCount: payload[6] + 1, // firmware sends raw pkt_hdr.hop (0=direct); convert to 1-based
          linkScore: payload[7],
          role: payload[8],
          lossPercent: 0,
          lastSeen: DateTime.now(),
          lat: cpLat,
          lon: cpLon,
        ));

      case _kCpPktNodeListDone:
        return RawLineEvent('BLE_CP:nodes:done');

      case _kCpPktChatRx:
        // Payload layout (updated firmware):
        //   [0-3]  src_id      u32 LE
        //   [4-5]  channel_id  u16 LE  (0 = Global / legacy build)
        //   [6+]   text        UTF-8
        // Legacy firmware omits bytes [4-5]; guard with length check.
        if (payload.length < 5) return null;
        final srcId = pd.getUint32(0, Endian.little);
        int chatChanId = 0;
        int textOffset = 4;
        if (payload.length >= 7) {
          chatChanId = payload[4] | (payload[5] << 8);
          textOffset = 6;
        }
        final text =
            utf8.decode(payload.sublist(textOffset), allowMalformed: true).trim();
        if (text.isEmpty) return null;
        final srcHex =
            '0x${srcId.toRadixString(16).toUpperCase().padLeft(8, '0')}';
        return ChatEvent(ChatMessage(
          id: '${DateTime.now().microsecondsSinceEpoch}',
          text: text,
          senderNodeId: srcId,
          senderName: srcHex,
          timestamp: DateTime.now(),
          origin: MessageOrigin.remote,
          channelId: chatChanId,
        ));
      case _kCpPktTelemetry:
        // Payload layout:
        //   [0-3]   src_id    u32 LE
        //   [4-5]   sensor_id u16 LE
        //   [6-9]   value     i32 LE
        //   [10]    unit_code u8
        //   [11-14] timestamp u32 LE
        if (payload.length < 15) return null;
        final telSrcId = pd.getUint32(0, Endian.little);
        final telSensorId = pd.getUint16(4, Endian.little);
        final telValue = pd.getInt32(6, Endian.little);
        final telUnitCode = payload[10];
        final telTimestamp = pd.getUint32(11, Endian.little);
        return TelemetryEvent(TelemetryReading(
          srcNodeId: telSrcId,
          sensorId: telSensorId,
          valueX100: telValue,
          unitCode: telUnitCode,
          timestampS: telTimestamp,
          receivedAt: DateTime.now(),
        ));
    }

    return RawLineEvent(
        'BLE_CP:type=0x${type.toRadixString(16).padLeft(2, '0').toUpperCase()}');
  }
}

/// Parses raw text lines from the Rivr firmware serial output and emits typed
/// [RivrEvent] objects.
///
/// The parser is stateless — call [parseLine] for each line received.
class RivrProtocol {
  // ── `id` command response state machine ───────────────────────────────────
  // The `id` CLI command prints up to 4 lines:
  //   Node ID  : 0xXXXXXXXX
  //   Callsign : ALICE
  //   Net ID   : 0xXXXX
  //   Position : lat, lon     (only when a position is stored)
  //
  // We buffer across calls because parseLine is called once per line.
  static int? _idNodeId;
  static String? _idCallsign;
  static bool _idNetIdSeen = false;
  static int _idLastEmittedNodeId = 0;
  static String _idLastEmittedCallsign = '';
  static double? _idLastEmittedLat;
  static double? _idLastEmittedLon;
  static int _idLastEmittedRole = 0;

  static final _idNodeIdPattern =
      RegExp(r'Node ID\s*:\s*(0x[0-9A-Fa-f]+)', caseSensitive: false);
  static final _idCallsignPattern =
      RegExp(r'Callsign\s*:\s*(\S*)', caseSensitive: false);
  static final _idNetIdPattern =
      RegExp(r'Net ID\s*:', caseSensitive: false);
  static final _idPositionPattern =
      RegExp(r'Position\s*:\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)', caseSensitive: false);
  static final _buildInfoRolePattern = RegExp(
      r'\[RIVR\].*\brole=(client|repeater|gateway)\b',
      caseSensitive: false);

  /// Reset the `id`-response accumulator (call on disconnect).
  static void resetIdState() {
    _idNodeId = null;
    _idCallsign = null;
    _idNetIdSeen = false;
    _idLastEmittedNodeId = 0;
    _idLastEmittedCallsign = '';
    _idLastEmittedLat = null;
    _idLastEmittedLon = null;
    _idLastEmittedRole = 0;
  }

  // ── BEACON pos log line ─────────────────────────────────────────────────────
  // Example:  I (1234) rivr_src: BEACON pos src=0xDEADBEEF lat=525134400 lon=47652300
  static final _beaconPosPattern = RegExp(
      r'BEACON pos src=(0x[0-9A-Fa-f]+)\s+lat=(-?\d+)\s+lon=(-?\d+)',
      caseSensitive: false);

  // ── @MET JSON ──────────────────────────────────────────────────────────────
  // Example:  @MET {"node":3735928559,"dc":12,"qdep":0,...}
  static final _metPattern = RegExp(r'^@MET\s+(\{.+\})\s*$');

  // ── @TEL JSON ──────────────────────────────────────────────────────────────
  // Example:  @TEL {"src":"0xAABBCCDD","sid":2,"val":4120,"unit":2,"unit_str":"%RH*100","ts":951}
  static final _telPattern = RegExp(r'^@TEL\s+(\{.+\})\s*$');

  // ── @CHT JSON (primary – always emitted by firmware) ───────────────────────
  // Example:  @CHT {"src":"0xDEADBEEF","dst":"0xFFFFFFFF","rssi":-87,"len":5,"text":"hello"}
  static final _chtPattern = RegExp(r'^@CHT\s+(\{.+\})\s*$');

  // ── @BCN JSON — emitted on every received beacon ─────────────────────────
  // Example: @BCN {"src":"0x1A2B3C4D","cs":"ALICE","rssi":-87,"snr":8,
  //               "hop":1,"score":95,"role":1,"lat":52.3702,"lon":4.8952}
  static final _bcnPattern = RegExp(r'^@BCN\s+(\{.+\})\s*$');

  // ── RIVR_SRC BEACON log line — always emitted on every firmware build ────
  // Format varies by platform (all share the same suffix after the tag):
  //   ESP32 : I (1932) RIVR_SRC: BEACON src=0xa50a9a0c cs='NL9MVV' role=1 rssi=-12 dBm
  //   RP2040: [I][RIVR_SRC] BEACON src=0xa50a9a0c cs='NL9MVV' role=1 rssi=-12 dBm
  //   Linux : [I][ms][RIVR_SRC] BEACON src=... cs='...' role=N rssi=N dBm
  // Match on the payload portion only; the cs='' field is unique to this line.
  static final _rivrSrcBeaconPattern = RegExp(
      "BEACON\\s+src=(0x[0-9A-Fa-f]+)\\s+cs='([^']*)'\\s+role=(\\d+)\\s+rssi=(-?\\d+)",
      caseSensitive: false);

  // ── [CHAT][NODEID]: text  (human-readable fallback, client build) ─────────
  // Example:  [CHAT][DEADBEEF]: hello world
  // ── ntable output from neighbor_table_print ─────────────────────────────
  // Format: 0x%08lX %5d %4d %5u %5u %6u %9u %6lu %6lu  %s
  // Cols:   nodeId  rssi snr loss etx flen score  age rx_ok flags
  // (No callsign column — callsign comes from @BCN lines.)
  static final _ntableRowPattern = RegExp(
      r'(0x[0-9A-Fa-f]{8})\s+(-?\d+)\s+(-?\d+)\s+\d+\s+\d+\s+\d+\s+(\d+)',
      caseSensitive: false);

  /// Parse one line of firmware output and return an event, or null if the
  /// line carries no structured information of interest.
  static RivrEvent? parseLine(String line) {
    line = line.trim();
    if (line.isEmpty) return null;

    // ── `id` response accumulator ──────────────────────────────────────────
    // Firmware prints (in order):
    //   Node ID  : 0xXXXX
    //   Callsign : ALICE
    //   Net ID   : 0xXXXX        ← last guaranteed line
    //   Position : lat, lon      ← optional; only when position is stored
    //
    // On the Net ID line we emit a DeviceInfoEvent and set _idNetIdSeen=true.
    // If the very next line is a Position line we emit a second, richer event
    // that supersedes the first (consumers always take the latest value).

    // Build info may arrive before or after `id`; keep the most recent role
    // cached and emit a richer self-node update once the node ID is known.
    final buildInfoMatch = _buildInfoRolePattern.firstMatch(line);
    if (buildInfoMatch != null) {
      final role = _parseRoleValue(buildInfoMatch.group(1));
      _idLastEmittedRole = role;
      if (_idLastEmittedNodeId != 0) {
        return DeviceInfoEvent(
          nodeId: _idLastEmittedNodeId,
          callsign: _idLastEmittedCallsign,
          lat: _idLastEmittedLat,
          lon: _idLastEmittedLon,
          role: role,
        );
      }
      return null;
    }

    // Phase A: if we just emitted on Net ID, check if current line is Position.
    if (_idNetIdSeen) {
      _idNetIdSeen = false;
      final posMatch = _idPositionPattern.firstMatch(line);
      if (posMatch != null && _idLastEmittedNodeId != 0) {
        final lat = double.tryParse(posMatch.group(1)!);
        final lon = double.tryParse(posMatch.group(2)!);
        _idLastEmittedLat = lat;
        _idLastEmittedLon = lon;
        return DeviceInfoEvent(
            nodeId: _idLastEmittedNodeId,
            callsign: _idLastEmittedCallsign,
            lat: lat,
            lon: lon,
            role: _idLastEmittedRole);
      }
      // Not a Position line — fall through to normal parsing.
    }

    // Phase B: accumulate Node ID / Callsign / Net ID.
    final nodeIdMatch = _idNodeIdPattern.firstMatch(line);
    if (nodeIdMatch != null) {
      _idNodeId = _parseHex(nodeIdMatch.group(1)!);
      _idCallsign = null;
      return null;
    }
    if (_idNodeId != null) {
      final csMatch = _idCallsignPattern.firstMatch(line);
      if (csMatch != null) {
        _idCallsign = csMatch.group(1) ?? '';
        return null;
      }
      final netMatch = _idNetIdPattern.firstMatch(line);
      if (netMatch != null && _idCallsign != null) {
        final nodeId = _idNodeId!;
        final callsign = _idCallsign!;
        _idNodeId = null;
        _idCallsign = null;
        _idNetIdSeen = true;
        _idLastEmittedNodeId = nodeId;
        _idLastEmittedCallsign = callsign;
        return DeviceInfoEvent(
          nodeId: nodeId,
          callsign: callsign,
          role: _idLastEmittedRole,
        );
      }
    }

    // @MET JSON
    final metMatch = _metPattern.firstMatch(line);
    if (metMatch != null) {
      final metrics = _parseMetrics(metMatch.group(1)!);
      if (metrics != null) return MetricsEvent(metrics);
    }

    // @TEL JSON
    final telMatch = _telPattern.firstMatch(line);
    if (telMatch != null) {
      final event = _parseTel(telMatch.group(1)!);
      if (event != null) return event;
    }

    // @CHT JSON (primary)
    final chtMatch = _chtPattern.firstMatch(line);
    if (chtMatch != null) {
      final event = _parseCht(chtMatch.group(1)!);
      if (event != null) return event;
    }

    // @BCN JSON → node update (USB serial equivalent of BLE push_node)
    final bcnMatch = _bcnPattern.firstMatch(line);
    if (bcnMatch != null) {
      final event = _parseBcn(bcnMatch.group(1)!);
      if (event != null) return event;
    }

    // RIVR_SRC: BEACON log line → node update (always present in firmware logs)
    final rivrBcnMatch = _rivrSrcBeaconPattern.firstMatch(line);
    if (rivrBcnMatch != null) {
      final nodeId = _parseHex(rivrBcnMatch.group(1)!) ?? 0;
      if (nodeId != 0) {
        final callsign = rivrBcnMatch.group(2) ?? '';
        final role = int.tryParse(rivrBcnMatch.group(3)!) ?? 0;
        final rssi = int.tryParse(rivrBcnMatch.group(4)!) ?? -120;
        return NodeEvent(RivrNode(
          nodeId: nodeId,
          callsign: callsign,
          rssiDbm: rssi,
          snrDb: 0,
          hopCount: 1,
          linkScore: 0,
          lossPercent: 0,
          role: role,
          lastSeen: DateTime.now(),
        ));
      }
    }

    // BEACON pos log line → position update for node
    final posMatch = _beaconPosPattern.firstMatch(line);
    if (posMatch != null) {
      final nodeId = _parseHex(posMatch.group(1)!) ?? 0;
      final latE7 = int.tryParse(posMatch.group(2)!) ?? -2147483648;
      final lonE7 = int.tryParse(posMatch.group(3)!) ?? -2147483648;
      if (latE7 != -2147483648 && lonE7 != -2147483648) {
        return NodeEvent(RivrNode(
          nodeId: nodeId,
          callsign: '',
          rssiDbm: -120,
          snrDb: 0,
          hopCount: 1,
          linkScore: 0,
          lossPercent: 0,
          lastSeen: DateTime.now(),
          lat: latE7 / 1e7,
          lon: lonE7 / 1e7,
        ));
      }
    }

    // ntable row → node update (no callsign available; hopCount defaults to 1)
    final nbMatch = _ntableRowPattern.firstMatch(line);
    if (nbMatch != null) {
      final nodeId = _parseHex(nbMatch.group(1)!) ?? 0;
      final rssi = int.tryParse(nbMatch.group(2)!) ?? -120;
      final snr = int.tryParse(nbMatch.group(3)!) ?? 0;
      final score = int.tryParse(nbMatch.group(4)!) ?? 0;
      final node = RivrNode(
        nodeId: nodeId,
        callsign: '',
        rssiDbm: rssi,
        snrDb: snr,
        hopCount: 1,
        linkScore: score,
        lossPercent: 0,
        lastSeen: DateTime.now(),
      );
      return NodeEvent(node);
    }

    return RawLineEvent(line);
  }

  /// Build the serial CLI command to set the node's own position.
  /// Returns a command string terminated with `\n`, ready to send over USB.
  static String buildSetPositionCommand(double lat, double lon) {
    return 'pos ${lat.toStringAsFixed(7)} ${lon.toStringAsFixed(7)}\n';
  }

  /// Build the serial CLI command to clear the stored position.
  static String buildClearPositionCommand() => 'pos clear\n';

  // ── @TEL JSON parser ─────────────────────────────────────────────────────
  static TelemetryEvent? _parseTel(String json) {
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      final srcStr  = m['src'] as String? ?? '0x0';
      final nodeId  = _parseHex(srcStr) ?? 0;
      final sensorId   = _i(m, 'sid');
      final valueX100  = _i(m, 'val');
      final unitCode   = _i(m, 'unit');
      final timestampS = _i(m, 'ts');
      if (sensorId == 0) return null;
      return TelemetryEvent(TelemetryReading(
        srcNodeId:   nodeId,
        sensorId:    sensorId,
        valueX100:   valueX100,
        unitCode:    unitCode,
        timestampS:  timestampS,
        receivedAt:  DateTime.now(),
      ));
    } catch (_) {
      return null;
    }
  }

  // ── @CHT JSON parser ─────────────────────────────────────────────────────
  static ChatEvent? _parseCht(String json) {
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      final srcStr = (m['src'] as String? ?? '0x0');
      final nodeId = _parseHex(srcStr) ?? 0;
      final text = (m['text'] as String? ?? '').trim();
      if (text.isEmpty) return null;
      // 'chan' field is emitted by updated firmware; absent in v1 legacy nodes → 0.
      final channelId = (m['chan'] as num?)?.toInt() ?? 0;
      final name =
          '0x${nodeId.toRadixString(16).toUpperCase().padLeft(8, '0')}';
      final msg = ChatMessage(
        id: '${DateTime.now().microsecondsSinceEpoch}',
        text: text,
        senderNodeId: nodeId,
        senderName: name,
        timestamp: DateTime.now(),
        origin: MessageOrigin.remote,
        channelId: channelId,
      );
      return ChatEvent(msg);
    } catch (_) {
      return null;
    }
  }

  // ── Hex parser: accepts '0xDEADBEEF' or 'DEADBEEF' ────────────────────────
  static int? _parseHex(String s) {
    final stripped =
        s.startsWith('0x') || s.startsWith('0X') ? s.substring(2) : s;
    return int.tryParse(stripped, radix: 16);
  }

  static int _parseRoleValue(Object? value) {
    if (value is num) {
      final role = value.toInt();
      return role >= 1 && role <= 3 ? role : 0;
    }
    final roleStr = value?.toString().trim().toLowerCase() ?? '';
    switch (roleStr) {
      case '1':
      case 'client':
        return 1;
      case '2':
      case 'repeater':
        return 2;
      case '3':
      case 'gateway':
        return 3;
      default:
        return 0;
    }
  }

  // ── @BCN JSON parser ──────────────────────────────────────────────────────
  static NodeEvent? _parseBcn(String json) {
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      final srcStr = m['src'] as String? ?? '0x0';
      final nodeId = _parseHex(srcStr) ?? 0;
      if (nodeId == 0) return null;
      final callsign = (m['cs'] as String? ?? '').trim();
      final rssi = _i(m, 'rssi');
      final snr = _i(m, 'snr');
      final hop = _i(m, 'hop');
      final score = _i(m, 'score');
      final role = _i(m, 'role');
      final lat = (m['lat'] as num?)?.toDouble();
      final lon = (m['lon'] as num?)?.toDouble();
      return NodeEvent(RivrNode(
        nodeId: nodeId,
        callsign: callsign,
        rssiDbm: rssi,
        snrDb: snr,
        hopCount: hop + 1,
        linkScore: score,
        lossPercent: 0,
        role: role,
        lastSeen: DateTime.now(),
        lat: lat,
        lon: lon,
      ));
    } catch (_) {
      return null;
    }
  }

  // ── Parse @MET fields ─────────────────────────────────────────────────────
  static RivrMetrics? _parseMetrics(String json) {
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return RivrMetrics(
        nodeId: _i(m, 'node_id'), // "node_id"
        dcPct: _i(m, 'dc_pct'), // "dc_pct"
        qDepth: _i(m, 'q_depth'), // "q_depth"
        txTotal: _i(m, 'tx_total'), // "tx_total"
        rxTotal: _i(m, 'rx_total'), // "rx_total"
        routeCache: _i(m, 'route_cache'), // "route_cache"
        lnkCnt: _i(m, 'lnk_cnt'), // "lnk_cnt"
        lnkBest: _i(m, 'lnk_best'), // "lnk_best"
        lnkRssi: _i(m, 'lnk_rssi'), // "lnk_rssi"
        lnkLoss: _i(m, 'lnk_loss'), // "lnk_loss"
        relaySkip: _i(m, 'relay_skip'), // "relay_skip"
        relayDelay: _i(m, 'relay_delay'), // "relay_delay"
        relayDensity: _i(m, 'relay_density'), // "relay_density"
        relayFwd: _i(m, 'relay_fwd'), // "relay_fwd"
        relaySel: _i(m, 'relay_sel'), // "relay_sel"
        relayCan: _i(m, 'relay_can'), // "relay_can"
        rxDecodeFail: _i(m, 'rx_fail'), // "rx_fail"
        rxDedupeDrop: _i(m, 'rx_dup'), // "rx_dup"
        rxTtlDrop: _i(m, 'rx_ttl'), // "rx_ttl"
        rxBadType: _i(m, 'rx_bad_type'), // "rx_bad_type"
        rxBadHop: _i(m, 'rx_bad_hop'), // "rx_bad_hop"
        txQueueFull: _i(m, 'tx_full'), // "tx_full"
        dutyBlocked: _i(m, 'dc_blk'), // "dc_blk"
        noRoute: _i(m, 'no_route'), // "no_route"
        loopDetectDrop: _i(m, 'loop_drop_total'), // "loop_drop_total"
        radioHardReset: _i(m, 'rad_rst'), // "rad_rst"
        radioTxFail: _i(m, 'rad_txfail'), // "rad_txfail"
        radioCrcFail: _i(m, 'rad_crc'), // "rad_crc"
        routeCacheHit: _i(m, 'rc_hit'), // "rc_hit"
        routeCacheMiss: _i(m, 'rc_miss'), // "rc_miss"
        ackTx: _i(m, 'ack_tx'), // "ack_tx"
        ackRx: _i(m, 'ack_rx'), // "ack_rx"
        retryAttempt: _i(m, 'retry_att'), // "retry_att"
        retrySuccess: _i(m, 'retry_ok'), // "retry_ok"
        retryFail: _i(m, 'retry_fail'), // "retry_fail"
        bleConn: _i(m, 'ble_conn'), // "ble_conn"
        bleRx: _i(m, 'ble_rx'), // "ble_rx"
        bleTx: _i(m, 'ble_tx'), // "ble_tx"
        bleErr: _i(m, 'ble_err'), // "ble_err"
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

  /// Build the serial command to send a chat message on a specific channel.
  ///
  /// When [channelId] > 0 the firmware is told to emit PKT_FLAG_CHANNEL with
  /// the given channel_id prefix in the payload.  Channel 0 (Global) sends
  /// a legacy PKT_CHAT for maximum backward compatibility.
  ///
  /// CLI wire format:
  ///   channel 0  → `chat <text>\n`           (legacy, no channel prefix)
  ///   channel N  → `chan <N> <text>\n`        (channel-aware, N = 1..65535)
  static String buildChatCommand(String text, {int channelId = 0}) {
    if (channelId == 0) return 'chat $text\n';
    return 'chan $channelId $text\n';
  }

  /// Firmware CLI command to persist the node callsign.
  static String buildSetCallsignCommand(String callsign) =>
      'set callsign $callsign\n';

  /// Firmware accepts 1-11 chars: A-Z a-z 0-9 dash.
  static bool isValidCallsign(String callsign) =>
      RegExp(r'^[A-Za-z0-9-]{1,11}$').hasMatch(callsign);

  /// Request the node table printout.
  static const String cmdNtable = 'ntable\n';

  /// Request a metrics snapshot.
  static const String cmdMetrics = 'metrics\n';

  /// Request the forward-candidate set status.
  static const String cmdFwdset = 'fwdset\n';

  /// Request a routing stats snapshot.
  static const String cmdRtstats = 'rtstats\n';
}
