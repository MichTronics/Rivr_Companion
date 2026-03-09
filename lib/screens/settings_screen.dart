import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../providers/app_providers.dart';
import '../providers/settings_provider.dart';
import '../services/ble_service.dart';
import '../services/serial_service.dart';
import '../protocol/rivr_protocol.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _callsignCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-fill callsign from saved settings
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _callsignCtrl.text = ref.read(settingsProvider).myCallsign;
    });
  }

  @override
  void dispose() {
    _callsignCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final connState = ref.watch(connectionStateProvider);
    final isConnected = connState.maybeWhen(
      data: (s) => s.isConnected,
      orElse: () => false,
    );
    final deviceName = connState.maybeWhen(
      data: (s) => s.deviceName,
      orElse: () => '',
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Connection ────────────────────────────────────────────────────
          _SettingsSection(
            title: 'Connection',
            children: [
              ListTile(
                leading: Icon(
                  isConnected ? Icons.link : Icons.link_off,
                  color: isConnected ? Colors.green : null,
                ),
                title: Text(isConnected ? 'Connected to $deviceName' : 'Not connected'),
                subtitle: const Text('Tap to connect or disconnect'),
                onTap: isConnected ? _disconnect : _showConnectSheet,
                trailing: isConnected
                    ? TextButton(
                        onPressed: _disconnect,
                        child: const Text('Disconnect'))
                    : FilledButton(
                        onPressed: _showConnectSheet,
                        child: const Text('Connect')),
              ),
            ],
          ),

          // ── Identity ──────────────────────────────────────────────────────
          _SettingsSection(
            title: 'Identity',
            children: [
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('My Callsign'),
                subtitle: Text(settings.myCallsign.isEmpty
                    ? 'Not set — node ID will be used'
                    : settings.myCallsign),
                onTap: () => _editCallsign(settings),
              ),
            ],
          ),

          // ── Appearance ────────────────────────────────────────────────────
          _SettingsSection(
            title: 'Appearance',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.dark_mode_outlined),
                title: const Text('Dark mode'),
                value: settings.darkMode,
                onChanged: (v) =>
                    ref.read(settingsNotifierProvider.notifier).setDarkMode(v),
              ),
            ],
          ),

          // ── Advanced (hidden until toggle is on) ──────────────────────────
          _SettingsSection(
            title: 'Advanced',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.tune),
                title: const Text('Advanced mode'),
                subtitle: const Text('Shows additional diagnostic controls'),
                value: settings.advancedMode,
                onChanged: (v) =>
                    ref.read(settingsNotifierProvider.notifier).setAdvancedMode(v),
              ),
              if (settings.advancedMode) ...[
                _BaudRateTile(currentRate: settings.lastUsbBaudRate),
                ListTile(
                  leading: const Icon(Icons.developer_mode),
                  title: const Text('Request fwdset snapshot'),
                  subtitle: const Text('Prints relay candidate set to log'),
                  enabled: isConnected,
                  onTap: () => ref
                      .read(connectionManagerProvider)
                      .send(RivrProtocol.cmdFwdset),
                ),
                ListTile(
                  leading: const Icon(Icons.analytics_outlined),
                  title: const Text('Request routing stats (@RST)'),
                  enabled: isConnected,
                  onTap: () => ref
                      .read(connectionManagerProvider)
                      .send(RivrProtocol.cmdRtstats),
                ),
              ],
            ],
          ),

          // ── About ─────────────────────────────────────────────────────────
          _SettingsSection(
            title: 'About',
            children: const [
              ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Rivr Companion'),
                subtitle: Text('v1.0.0 — open-source LoRa mesh companion'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _disconnect() async {
    await ref.read(connectionManagerProvider).disconnect();
  }

  Future<void> _showConnectSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ConnectSheet(),
    );
  }

  Future<void> _editCallsign(AppSettings settings) async {
    _callsignCtrl.text = settings.myCallsign;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set callsign'),
        content: TextField(
          controller: _callsignCtrl,
          maxLength: 11,
          decoration: const InputDecoration(
            hintText: 'e.g. W1AW or ALICE',
            helperText: 'Max 11 characters',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, _callsignCtrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (result != null) {
      await ref.read(settingsNotifierProvider.notifier).setCallsign(result);
    }
  }
}

// ── Connect sheet ─────────────────────────────────────────────────────────

class _ConnectSheet extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ConnectSheet> createState() => _ConnectSheetState();
}

enum _ConnectMode { ble, usb }

class _ConnectSheetState extends ConsumerState<_ConnectSheet> {
  _ConnectMode _mode = _ConnectMode.ble;
  List<String> _scanned = [];
  bool _isScanning = false;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (ctx, scrollCtrl) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<_ConnectMode>(
                segments: const [
                  ButtonSegment(
                      value: _ConnectMode.ble,
                      icon: Icon(Icons.bluetooth),
                      label: Text('Bluetooth')),
                  ButtonSegment(
                      value: _ConnectMode.usb,
                      icon: Icon(Icons.usb),
                      label: Text('USB Serial')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() {
                  _mode = s.first;
                  _scanned = [];
                }),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _scanned.isEmpty
                  ? Center(
                      child: _isScanning
                          ? const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 12),
                                Text('Scanning…'),
                              ],
                            )
                          : FilledButton.icon(
                              onPressed: _scan,
                              icon: const Icon(Icons.search),
                              label: Text(_mode == _ConnectMode.ble
                                  ? 'Scan for BLE devices'
                                  : 'Scan for USB devices'),
                            ),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      itemCount: _scanned.length,
                      itemBuilder: (_, i) {
                        final parts = _scanned[i].split(':');
                        final id = parts.length > 1 ? parts[1] : '';
                        final name = parts.length > 2 ? parts.sublist(2).join(': ') : id;
                        return ListTile(
                          leading: Icon(_mode == _ConnectMode.ble
                              ? Icons.bluetooth
                              : Icons.usb),
                          title: Text(name.isNotEmpty ? name : id),
                          subtitle: Text(id),
                          onTap: () => _connectTo(id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  StreamSubscription<RivrEvent>? _scanSub;

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }

  Future<void> _scan() async {
    if (!mounted) return;
    setState(() {
      _isScanning = true;
      _scanned = [];
    });

    // Each scan creates a fresh transport; the manager takes ownership.
    final service = _mode == _ConnectMode.ble
        ? BleService()
        : SerialService();
    await ref.read(connectionManagerProvider).useTransport(service);
    await _scanSub?.cancel();
    _scanSub = ref.read(connectionManagerProvider).eventStream.listen((event) {
      if (!mounted) return;
      if (event is RawLineEvent) {
        if (event.line.startsWith('BLE_SCAN:') ||
            event.line.startsWith('USB_SCAN:')) {
          setState(() => _scanned.add(event.line));
        }
      }
    });
    await ref.read(connectionManagerProvider).startScan();
    await Future.delayed(const Duration(seconds: 5));
    if (mounted) setState(() => _isScanning = false);
  }

  Future<void> _connectTo(String id) async {
    Navigator.pop(context);
    await ref.read(connectionManagerProvider).connect(id);
  }
}

// ── Shared UI helpers ─────────────────────────────────────────────────────

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary),
          ),
        ),
        ...children,
        const Divider(height: 1),
      ],
    );
  }
}

class _BaudRateTile extends ConsumerWidget {
  final int currentRate;
  const _BaudRateTile({required this.currentRate});

  static const _rates = [9600, 19200, 38400, 57600, 115200, 230400, 460800];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.speed),
      title: const Text('USB Baud rate'),
      subtitle: Text('$currentRate baud'),
      trailing: DropdownButton<int>(
        value: currentRate,
        underline: const SizedBox.shrink(),
        items: _rates
            .map((r) => DropdownMenuItem(value: r, child: Text('$r')))
            .toList(),
        onChanged: (v) {
          if (v != null) {
            ref.read(settingsNotifierProvider.notifier).setBaudRate(v);
          }
        },
      ),
    );
  }
}
