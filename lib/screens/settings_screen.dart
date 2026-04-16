import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../models/app_settings.dart';
import '../providers/app_providers.dart';
import '../providers/settings_provider.dart';
import '../services/ble_service.dart';
import '../services/connection_manager.dart';
import '../services/serial_service.dart';
import '../protocol/rivr_protocol.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _callsignCtrl = TextEditingController();
  String? _nodePositionLabel;

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
  }  @override
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
    final canUseSerialCli =
        isConnected && settings.lastConnectionType == ConnectionType.usb;

    // Show a SnackBar whenever the connection transitions to error state.
    ref.listen(connectionStateProvider, (_, next) {
      next.whenData((s) {
        if (s.status == ConnectionStatus.error && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(s.errorMessage ?? 'Connection failed'),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 5),
          ));
        }
      });
    });

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
                title: Text(
                    isConnected ? 'Connected to $deviceName' : 'Not connected'),
                subtitle: const Text('Tap to connect or disconnect'),
                onTap: isConnected ? _disconnect : _showConnectSheet,
                trailing: isConnected
                    ? TextButton(
                        onPressed: _disconnect, child: const Text('Disconnect'))
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

          // ── Node Position ─────────────────────────────────────────────
          _SettingsSection(
            title: 'Node Position',
            children: [
              ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: const Text('My node position'),
                subtitle: Text(_nodePositionLabel ??
                    (canUseSerialCli
                        ? 'Set position for map visibility'
                        : 'USB connection required')),
                enabled: canUseSerialCli,
                trailing: canUseSerialCli
                    ? PopupMenuButton<_PosPick>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (pick) {
                          switch (pick) {
                            case _PosPick.gps:
                              _setPositionFromGps();
                            case _PosPick.manual:
                              _setPositionManually();
                            case _PosPick.clear:
                              _clearPosition();
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: _PosPick.gps,
                            child: ListTile(
                              leading: Icon(Icons.gps_fixed),
                              title: Text('Use phone GPS'),
                            ),
                          ),
                          PopupMenuItem(
                            value: _PosPick.manual,
                            child: ListTile(
                              leading: Icon(Icons.edit_location_alt_outlined),
                              title: Text('Enter manually'),
                            ),
                          ),
                          PopupMenuItem(
                            value: _PosPick.clear,
                            child: ListTile(
                              leading: Icon(Icons.location_off_outlined),
                              title: Text('Clear position'),
                            ),
                          ),
                        ],
                      )
                    : null,
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
                onChanged: (v) => ref
                    .read(settingsNotifierProvider.notifier)
                    .setAdvancedMode(v),
              ),
              if (settings.advancedMode) ...[
                _BaudRateTile(currentRate: settings.lastUsbBaudRate),
                ListTile(
                  leading: const Icon(Icons.developer_mode),
                  title: const Text('Request fwdset snapshot'),
                  subtitle: const Text('Prints relay candidate set to log'),
                  enabled: canUseSerialCli,
                  onTap: canUseSerialCli
                      ? () => ref
                          .read(connectionManagerProvider)
                          .send(RivrProtocol.cmdFwdset)
                      : null,
                ),
                ListTile(
                  leading: const Icon(Icons.analytics_outlined),
                  title: const Text('Request routing stats (@RST)'),
                  subtitle: const Text('USB serial only'),
                  enabled: canUseSerialCli,
                  onTap: canUseSerialCli
                      ? () => ref
                          .read(connectionManagerProvider)
                          .send(RivrProtocol.cmdRtstats)
                      : null,
                ),
              ],
            ],
          ),

          // ── About ─────────────────────────────────────────────────────────
          const _SettingsSection(
            title: 'About',
            children: [
              ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Rivr Companion'),
                subtitle: Text('v0.1.0 — open-source LoRa mesh companion'),
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

  void _showPositionSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _sendPositionCommand(double lat, double lon) async {
    await ref
        .read(connectionManagerProvider)
        .send(RivrProtocol.buildSetPositionCommand(lat, lon));
    if (mounted) {
      setState(() {
        _nodePositionLabel =
            '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
      });
    }
  }

  Future<void> _setPositionFromGps() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showPositionSnackBar('Location services are disabled.');
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _showPositionSnackBar('Location permission denied.');
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      await _sendPositionCommand(pos.latitude, pos.longitude);
      _showPositionSnackBar('Position sent to node.');
    } catch (e) {
      _showPositionSnackBar('Failed to get GPS position: $e');
    }
  }

  Future<void> _setPositionManually() async {
    final latCtrl = TextEditingController();
    final lonCtrl = TextEditingController();
    final result = await showDialog<(double, double)?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter position'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: latCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                  signed: true, decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Latitude', hintText: '52.5134400'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lonCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                  signed: true, decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Longitude', hintText: '4.7652300'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                final lat = double.tryParse(latCtrl.text.trim());
                final lon = double.tryParse(lonCtrl.text.trim());
                if (lat != null &&
                    lon != null &&
                    lat >= -90 &&
                    lat <= 90 &&
                    lon >= -180 &&
                    lon <= 180) {
                  Navigator.pop(ctx, (lat, lon));
                }
              },
              child: const Text('Set')),
        ],
      ),
    );
    latCtrl.dispose();
    lonCtrl.dispose();
    if (result != null) {
      await _sendPositionCommand(result.$1, result.$2);
      _showPositionSnackBar('Position sent to node.');
    }
  }

  Future<void> _clearPosition() async {
    await ref
        .read(connectionManagerProvider)
        .send(RivrProtocol.buildClearPositionCommand());
    if (mounted) {
      setState(() => _nodePositionLabel = null);
    }
    _showPositionSnackBar('Position cleared.');
  }

  Future<void> _showConnectSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ConnectSheet(),
    );
  }

  Future<void> _syncCallsignToConnectedFirmware(String callsign) async {
    if (callsign.isEmpty) return;
    final connState = ref.read(connectionStateProvider);
    final isConnected =
        connState.maybeWhen(data: (s) => s.isConnected, orElse: () => false);
    if (!isConnected) return;
    await ref
        .read(connectionManagerProvider)
        .send(RivrProtocol.buildSetCallsignCommand(callsign));
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
      if (result.isNotEmpty && !RivrProtocol.isValidCallsign(result)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Callsign must be 1-11 characters: A-Z, a-z, 0-9, or -'),
            ),
          );
        }
        return;
      }
      await ref.read(settingsNotifierProvider.notifier).setCallsign(result);
      await _syncCallsignToConnectedFirmware(result);
    }
  }
}

