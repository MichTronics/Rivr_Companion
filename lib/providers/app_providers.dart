import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/connection_manager.dart';
import '../services/app_database.dart';
import '../services/telemetry_forward_service.dart';
import '../services/foreground_service.dart';
import '../protocol/rivr_protocol.dart';
import '../models/chat_message.dart';
import '../models/rivr_node.dart';
import '../models/metrics.dart';
import '../models/telemetry_reading.dart';
import '../providers/settings_provider.dart';

// ── App database ──────────────────────────────────────────────────────────

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

// ── Singleton connection manager ───────────────────────────────────────────

final connectionManagerProvider = Provider<ConnectionManager>((ref) {
  final manager = ConnectionManager();
  ref.onDispose(manager.dispose);
  return manager;
});

// ── Reactive connection state ─────────────────────────────────────────────

final connectionStateProvider = StreamProvider<RivrConnState>((ref) {
  return ref.watch(connectionManagerProvider).stateStream;
});

// ── Event dispatcher — feeds all downstream providers ────────────────────

/// Central event stream.  All model providers listen to this.
final eventStreamProvider = StreamProvider<RivrEvent>((ref) {
  return ref.watch(connectionManagerProvider).eventStream;
});

// ── Chat messages ──────────────────────────────────────────────────────────

class ChatNotifier extends Notifier<List<ChatMessage>> {
  static const _maxMessages = 1000;

  /// Pending local sends keyed by text, used to suppress a single immediate TX
  /// echo when the radio's node-ID is not yet known from @MET.
  final _pendingEchoes = <String, ({DateTime sentAt, int remaining})>{};
  static const _echoWindow = Duration(seconds: 3);

  AppDatabase get _db => ref.read(appDatabaseProvider);

  @override
  List<ChatMessage> build() {
    // Seed state from persisted messages asynchronously so we don't block
    // the synchronous build(). Events that arrive during the load are
    // appended to state normally; the DB seed will re-sort and de-dup.
    Future.microtask(() async {
      final stored = await _db.getAllMessages();
      if (stored.isEmpty) return;
      // Merge: keep any messages already added via events, de-dup by id.
      final existing = {for (final m in state) m.id: m};
      for (final m in stored) {
        existing.putIfAbsent(m.id, () => m);
      }
      final merged = existing.values.toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      state = merged.length > _maxMessages
          ? merged.sublist(merged.length - _maxMessages)
          : merged;
    });

    ref.listen(eventStreamProvider, (_, next) {
      next.whenData((event) {
        if (event is ChatEvent) {
          final msg = event.message;

          // Drop @CHT lines where src == our own node ID (TX echo from radio).
          // The node ID comes from @MET; if it is not yet available we fall
          // through to the text-based dedup below.
          final localNodeId = ref.read(metricsProvider.notifier).latest.nodeId;
          if (localNodeId != 0 && msg.senderNodeId == localNodeId) return;

          // Also suppress echoes where src == the phone's own BLE node-ID.
          // This handles BLE where the node may relay our own frame back.
          final phoneNodeId = ref.read(settingsProvider).phoneNodeId;
          if (phoneNodeId != 0 && msg.senderNodeId == phoneNodeId) return;

          // Fallback: suppress only one near-immediate text match per local send.
          final pending = _pendingEchoes[msg.text];
          if (pending != null) {
            if (DateTime.now().difference(pending.sentAt) < _echoWindow) {
              final remaining = pending.remaining - 1;
              if (remaining > 0) {
                _pendingEchoes[msg.text] = (
                  sentAt: pending.sentAt,
                  remaining: remaining,
                );
              } else {
                _pendingEchoes.remove(msg.text);
              }
              return;
            }
            _pendingEchoes.remove(msg.text);
          }

          // Enrich sender name with callsign from node table if available
          final nodes = ref.read(nodesProvider);
          final node = nodes[msg.senderNodeId];
          final enriched = (node != null && node.callsign.isNotEmpty)
              ? ChatMessage(
                  id: msg.id,
                  text: msg.text,
                  senderNodeId: msg.senderNodeId,
                  senderName: '${node.callsign} (${msg.senderName})',
                  timestamp: msg.timestamp,
                  origin: msg.origin,
                )
              : msg;
          _add(enriched);
        }
      });
    });
    return [];
  }

  void _add(ChatMessage msg) {
    final next = [...state, msg];
    state = next.length > _maxMessages
        ? next.sublist(next.length - _maxMessages)
        : next;
    // Persist asynchronously — fire and forget.
    _db.insertMessage(msg);
  }

