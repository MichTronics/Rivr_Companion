import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/channel.dart';
import '../models/chat_message.dart';
import '../protocol/rivr_protocol.dart';
import '../providers/settings_provider.dart';
import 'app_providers.dart';

// ── Persistence keys ───────────────────────────────────────────────────────

const String _kChannelMembershipKey = 'channel_membership_v1';
const String _kTxChannelKey         = 'channel_tx_default';

// ═══════════════════════════════════════════════════════════════════════════
// CHANNEL TABLE NOTIFIER
// ═══════════════════════════════════════════════════════════════════════════

/// Manages the bounded local channel table: config + membership state.
///
/// State is a [Map<int, ChannelState>] keyed by channel_id.
/// Map is always bounded to [kMaxChannels] entries.
///
/// Persistence: membership (joined/muted/hidden/txDefault) is saved to
/// SharedPreferences as a compact comma-separated string.
/// Config (names, kinds) comes from defaults or future companion-side sync.
class ChannelTableNotifier extends AsyncNotifier<Map<int, ChannelState>> {
  @override
  Future<Map<int, ChannelState>> build() async {
    return await _load();
  }

  Future<Map<int, ChannelState>> _load() async {
    final prefs = await SharedPreferences.getInstance();

    // Reconstruct from defaults
    final Map<int, ChannelState> table = {};
    for (var i = 0; i < kDefaultChannels.length; i++) {
      final cfg = kDefaultChannels[i];
      final mem = kDefaultMembership[i];
      table[cfg.channelId] = ChannelState(config: cfg, membership: mem);
    }

    // Load saved membership overrides
    final saved = prefs.getString(_kChannelMembershipKey);
    if (saved != null && saved.isNotEmpty) {
      _applyPersistedMembership(table, saved);
    }

    // Load TX default
    final txDefault = prefs.getInt(_kTxChannelKey) ?? kChanGlobal;
    _applyTxDefault(table, txDefault);

    return table;
  }

  /// Parse compact persistence format:
  ///   `<chanId>:<joined>:<muted>:<hidden>;<chanId>:...`
  void _applyPersistedMembership(Map<int, ChannelState> table, String raw) {
    for (final entry in raw.split(';')) {
      final parts = entry.split(':');
      if (parts.length < 4) continue;
      final id = int.tryParse(parts[0]);
      if (id == null || !table.containsKey(id)) continue;
      final joined = parts[1] == '1';
      final muted  = parts[2] == '1';
      final hidden = parts[3] == '1';
      final existing = table[id]!;
      table[id] = existing.copyWith(
        membership: existing.membership.copyWith(
          joined: joined,
          muted:  muted,
          hidden: hidden,
        ),
      );
    }
  }

  void _applyTxDefault(Map<int, ChannelState> table, int txDefault) {
    for (final key in table.keys) {
      final existing = table[key]!;
      table[key] = existing.copyWith(
        membership: existing.membership.copyWith(txDefault: key == txDefault),
      );
    }
  }

  Future<void> _persist(Map<int, ChannelState> table) async {
    final prefs = await SharedPreferences.getInstance();

    final parts = table.values.map((cs) {
      final m = cs.membership;
      return '${m.channelId}:${m.joined ? 1 : 0}:${m.muted ? 1 : 0}:${m.hidden ? 1 : 0}';
    }).join(';');
    await prefs.setString(_kChannelMembershipKey, parts);

    final txEntry = table.values
        .where((cs) => cs.membership.txDefault)
        .map((cs) => cs.config.channelId)
        .firstOrNull ?? kChanGlobal;
    await prefs.setInt(_kTxChannelKey, txEntry);
  }

  // ── Public API ─────────────────────────────────────────────────────────

  Map<int, ChannelState> get _current => state.value ?? {};

  void join(int channelId) {
    final table = Map<int, ChannelState>.from(_current);
    if (!table.containsKey(channelId)) return;
    table[channelId] = table[channelId]!.copyWith(
      membership: table[channelId]!.membership.copyWith(joined: true),
    );
    state = AsyncData(table);
    _persist(table);
  }