// ── connect sheet ─────────────────────────────────────────────────────────

enum _PosPick { gps, manual, clear }

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
  void initState() {
    super.initState();
    final lastType = ref.read(settingsProvider).lastConnectionType;
    _mode =
        lastType == ConnectionType.usb ? _ConnectMode.usb : _ConnectMode.ble;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (ctx, scrollCtrl) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
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
                        // BLE events use | separator: BLE_SCAN|<mac>|<name>
                        // USB events use : separator: USB_SCAN:<path>:<label>
                        final line = _scanned[i];
                        final isBle = line.startsWith('BLE_SCAN|');
                        final parts = line.split(isBle ? '|' : ':');
                        final id = parts.length > 1 ? parts[1] : '';
                        final name = parts.length > 2
                            ? parts.sublist(2).join(isBle ? '|' : ':')
                            : id;
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
    try {
      final settings = ref.read(settingsProvider);
      final selectedType =
          _mode == _ConnectMode.ble ? ConnectionType.ble : ConnectionType.usb;
      await ref
          .read(settingsNotifierProvider.notifier)
          .setConnectionType(selectedType);

      // Each scan creates a fresh transport; the manager takes ownership.
      final service = _mode == _ConnectMode.ble
          ? BleService(phoneNodeId: settings.phoneNodeId)
          : SerialService(baudRate: settings.lastUsbBaudRate);
      await ref.read(connectionManagerProvider).useTransport(service);
      await _scanSub?.cancel();
      _scanSub =
          ref.read(connectionManagerProvider).eventStream.listen((event) {
        if (!mounted) return;
        if (event is RawLineEvent) {
          if (event.line.startsWith('BLE_SCAN|') ||
              event.line.startsWith('USB_SCAN:')) {
            setState(() => _scanned.add(event.line));
          }
        }
      });
      await ref.read(connectionManagerProvider).startScan();
      await Future.delayed(const Duration(seconds: 5));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _connectTo(String id) async {
    final settings = ref.read(settingsProvider);
    final service = _mode == _ConnectMode.ble
        ? BleService(phoneNodeId: settings.phoneNodeId)
        : SerialService(baudRate: settings.lastUsbBaudRate);

    await _scanSub?.cancel();

    if (!mounted) return;
    Navigator.pop(context);
    try {
      await ref.read(connectionManagerProvider).useTransport(service);
      await ref.read(connectionManagerProvider).connect(id);
      if (settings.myCallsign.isNotEmpty) {
        await ref.read(connectionManagerProvider).send(
              RivrProtocol.buildSetCallsignCommand(settings.myCallsign),
            );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed: $e')),
        );
      }
    }
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
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: Theme.of(context).colorScheme.primary),
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
