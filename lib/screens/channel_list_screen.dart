import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/channel.dart';
import '../providers/channel_provider.dart';
import 'channel_thread_screen.dart';
import 'sensor_channel_screen.dart';

/// Channel list screen — the primary chat UX entry point.
///
/// Displays all joined, non-hidden channels with per-channel unread counts.
/// Tapping a channel navigates to [ChannelThreadScreen].
/// Muted channels are shown with dimmed styling.
/// Hidden channels do not appear unless explicitly revealed via settings.
class ChannelListScreen extends ConsumerWidget {
  const ChannelListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(joinedChannelsProvider);
    final channelTable = ref.watch(channelTableProvider);
    final activeChannelId = ref.watch(activeChannelProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return channelTable.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (_) {
        if (channels.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.forum_outlined,
                      size: 56, color: cs.onSurface.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text(
                    'No channels joined.',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: cs.onSurface.withValues(alpha: 0.5)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Channel 0 (Global) will appear once connected.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.outline),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: channels.length,
          separatorBuilder: (_, i) => const Divider(height: 1, indent: 16),
          itemBuilder: (context, index) {
            final channelState = channels[index];
            return _ChannelTile(
              channelState: channelState,
              isActive: channelState.config.channelId == activeChannelId,
              onTap: () => _openChannel(context, ref, channelState),
            );
          },
        );
      },
    );
  }

  void _openChannel(
      BuildContext context, WidgetRef ref, ChannelState channelState) {
    ref.read(activeChannelProvider.notifier).setActive(
          channelState.config.channelId,
        );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => channelState.config.channelId == 4
            ? const SensorChannelScreen()
            : ChannelThreadScreen(
                channelId: channelState.config.channelId,
              ),
      ),
    );
  }
}

class _ChannelTile extends ConsumerWidget {
  final ChannelState channelState;
  final bool isActive;
  final VoidCallback onTap;

  const _ChannelTile({
    required this.channelState,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;
    final cfg   = channelState.config;
    final mem   = channelState.membership;
    final unread = channelState.unreadCount;

    final isMuted    = mem.muted;
    final isPriority = cfg.isPriority;

    // Pick a leading icon by channel kind
    final icon = _iconFor(cfg.kind, isPriority);
    final iconColor = isMuted
        ? cs.onSurface.withValues(alpha: 0.3)
        : isPriority
            ? cs.error
            : cs.primary;

    // Peek at most recent message
    final messages = ref.watch(channelMessageListProvider(cfg.channelId));
    final lastMsg  = messages.isNotEmpty ? messages.last : null;

    final nameStyle = theme.textTheme.titleMedium?.copyWith(
      color: isMuted ? cs.onSurface.withValues(alpha: 0.5) : cs.onSurface,
      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
    );

    return ListTile(
      key: ValueKey(cfg.channelId),
      selected: isActive,
      selectedTileColor: cs.primaryContainer.withValues(alpha: 0.35),
      leading: CircleAvatar(
        backgroundColor: iconColor.withValues(alpha: 0.12),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(cfg.displayName, style: nameStyle, overflow: TextOverflow.ellipsis),
          ),
          if (mem.txDefault)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.send, size: 12, color: cs.secondary),
            ),
          if (isMuted)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.volume_off, size: 12, color: cs.outline),
            ),
        ],
      ),
      subtitle: lastMsg != null
          ? Text(
              '${lastMsg.isLocal ? "You: " : ""}${lastMsg.text}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isMuted
                    ? cs.onSurface.withValues(alpha: 0.35)
                    : cs.onSurface.withValues(alpha: 0.65),
              ),
            )
          : null,
      trailing: unread > 0
          ? Badge(
              label: Text(unread > 99 ? '99+' : '$unread'),
              backgroundColor: isPriority ? cs.error : cs.primary,
            )
          : null,
      onTap: onTap,
    );
  }

  IconData _iconFor(ChannelKind kind, bool isPriority) {
    if (isPriority) return Icons.warning_amber_rounded;
    switch (kind) {
      case ChannelKind.public:    return Icons.public;
      case ChannelKind.group:     return Icons.group;
      case ChannelKind.emergency: return Icons.warning_amber_rounded;
      case ChannelKind.system:    return Icons.settings_suggest;
      case ChannelKind.restricted: return Icons.lock_outline;
    }
  }
}
