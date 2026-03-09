import 'package:equatable/equatable.dart';

/// Parsed snapshot of a single @MET JSON line emitted by the Rivr firmware.
class RivrMetrics extends Equatable {
  // --- Identity ---
  final int nodeId;

  // --- Radio health ---
  final int dcPct;         // duty-cycle used %              "dc_pct"
  final int qDepth;        // TX queue depth                  "q_depth"
  final int txTotal;       // lifetime TX frames              "tx_total"
  final int rxTotal;       // lifetime RX frames              "rx_total"
  final int routeCache;    // live route-cache entries        "route_cache"

  // --- Link quality ---
  final int lnkCnt;        // live neighbor count             "lnk_cnt"
  final int lnkBest;       // best link score 0-100           "lnk_best"
  final int lnkRssi;       // EWMA RSSI of best neighbor (dBm)"lnk_rssi"
  final int lnkLoss;       // avg loss % across neighbors     "lnk_loss"

  // --- Relay ---
  final int relaySkip;     // phase-4+5 suppressed relays     "relay_skip"
  final int relayDelay;    // lifetime extra holdoff (ms)      "relay_delay"
  final int relayDensity;  // viable neighbor count            "relay_density"
  final int relayFwd;      // relay frames that completed TX  "relay_fwd"
  final int relaySel;      // relay candidates selected        "relay_sel"
  final int relayCan;      // relay frames cancelled (phase-4)"relay_can"

  // --- RX drop counters ---
  final int rxDecodeFail;  // decode failures                 "rx_fail"
  final int rxDedupeDrop;  // duplicate suppression           "rx_dup"
  final int rxTtlDrop;     // TTL-exhausted drops             "rx_ttl"
  final int rxBadType;     // unknown frame type              "rx_bad_type"
  final int rxBadHop;      // invalid hop count               "rx_bad_hop"

  // --- TX / routing drop counters ---
  final int txQueueFull;   // TX queue full drops             "tx_full"
  final int dutyBlocked;   // duty-cycle blocked              "dc_blk"
  final int noRoute;       // no-route drops                  "no_route"
  final int loopDetectDrop;// loop-detect cumulative drops    "loop_drop_total"

  // --- Radio hardware counters ---
  final int radioHardReset;// hard resets                     "rad_rst"
  final int radioTxFail;   // radio TX failures               "rad_txfail"
  final int radioCrcFail;  // radio CRC errors                "rad_crc"

  // --- Route-cache efficiency ---
  final int routeCacheHit; // cache hits                      "rc_hit"
  final int routeCacheMiss;// cache misses                    "rc_miss"

  // --- ACK / retry ---
  final int ackTx;         // ACKs transmitted                "ack_tx"
  final int ackRx;         // ACKs received                   "ack_rx"
  final int retryAttempt;  // retry attempts                  "retry_att"
  final int retrySuccess;  // successful retries              "retry_ok"
  final int retryFail;     // failed retries                  "retry_fail"

  final DateTime collectedAt;

  const RivrMetrics({
    required this.nodeId,
    required this.dcPct,
    required this.qDepth,
    required this.txTotal,
    required this.rxTotal,
    required this.routeCache,
    required this.lnkCnt,
    required this.lnkBest,
    required this.lnkRssi,
    required this.lnkLoss,
    required this.relaySkip,
    required this.relayDelay,
    required this.relayDensity,
    required this.relayFwd,
    required this.relaySel,
    required this.relayCan,
    required this.rxDecodeFail,
    required this.rxDedupeDrop,
    required this.rxTtlDrop,
    required this.rxBadType,
    required this.rxBadHop,
    required this.txQueueFull,
    required this.dutyBlocked,
    required this.noRoute,
    required this.loopDetectDrop,
    required this.radioHardReset,
    required this.radioTxFail,
    required this.radioCrcFail,
    required this.routeCacheHit,
    required this.routeCacheMiss,
    required this.ackTx,
    required this.ackRx,
    required this.retryAttempt,
    required this.retrySuccess,
    required this.retryFail,
    required this.collectedAt,
  });

  factory RivrMetrics.empty() => RivrMetrics(
    nodeId: 0, dcPct: 0, qDepth: 0, txTotal: 0, rxTotal: 0,
    routeCache: 0, lnkCnt: 0, lnkBest: 0, lnkRssi: -120, lnkLoss: 0,
    relaySkip: 0, relayDelay: 0, relayDensity: 0,
    relayFwd: 0, relaySel: 0, relayCan: 0,
    rxDecodeFail: 0, rxDedupeDrop: 0, rxTtlDrop: 0, rxBadType: 0, rxBadHop: 0,
    txQueueFull: 0, dutyBlocked: 0, noRoute: 0, loopDetectDrop: 0,
    radioHardReset: 0, radioTxFail: 0, radioCrcFail: 0,
    routeCacheHit: 0, routeCacheMiss: 0,
    ackTx: 0, ackRx: 0, retryAttempt: 0, retrySuccess: 0, retryFail: 0,
    collectedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  @override
  List<Object?> get props => [nodeId, dcPct, txTotal, rxTotal, collectedAt];
}