  void leave(int channelId) {
    if (channelId == kChanGlobal) return; // Global cannot be left
    final table = Map<int, ChannelState>.from(_current);
    if (!table.containsKey(channelId)) return;
    final cs = table[channelId]!;
    table[channelId] = cs.copyWith(
      membership: cs.membership.copyWith(joined: false, txDefault: false),
    );
    // If this was the TX default, revert to Global
    if (cs.membership.txDefault) {
      final g = table[kChanGlobal];
      if (g != null) {
        table[kChanGlobal] = g.copyWith(
          membership: g.membership.copyWith(txDefault: true),
        );
      }
    }
    state = AsyncData(table);
    _persist(table);
  }

  void setMuted(int channelId, bool muted) {
    final table = Map<int, ChannelState>.from(_current);
    if (!table.containsKey(channelId)) return;
    table[channelId] = table[channelId]!.copyWith(
      membership: table[channelId]!.membership.copyWith(muted: muted),
    );
    state = AsyncData(table);
    _persist(table);
  }

  void setHidden(int channelId, bool hidden) {
    final table = Map<int, ChannelState>.from(_current);
    if (!table.containsKey(channelId)) return;
    table[channelId] = table[channelId]!.copyWith(
      membership: table[channelId]!.membership.copyWith(hidden: hidden),
    );
    state = AsyncData(table);
    _persist(table);
  }

  bool setTxDefault(int channelId) {
    final table = Map<int, ChannelState>.from(_current);
    if (!table.containsKey(channelId)) return false;
    if (!table[channelId]!.membership.joined) return false;

    // Clear all tx_default flags first
    for (final key in table.keys) {
      final cs = table[key]!;
      if (cs.membership.txDefault) {
        table[key] = cs.copyWith(
          membership: cs.membership.copyWith(txDefault: false),
        );
      }
    }
    table[channelId] = table[channelId]!.copyWith(
      membership: table[channelId]!.membership.copyWith(txDefault: true),
    );
    state = AsyncData(table);
    _persist(table);
    return true;
  }

  int get txDefaultId {
    for (final cs in _current.values) {
      if (cs.membership.txDefault) return cs.config.channelId;
    }
    return kChanGlobal;
  }

  void incrementUnread(int channelId) {
    final table = Map<int, ChannelState>.from(_current);
    if (!table.containsKey(channelId)) return;
    final cs = table[channelId]!;
    if (cs.membership.muted) return; // suppress unread when muted
    table[channelId] = cs.copyWith(unreadCount: cs.unreadCount + 1);
    state = AsyncData(table);
  }

  void clearUnread(int channelId) {
    final table = Map<int, ChannelState>.from(_current);
    if (!table.containsKey(channelId)) return;
    table[channelId] = table[channelId]!.copyWith(unreadCount: 0);
    state = AsyncData(table);
  }

  List<ChannelState> get joined => _current.values
      .where((cs) => cs.membership.joined && !cs.membership.hidden)
      .toList()
    ..sort((a, b) => a.config.channelId.compareTo(b.config.channelId));
}

final channelTableProvider =
    AsyncNotifierProvider<ChannelTableNotifier, Map<int, ChannelState>>(
        ChannelTableNotifier.new);

/// Convenience: sorted list of visible joined channels.
final joinedChannelsProvider = Provider<List<ChannelState>>((ref) {
  return ref.watch(channelTableProvider).maybeWhen(
    data: (table) => table.values
        .where((cs) => cs.membership.joined && !cs.membership.hidden)
        .toList()
      ..sort((a, b) => a.config.channelId.compareTo(b.config.channelId)),
    orElse: () => [],
  );
});

