import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/channel.dart';
import '../models/chat_message.dart';
import '../protocol/rivr_protocol.dart';
import '../providers/app_providers.dart';
import '../providers/channel_provider.dart';
import '../providers/settings_provider.dart';

/// Per-channel message thread with composer.
///
/// Watching [channelMessageListProvider] scoped to [channelId] means only
/// the messages for this channel cause a rebuild — other channels' messages
/// do not trigger a re-render here.
///
/// Lifecycle:
///   - On open: marks this channel as active (clears unread badge).
///   - On pop:  clears active channel (-1), restoring badge counting.
class ChannelThreadScreen extends ConsumerStatefulWidget {
  final int channelId;

  const ChannelThreadScreen({super.key, required this.channelId});

  @override
  ConsumerState<ChannelThreadScreen> createState() =>
      _ChannelThreadScreenState();
}

class _ChannelThreadScreenState extends ConsumerState<ChannelThreadScreen> {
  final _controller = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    // Mark channel as open — clears unread counter immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeChannelProvider.notifier).setActive(widget.channelId);
    });
  }

  @override
  void dispose() {
    // Stop suppressing unread counts for this channel on exit.
    ref.read(activeChannelProvider.notifier).setActive(-1);
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();

    setState(() => _isSending = true);

    final settings = ref.read(settingsProvider);
    final manager  = ref.read(connectionManagerProvider);

    if (!manager.currentState.isConnected) {
      ref.read(channelMessagesProvider.notifier).addSystem(
            'Not connected — message not sent.',
            channelId: widget.channelId,
          );
      setState(() => _isSending = false);
      return;
    }

    // Optimistic local echo
    ref.read(channelMessagesProvider.notifier).addLocal(
          ChatMessage.local(
            text: text,
            myNodeId: settings.phoneNodeId,
            myCallsign: settings.myCallsign,
            channelId: widget.channelId,
          ),
        );

    await manager.send(
      RivrProtocol.buildChatCommand(text, channelId: widget.channelId),
    );
    setState(() => _isSending = false);

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final channelTable = ref.watch(channelTableProvider);
    final messages     = ref.watch(channelMessageListProvider(widget.channelId));
    final connState    = ref.watch(connectionStateProvider);
    final isConnected  = connState.maybeWhen(
      data: (s) => s.isConnected,
      orElse: () => false,
    );

    // Auto-scroll on new incoming message
    ref.listen(channelMessageListProvider(widget.channelId), (_, __) {
      _scrollToBottom();
    });

    final channelState = channelTable.maybeWhen(
      data: (table) => table[widget.channelId],
      orElse: () => null,
    );
    final channelName = channelState?.config.displayName ?? 'Channel ${widget.channelId}';
    final isMuted     = channelState?.membership.muted ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(channelName),
            if (isMuted)
              Text(
                'Muted',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
          ],
        ),
        actions: [
          _ChannelActionMenu(channelId: widget.channelId),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? const Center(
                    child: Text(
                      'No messages yet.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    itemCount: messages.length,
                    itemBuilder: (_, i) =>
                        _ChatBubble(message: messages[i]),
                  ),
          ),
          _Composer(
            controller: _controller,
            isSending: _isSending,
            isConnected: isConnected,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

// ── Composer ──────────────────────────────────────────────────────────────

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final bool isConnected;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.isSending,
    required this.isConnected,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: isConnected,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: isConnected
                      ? 'Message…'
                      : 'Connect to a node first',
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(24)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: (isConnected && !isSending) ? onSend : null,
              icon: isSending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Chat bubble ───────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  const _ChatBubble({required this.message});

  static final _timeFmt = DateFormat('HH:mm');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;

    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Center(
          child: Text(
            message.text,
            style: theme.textTheme.bodyMedium?.copyWith(color: cs.outline),
          ),
        ),
      );
    }

    final isLocal = message.isLocal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Align(
        alignment: isLocal ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75),
          child: Column(
            crossAxisAlignment:
                isLocal ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isLocal)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                  child: Text(
                    message.senderName,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isLocal
                      ? cs.primary
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.only(
                    topLeft:    const Radius.circular(16),
                    topRight:   const Radius.circular(16),
                    bottomLeft:  Radius.circular(isLocal ? 16 : 4),
                    bottomRight: Radius.circular(isLocal ? 4 : 16),
                  ),
                ),
                child: Text(
                  message.text,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: isLocal ? cs.onPrimary : cs.onSurface,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                child: Text(
                  _timeFmt.format(message.timestamp),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.outline,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Per-channel action menu ───────────────────────────────────────────────

class _ChannelActionMenu extends ConsumerWidget {
  final int channelId;
  const _ChannelActionMenu({required this.channelId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelTable = ref.watch(channelTableProvider);
    final channelState = channelTable.maybeWhen(
      data: (t) => t[channelId],
      orElse: () => null,
    );
    if (channelState == null) return const SizedBox.shrink();

    final isMuted = channelState.membership.muted;
    final isTxDefault = channelState.membership.txDefault;
    final isGlobal = channelId == kChanGlobal;

    return PopupMenuButton<_ChannelAction>(
      onSelected: (action) =>
          _handleAction(context, ref, action, channelState),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _ChannelAction.toggleMute,
          child: ListTile(
            dense: true,
            leading: Icon(isMuted ? Icons.volume_up : Icons.volume_off),
            title: Text(isMuted ? 'Unmute' : 'Mute'),
          ),
        ),
        if (!isTxDefault)
          const PopupMenuItem(
            value: _ChannelAction.setTxDefault,
            child: ListTile(
              dense: true,
              leading: Icon(Icons.send),
              title: Text('Send here by default'),
            ),
          ),
        if (!isGlobal)
          const PopupMenuItem(
            value: _ChannelAction.leave,
            child: ListTile(
              dense: true,
              leading: Icon(Icons.exit_to_app),
              title: Text('Leave channel'),
            ),
          ),
      ],
    );
  }

  void _handleAction(
    BuildContext context,
    WidgetRef ref,
    _ChannelAction action,
    ChannelState channelState,
  ) {
    final notifier = ref.read(channelTableProvider.notifier);
    switch (action) {
      case _ChannelAction.toggleMute:
        notifier.setMuted(channelId, !channelState.membership.muted);
      case _ChannelAction.setTxDefault:
        notifier.setTxDefault(channelId);
      case _ChannelAction.leave:
        notifier.leave(channelId);
        Navigator.of(context).pop();
    }
  }
}

enum _ChannelAction { toggleMute, setTxDefault, leave }
