import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/chat_message.dart';
import '../protocol/rivr_protocol.dart';
import '../providers/app_providers.dart';
import '../providers/settings_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();
  // canRequestFocus: false prevents this button from stealing focus on click.
  final _sendBtnFocus = FocusNode(canRequestFocus: false, skipTraversal: true);
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    // Intercept Enter at key level so the IME connection is never closed
    // (TextInputAction.send would close it, losing focus on Linux desktop).
    _focusNode.onKeyEvent = (_, event) {
      if (event is KeyDownEvent &&
          (event.logicalKey == LogicalKeyboardKey.enter ||
           event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
        _send();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    _sendBtnFocus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();

    setState(() => _isSending = true);
    final settings = ref.read(settingsProvider);
    final manager = ref.read(connectionManagerProvider);

    if (!manager.currentState.isConnected) {
      ref.read(chatProvider.notifier).addSystem('Not connected — message not sent.');
      setState(() => _isSending = false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
      return;
    }

    ref.read(chatProvider.notifier).addLocal(
          ChatMessage.local(
            text: text,
            myNodeId: settings.phoneNodeId,
            myCallsign: settings.myCallsign,
          ),
        );

    await manager.send(RivrProtocol.buildChatCommand(text));
    setState(() => _isSending = false);
    _focusNode.requestFocus();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus(); // second pass in case setState rebuild deferred it
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
    final messages = ref.watch(chatProvider);
    final connState = ref.watch(connectionStateProvider);
    final isConnected = connState.maybeWhen(
      data: (s) => s.isConnected,
      orElse: () => false,
    );

    // Auto-scroll on new message
    ref.listen(chatProvider, (_, __) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      });
    });

    return Column(
      children: [
        // Message list
        Expanded(
          child: messages.isEmpty
              ? const Center(
                  child: Text(
                    'No messages yet.\nConnect to a node and start chatting.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (ctx, i) => _ChatBubble(message: messages[i]),
                ),
        ),

        // Input bar
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    autofocus: true,
                    enabled: isConnected,
                    // send action for mobile soft-keyboard; Enter on desktop is
                    // handled by _focusNode.onKeyEvent to avoid IME close.
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: isConnected ? 'Message…' : 'Connect to a node first',
                      border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24))),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  focusNode: _sendBtnFocus,
                  onPressed: (isConnected && !_isSending) ? _send : null,
                  icon: _isSending
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  const _ChatBubble({required this.message});

  static final _timeFmt = DateFormat('HH:mm');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
              // Sender name (remote only)
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
              // Bubble
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isLocal ? cs.primary : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft:
                        Radius.circular(isLocal ? 16 : 4),
                    bottomRight:
                        Radius.circular(isLocal ? 4 : 16),
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
              // Timestamp
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                child: Text(
                  _timeFmt.format(message.timestamp),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white54,
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