  void addSystem(String text) => _add(ChatMessage.system(text));

  void addLocal(ChatMessage msg) {
    // Record the text so we can suppress a single immediate radio echo for the
    // same message (used when node-ID from @MET is not yet known).
    final existing = _pendingEchoes[msg.text];
    _pendingEchoes[msg.text] = (
      sentAt: DateTime.now(),
      remaining: (existing?.remaining ?? 0) + 1,
    );
    _add(msg);
  }
}

final chatProvider =
    NotifierProvider<ChatNotifier, List<ChatMessage>>(ChatNotifier.new);

// ── Nodes ──────────────────────────────────────────────────────────────────

class NodesNotifier extends Notifier<Map<int, RivrNode>> {
  AppDatabase get _db => ref.read(appDatabaseProvider);

  @override
  Map<int, RivrNode> build() {
    // Seed from DB on startup.
    Future.microtask(() async {
      final stored = await _db.getAllNodes();
      if (stored.isEmpty) return;
      // Don't overwrite state if events already populated it.
      final existing = Map<int, RivrNode>.from(state);
      for (final n in stored) {
        existing.putIfAbsent(n.nodeId, () => n);
      }
      state = existing;
    });

    ref.listen(eventStreamProvider, (_, next) {
      next.whenData((event) {
        if (event is NodeEvent) {
          final incoming = event.node;
          final existing = state[incoming.nodeId];
          // Never let a NodeEvent (from @BCN / ntable / log lines) overwrite
          // the self-node established by DeviceInfoEvent or MetricsEvent.
          // Guard on the actual connected node ID, not on hopCount==0, to
          // avoid locking out neighbour nodes that were accidentally placed
          // at hopCount==0 by the BEACON pos log parser.
          final selfId = ref.read(connectedNodeIdProvider);
          if (selfId != 0 && incoming.nodeId == selfId) return;
          // Preserve known callsign/position when the incoming event lacks them
          // (ntable rows carry no callsign; @BCN position may lag ntable).
          final callsign = incoming.callsign.isNotEmpty
              ? incoming.callsign
              : (existing?.callsign ?? '');
          final lat = incoming.lat ?? existing?.lat;
          final lon = incoming.lon ?? existing?.lon;
          final merged = incoming.copyWith(
            callsign: callsign,
            lat: lat,
            lon: lon,
          );
          _setNode(merged);
        } else if (event is DeviceInfoEvent && event.nodeId != 0) {
          // Always keep the connected node in the map (hopCount=0) so the
          // mesh ring shows the correct callsign even without a position.
          final existing = state[event.nodeId];
          final callsign = event.callsign.isNotEmpty
              ? event.callsign
              : (existing?.callsign ?? '');
          final self = RivrNode(
            nodeId: event.nodeId,
            callsign: callsign,
            rssiDbm: existing?.rssiDbm ?? 0,
            snrDb: existing?.snrDb ?? 0,
            hopCount: 0,
            linkScore: existing?.linkScore ?? 100,
            lossPercent: existing?.lossPercent ?? 0,
            lastSeen: DateTime.now(),
            role: existing?.role ?? 1,
            // Preserve existing position unless a new one is provided.
            lat: event.lat ?? (existing?.hopCount == 0 ? existing?.lat : null),
            lon: event.lon ?? (existing?.hopCount == 0 ? existing?.lon : null),
          );
          _setNode(self);
        } else if (event is MetricsEvent && event.metrics.nodeId != 0) {
          // MetricsEvent is broadcast periodically by the firmware on every
          // platform (USB serial and BLE).  Use it as a reliable fallback to
          // establish the self-node (hopCount=0) in case DeviceInfoEvent from
          // the `id\n` response hasn't arrived yet (e.g. first @MET fires
          // before the 300 ms USB delay elapses, or id\n was delayed).
          final nodeId = event.metrics.nodeId;
          final existing = state[nodeId];
          if (existing == null || existing.hopCount != 0) {
            // Prefer callsign already in map; fall back to the one stored in
            // settings (auto-synced from every DeviceInfoEvent / id response).
            final callsign = (existing?.callsign.isNotEmpty == true)
                ? existing!.callsign
                : ref.read(settingsProvider).myCallsign;
            if (callsign.isNotEmpty) {
              final self = RivrNode(
                nodeId: nodeId,
                callsign: callsign,
                rssiDbm: existing?.rssiDbm ?? 0,
                snrDb: existing?.snrDb ?? 0,
                hopCount: 0,
                linkScore: existing?.linkScore ?? 100,
                lossPercent: existing?.lossPercent ?? 0,
                lastSeen: DateTime.now(),
                role: existing?.role ?? 1,
                lat: existing?.lat,
                lon: existing?.lon,
              );
              _setNode(self);
            }
          }
        }
      });
    });
    // Clear the self-node entry on disconnect so it doesn't linger.
    ref.listen(connectionStateProvider, (_, next) {
      next.whenData((s) {
        if (!s.isConnected) state = {};
      });
    });
    // Also react to position changes made via the settings screen so the
    // self-node stays in sync without waiting for the next connect.
    ref.listen(connectedNodePositionProvider, (_, pos) {
      final nodeId = ref.read(connectedNodeIdProvider);
      if (nodeId == 0) return;
      final existing = state[nodeId];
      if (pos != null) {
        final self = RivrNode(
          nodeId: nodeId,
          callsign: existing?.callsign ?? '',
          rssiDbm: existing?.rssiDbm ?? 0,
          snrDb: existing?.snrDb ?? 0,
          hopCount: 0,
          linkScore: existing?.linkScore ?? 100,
          lossPercent: existing?.lossPercent ?? 0,
          lastSeen: DateTime.now(),
          role: existing?.role ?? 1,
          lat: pos.lat,
          lon: pos.lon,
        );
        _setNode(self);
      } else if (existing != null && existing.hopCount == 0) {
        _setNode(existing.copyWith(lat: null, lon: null));
      }
    });
    return {};
  }