/// Current default TX channel ID.
final txChannelIdProvider = Provider<int>((ref) {
  return ref.watch(channelTableProvider).maybeWhen(
    data: (table) {
      for (final cs in table.values) {
        if (cs.membership.txDefault) return cs.config.channelId;
      }
      return kChanGlobal;
    },
    orElse: () => kChanGlobal,
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// CHANNEL MESSAGES NOTIFIER
// ═══════════════════════════════════════════════════════════════════════════

/// One unified message store keyed by channel_id.
///
/// This is the single source of truth for all channel messages.
/// No parallel "global chat" vs "private chat" split.
/// Channel 0 (Global) holds all legacy PKT_CHAT messages too.
///
/// State: `Map<int, List<ChatMessage>>` — channel_id → ordered message list.
class ChannelMessagesNotifier extends Notifier<Map<int, List<ChatMessage>>> {
  static const int _maxMessagesPerChannel = 500;

  /// Pending local echo suppression: text → (sentAt, remaining count).
  final Map<String, ({DateTime sentAt, int remaining})> _pendingEchoes = {};
  static const _echoWindow = Duration(seconds: 3);

  @override
  Map<int, List<ChatMessage>> build() {
    // Listen to all incoming events
    ref.listen(eventStreamProvider, (_, next) {
      next.whenData((event) {
        if (event is ChatEvent) _handleIncoming(event.message);
      });
    });
    return {};
  }

  void _handleIncoming(ChatMessage msg) {
    final channelId = msg.channelId;

    // Suppress exact self-echoes from the radio node
    final localNodeId = ref.read(metricsProvider.notifier).latest.nodeId;
    if (localNodeId != 0 && msg.senderNodeId == localNodeId) return;

    final phoneNodeId = ref.read(settingsProvider).phoneNodeId;
    if (phoneNodeId != 0 && msg.senderNodeId == phoneNodeId) return;

    // Text-based fallback echo suppression
    final pending = _pendingEchoes[msg.text];
    if (pending != null) {
      if (DateTime.now().difference(pending.sentAt) < _echoWindow) {
        final remaining = pending.remaining - 1;
        if (remaining > 0) {
          _pendingEchoes[msg.text] = (sentAt: pending.sentAt, remaining: remaining);
        } else {
          _pendingEchoes.remove(msg.text);
        }
        return;
      }
      _pendingEchoes.remove(msg.text);
    }

    // Enrich sender name with known callsign
    final nodes = ref.read(nodesProvider);
    final node  = nodes[msg.senderNodeId];
    final enriched = (node != null && node.callsign.isNotEmpty)
        ? ChatMessage(
            id:           msg.id,
            text:         msg.text,
            senderNodeId: msg.senderNodeId,
            senderName:   '${node.callsign} (${msg.senderName})',
            timestamp:    msg.timestamp,
            origin:       msg.origin,
            channelId:    channelId,
          )
        : msg;

    _insertMessage(channelId, enriched);

    // Increment unread counter for inactive channels
    final channelTable = ref.read(channelTableProvider);
    channelTable.whenData((table) {
      final cs = table[channelId];
      if (cs != null && cs.membership.joined) {
        // Only increment unread — UI layer decides when to clear it
        ref.read(channelTableProvider.notifier).incrementUnread(channelId);
      }
    });
  }

  void _insertMessage(int channelId, ChatMessage msg) {
    final current = Map<int, List<ChatMessage>>.from(state);
    final list    = List<ChatMessage>.from(current[channelId] ?? []);
    list.add(msg);
    if (list.length > _maxMessagesPerChannel) {
      list.removeRange(0, list.length - _maxMessagesPerChannel);
    }
    current[channelId] = list;
    state = current;
  }

  /// Add a locally-composed message to the specified channel immediately.
  /// Also registers an echo-suppression entry.
  void addLocal(ChatMessage msg) {
    final existing = _pendingEchoes[msg.text];
    _pendingEchoes[msg.text] = (
      sentAt:    DateTime.now(),
      remaining: (existing?.remaining ?? 0) + 1,
    );
    _insertMessage(msg.channelId, msg);
  }

  void addSystem(String text, {int channelId = kChanGlobal}) {
    _insertMessage(channelId, ChatMessage.system(text, channelId: channelId));
  }

  List<ChatMessage> messagesFor(int channelId) =>
      state[channelId] ?? const [];
}

final channelMessagesProvider =
    NotifierProvider<ChannelMessagesNotifier, Map<int, List<ChatMessage>>>(
        ChannelMessagesNotifier.new);

/// Convenience: messages for a specific channel (watched).
final channelMessageListProvider =
    Provider.family<List<ChatMessage>, int>((ref, channelId) {
  final all = ref.watch(channelMessagesProvider);
  return all[channelId] ?? const [];
});

// ═══════════════════════════════════════════════════════════════════════════
// ACTIVE CHANNEL PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

/// Tracks which channel the user currently has open in the thread view.
/// When the user opens a channel, its unread count should be cleared.
class ActiveChannelNotifier extends Notifier<int> {
  @override
  int build() => kChanGlobal;

  void setActive(int channelId) {
    if (state != channelId) {
      state = channelId;
      ref.read(channelTableProvider.notifier).clearUnread(channelId);
    }
  }
}

final activeChannelProvider =
    NotifierProvider<ActiveChannelNotifier, int>(ActiveChannelNotifier.new);
