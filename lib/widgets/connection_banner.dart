import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/connection_manager.dart';

/// Thin status bar shown at the very top of every screen.
/// Green when connected, amber when scanning/connecting, transparent otherwise.
class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connState = ref.watch(connectionStateProvider);

    return connState.when(
      data: (state) => _BannerContent(state: state),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _BannerContent extends StatelessWidget {
  final RivrConnState state;
  const _BannerContent({required this.state});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    switch (state.status) {
      case ConnectionStatus.connected:
        return _Banner(
          color: Colors.green.shade700,
          icon: Icons.link,
          text: 'Connected · ${state.deviceName}',
        );
      case ConnectionStatus.connecting:
        return _Banner(
          color: Colors.orange.shade700,
          icon: Icons.sync,
          text: 'Connecting to ${state.deviceName}…',
          showSpinner: true,
        );
      case ConnectionStatus.scanning:
        return _Banner(
          color: cs.secondary,
          icon: Icons.search,
          text: 'Scanning…',
          showSpinner: true,
        );
      case ConnectionStatus.error:
        return _Banner(
          color: cs.error,
          icon: Icons.error_outline,
          text: state.errorMessage ?? 'Connection error',
        );
      case ConnectionStatus.disconnected:
        return const SizedBox.shrink();
    }
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  final bool showSpinner;

  const _Banner({
    required this.color,
    required this.icon,
    required this.text,
    this.showSpinner = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      color: color,
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: MediaQuery.of(context).padding.top + 4,
        bottom: 6,
      ),
      child: Row(
        children: [
          if (showSpinner)
            const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          else
            Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