  /// Updates state and persists the node to the local database.
  void _setNode(RivrNode node) {
    state = {...state, node.nodeId: node};
    _db.upsertNode(node); // fire and forget
  }

  List<RivrNode> get sorted => state.values.toList()
    ..sort((a, b) => b.linkScore.compareTo(a.linkScore));
}

final nodesProvider =
    NotifierProvider<NodesNotifier, Map<int, RivrNode>>(NodesNotifier.new);

// ── Metrics ────────────────────────────────────────────────────────────────

class MetricsNotifier extends Notifier<List<RivrMetrics>> {
  static const _maxHistory = 60;  // keep last 60 snapshots (≈5 min at 5 s)

  @override
  List<RivrMetrics> build() {
    ref.listen(eventStreamProvider, (_, next) {
      next.whenData((event) {
        if (event is MetricsEvent) {
          final next = [...state, event.metrics];
          state = next.length > _maxHistory
              ? next.sublist(next.length - _maxHistory)
              : next;
        }
      });
    });
    return [];
  }

  RivrMetrics get latest => state.isNotEmpty ? state.last : RivrMetrics.empty();
}

final metricsProvider =
    NotifierProvider<MetricsNotifier, List<RivrMetrics>>(MetricsNotifier.new);

/// Convenience: just the most recent snapshot.
final latestMetricsProvider = Provider<RivrMetrics>((ref) {
  final history = ref.watch(metricsProvider); // watch state so this rebuilds on every @MET
  return history.isNotEmpty ? history.last : RivrMetrics.empty();
});

// ── Raw log lines ─────────────────────────────────────────────────────────

class LogNotifier extends Notifier<List<String>> {
  static const maxLines = 500;

  @override
  List<String> build() {
    ref.listen(eventStreamProvider, (_, next) {
      next.whenData((event) {
        if (event is RawLineEvent) {
          _add(event.line);
        } else if (event is ChatEvent) {
          final m = event.message;
          final src =
              '0x${m.senderNodeId.toRadixString(16).toUpperCase().padLeft(8, '0')}';
          _add('[CHAT] from=${m.senderName}($src) ch=${m.channelId} "${m.text}"');
        } else if (event is MetricsEvent) {
          final m = event.metrics;
          final id =
              '0x${m.nodeId.toRadixString(16).toUpperCase().padLeft(8, '0')}';
          _add('[MET] node=$id dc=${m.dcPct}% rx=${m.rxTotal} tx=${m.txTotal}'
              ' lnk=${m.lnkCnt} rssi=${m.lnkRssi}dBm');
        } else if (event is NodeEvent) {
          final n = event.node;
          final id =
              '0x${n.nodeId.toRadixString(16).toUpperCase().padLeft(8, '0')}';
          _add('[NODE] id=$id cs=${n.callsign} hop=${n.hopCount}'
              ' rssi=${n.rssiDbm}dBm score=${n.linkScore}');
        } else if (event is TelemetryEvent) {
          final t = event.reading;
          final src =
              '0x${t.srcNodeId.toRadixString(16).toUpperCase().padLeft(8, '0')}';
          final val = (t.valueX100 / 100).toStringAsFixed(2);
          _add('[TEL] src=$src sid=${t.sensorId} val=$val unit=${t.unitCode}');
        } else if (event is DeviceInfoEvent) {
          final id =
              '0x${event.nodeId.toRadixString(16).toUpperCase().padLeft(8, '0')}';
          _add('[DEV] id=$id cs=${event.callsign}');
        }
      });
    });
    return [];
  }

