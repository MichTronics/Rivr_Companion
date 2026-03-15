import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/connection_manager.dart';
import '../protocol/rivr_protocol.dart';
import '../models/chat_message.dart';
import '../models/rivr_node.dart';
import '../models/metrics.dart';
import '../providers/settings_provider.dart';

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
  static const _maxMessages = 500;

  /// Pending local sends keyed by text, used to suppress a single immediate TX
  /// echo when the radio's node-ID is not yet known from @MET.
  final _pendingEchoes = <String, ({DateTime sentAt, int remaining})>{};
  static const _echoWindow = Duration(seconds: 3);

  @override
  List<ChatMessage> build() {
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
  @override
  Map<int, RivrNode> build() {
    ref.listen(eventStreamProvider, (_, next) {
      next.whenData((event) {
        if (event is NodeEvent) {
          state = {...state, event.node.nodeId: event.node};
        }
      });
    });
    return {};
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
  static const _maxLines = 200;

  @override
  List<String> build() {
    ref.listen(eventStreamProvider, (_, next) {
      next.whenData((event) {
        if (event is RawLineEvent) {
          final l = [...state, event.line];
          state = l.length > _maxLines ? l.sublist(l.length - _maxLines) : l;
        }
      });
    });
    return [];
  }
}

final logProvider = NotifierProvider<LogNotifier, List<String>>(LogNotifier.new);