  void _add(String line) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final l = [...state, '$ts $line'];
    state = l.length > maxLines ? l.sublist(l.length - maxLines) : l;
  }

  void clear() => state = [];
}

final logProvider = NotifierProvider<LogNotifier, List<String>>(LogNotifier.new);

// ── Connected node ID ─────────────────────────────────────────────────────

/// Tracks the node ID of the connected hardware node.
///
/// Updated from two sources:
///  • BLE: [DeviceInfoEvent] emitted immediately after session start
///  • Both: [MetricsEvent] which carries [RivrMetrics.nodeId]
class ConnectedNodeIdNotifier extends Notifier<int> {
  @override
  int build() {
    ref.listen(eventStreamProvider, (_, next) {
      next.whenData((event) {
        if (event is DeviceInfoEvent && event.nodeId != 0) {
          state = event.nodeId;
        } else if (event is MetricsEvent && event.metrics.nodeId != 0) {
          state = event.metrics.nodeId;
        }
      });
    });
    return 0;
  }
}

final connectedNodeIdProvider =
    NotifierProvider<ConnectedNodeIdNotifier, int>(ConnectedNodeIdNotifier.new);

/// The node ID of the currently connected hardware node, or 0 if not yet known.
/// Use this to determine "is this message mine?" in the UI.
final localMeshNodeIdProvider = Provider<int>((ref) {
  return ref.watch(connectedNodeIdProvider);
});

// ── Connected node identity (auto-loaded on USB connect) ──────────────────

/// Holds the position last reported by the connected node via `id` CLI response.
/// `null` means not set (node has no stored position).
class ConnectedNodePositionNotifier
    extends Notifier<({double lat, double lon})?> {
  @override
  ({double lat, double lon})? build() {
    ref.listen(eventStreamProvider, (_, next) {
      next.whenData((event) {
        if (event is DeviceInfoEvent) {
          if (event.lat != null && event.lon != null) {
            state = (lat: event.lat!, lon: event.lon!);
          } else if (event.nodeId != 0) {
            // Node responded but has no position stored — clear any stale value.
            state = null;
          }
          // Auto-update the saved callsign when the node reports one and
          // the app's stored callsign is empty or differs.
          if (event.callsign.isNotEmpty) {
            final current = ref.read(settingsProvider).myCallsign;
            if (current != event.callsign) {
              ref
                  .read(settingsNotifierProvider.notifier)
                  .setCallsign(event.callsign);
            }
          }
        }
      });
    });
    // Clear on disconnect.
    ref.listen(connectionStateProvider, (_, next) {
      next.whenData((s) {
        if (!s.isConnected) state = null;
      });
    });
    return null;
  }
}

final connectedNodePositionProvider =
    NotifierProvider<ConnectedNodePositionNotifier,
        ({double lat, double lon})?>(ConnectedNodePositionNotifier.new);

// ── Telemetry readings ────────────────────────────────────────────────────

/// Stores the latest reading per (nodeId, sensorId) pair.
/// Map key: nodeId → Map key: sensorId → latest TelemetryReading.
class TelemetryNotifier extends Notifier<Map<int, Map<int, TelemetryReading>>> {
  @override
  Map<int, Map<int, TelemetryReading>> build() {
    // Seed from DB: compute latest per (srcNodeId, sensorId).
    Future.microtask(() async {
      final recent = await ref.read(appDatabaseProvider).getRecentTelemetry();
      if (recent.isEmpty) return;
      final map = <int, Map<int, TelemetryReading>>{};
      for (final r in recent) {
        // recent is sorted oldest-first, so later entries overwrite earlier.
        map.putIfAbsent(r.srcNodeId, () => {})[r.sensorId] = r;
      }
      // Merge so live readings received before load completes are kept.
      for (final entry in map.entries) {
        final live = state[entry.key];
        if (live == null) {
          state = {...state, entry.key: entry.value};
        } else {
          final merged = Map<int, TelemetryReading>.from(entry.value)..addAll(live);
          state = {...state, entry.key: merged};
        }
      }
    });

    ref.listen(eventStreamProvider, (_, next) {
      next.whenData((event) {
        if (event is TelemetryEvent) {
          final r = event.reading;
          final nodeMap = Map<int, TelemetryReading>.from(
              state[r.srcNodeId] ?? {});
          nodeMap[r.sensorId] = r;
          state = {...state, r.srcNodeId: nodeMap};
        }
      });
    });
    return {};
  }
}

final telemetryProvider = NotifierProvider<TelemetryNotifier,
    Map<int, Map<int, TelemetryReading>>>(TelemetryNotifier.new);

// ── Telemetry history (for charts) ────────────────────────────────────────

/// Stores a timestamped list of readings per (nodeId, sensorId).
/// Map key: nodeId → Map key: sensorId → ordered list of readings (oldest first).
class TelemetryHistoryNotifier
    extends Notifier<Map<int, Map<int, List<TelemetryReading>>>> {
  static const _maxPoints = 120; // ~2 h at 60 s TX interval

  AppDatabase get _db => ref.read(appDatabaseProvider);

  @override
  Map<int, Map<int, List<TelemetryReading>>> build() {
    // Seed with last 7 days of readings from the database.
    Future.microtask(() async {
      final stored = await _db.getRecentTelemetry();
      if (stored.isEmpty) return;
      final map = <int, Map<int, List<TelemetryReading>>>{};
      for (final r in stored) {
        map.putIfAbsent(r.srcNodeId, () => {})
            .putIfAbsent(r.sensorId, () => [])
            .add(r);
      }
      // Merge live readings that arrived before the load completed.
      final merged = Map<int, Map<int, List<TelemetryReading>>>.from(map);
      for (final nodeEntry in state.entries) {
        for (final sensorEntry in nodeEntry.value.entries) {
          final existing = merged
              .putIfAbsent(nodeEntry.key, () => {})
              .putIfAbsent(sensorEntry.key, () => []);
          existing.addAll(sensorEntry.value);
        }
      }
      state = merged;
    });
    // Prune stale rows from the DB once on startup (best-effort).
    Future.microtask(() => _db.pruneOldTelemetry());

    ref.listen(eventStreamProvider, (_, next) {
      next.whenData((event) {
        if (event is TelemetryEvent) {
          final r = event.reading;
          final nodeSensors = Map<int, List<TelemetryReading>>.from(
              state[r.srcNodeId] ?? {});
          final history = List<TelemetryReading>.from(
              nodeSensors[r.sensorId] ?? [])
            ..add(r);
          nodeSensors[r.sensorId] = history.length > _maxPoints
              ? history.sublist(history.length - _maxPoints)
              : history;
          state = {...state, r.srcNodeId: nodeSensors};
          _db.insertTelemetry(r); // fire and forget
        }
      });
    });
    return {};
  }
}

final telemetryHistoryProvider = NotifierProvider<TelemetryHistoryNotifier,
    Map<int, Map<int, List<TelemetryReading>>>>(TelemetryHistoryNotifier.new);

// ── Website telemetry forwarding ──────────────────────────────────────────

/// Manages the [TelemetryForwardService] lifecycle.
/// Always active — forwards data to the built-in server using hardcoded
/// defaults, falling back to user-overridden values if present.
final telemetryForwardProvider = Provider<TelemetryForwardService>((ref) {
  final settings = ref.watch(settingsProvider);

  final service = TelemetryForwardService(
    baseUrl: settings.webUploadUrl,
    token: settings.webUploadToken,
  );

  final eventStream = ref.watch(connectionManagerProvider).eventStream;
  service.attach(eventStream);

  ref.onDispose(service.dispose);

  return service;
});

/// Live upload stats.
final webUploadStatsProvider = StreamProvider<WebUploadStats>((ref) {
  return ref.watch(telemetryForwardProvider).statsStream;
});

// ── Android foreground service ────────────────────────────────────────────

/// Starts the Android foreground service when connected and stops it on
/// disconnect, preventing the OS from pausing the process in the background
/// and interrupting telemetry forwarding.
final foregroundServiceProvider = Provider<void>((ref) {
  ref.listen(connectionStateProvider, (_, next) {
    next.whenData((s) {
      if (s.isConnected) {
        startForegroundService('Connected — forwarding mesh data');
      } else {
        stopForegroundService();
      }
    });
  });
});
