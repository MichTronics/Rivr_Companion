import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;

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
  final _callsignCtrl  = TextEditingController();
  final _netIdCtrl     = TextEditingController();
  String? _nodePositionLabel;

  @override
  void initState() {
    super.initState();
    // Pre-fill callsign from saved settings
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = ref.read(settingsProvider);
      _callsignCtrl.text = s.myCallsign;
    });
  }

  @override
  void dispose() {
    _callsignCtrl.dispose();
    _netIdCtrl.dispose();
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
    final canUseSerialCli =
        isConnected && settings.lastConnectionType == ConnectionType.usb;
    final canSendPosition = isConnected;

    // Use position from the node if available, fall back to manually set label.
    final nodePos = ref.watch(connectedNodePositionProvider);
    final posLabel = nodePos != null
        ? '${nodePos.lat.toStringAsFixed(5)}, ${nodePos.lon.toStringAsFixed(5)}'
        : _nodePositionLabel;

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
        if (!s.isConnected && mounted) {
          setState(() => _nodePositionLabel = null);
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
              if (isConnected)
                ListTile(
                  leading: const Icon(Icons.hub_outlined),
                  title: const Text('Network ID'),
                  subtitle: const Text('16-bit hex ID shared by all nodes in your mesh'),
                  onTap: () => _editNetId(),
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
                subtitle: Text(posLabel ??
                    (canSendPosition
                        ? 'Set position for map visibility'
                        : 'Connect to set position')),
                enabled: canSendPosition,
                trailing: canSendPosition
                    ? PopupMenuButton<_PosPick>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (pick) {
                          switch (pick) {
                            case _PosPick.gps:
                              _setPositionFromGps();
                            case _PosPick.mapPick:
                              _setPositionFromMap();
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
                            value: _PosPick.mapPick,
                            child: ListTile(
                              leading: Icon(Icons.pin_drop_outlined),
                              title: Text('Pick on map'),
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

          // ── Web Upload ────────────────────────────────────────────────────
          const _WebUploadSection(),

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
              SwitchListTile(
                secondary: const Icon(Icons.thermostat_outlined),
                title: const Text('Show temperatures in °F'),
                subtitle: const Text('Affects sensor and diagnostic views'),
                value: settings.useFahrenheit,
                onChanged: (v) => ref
                    .read(settingsNotifierProvider.notifier)
                    .setUseFahrenheit(v),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.screen_lock_portrait_outlined),
                title: const Text('Keep screen awake'),
                subtitle: const Text('Prevents the display from turning off'),
                value: settings.keepScreenAwake,
                onChanged: (v) => ref
                    .read(settingsNotifierProvider.notifier)
                    .setKeepScreenAwake(v),
              ),
            ],
          ),

          // ── Data ──────────────────────────────────────────────────────────
          _SettingsSection(
            title: 'Data',
            children: [
              ListTile(
                leading: const Icon(Icons.history_outlined),
                title: const Text('Telemetry retention'),
                subtitle: Text(
                    '${settings.telemetryRetentionDays} day${settings.telemetryRetentionDays == 1 ? '' : 's'}'),
                onTap: () => _pickRetentionDays(settings.telemetryRetentionDays),
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
                if (isConnected)
                  ListTile(
                    leading: const Icon(Icons.sensors),
                    title: const Text('Sensor TX config'),
                    subtitle: const Text('Heartbeat interval and delta thresholds'),
                    onTap: () => _editSensorConfig(),
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

  Future<void> _editNetId() async {
    _netIdCtrl.clear();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Network ID'),
        content: TextField(
          controller: _netIdCtrl,
          maxLength: 6,
          decoration: const InputDecoration(
            hintText: 'e.g. 0x1234 or 4660',
            helperText: '0–65535 in decimal or 0x hex',
          ),
          keyboardType: TextInputType.text,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, _netIdCtrl.text.trim()),
              child: const Text('Apply')),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    int? netId;
    if (result.startsWith('0x') || result.startsWith('0X')) {
      netId = int.tryParse(result.substring(2), radix: 16);
    } else {
      netId = int.tryParse(result);
    }
    if (netId == null || netId < 0 || netId > 0xFFFF) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid Network ID — enter 0–65535')));
      }
      return;
    }
    ref.read(connectionManagerProvider)
        .sendRaw(RivrCompanionCodec.buildSetNetId(netId));
  }

  Future<void> _pickRetentionDays(int current) async {
    const options = [1, 3, 7, 14, 30];
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => RadioGroup<int>(
        groupValue: current,
        onChanged: (v) => Navigator.pop(ctx, v),
        child: SimpleDialog(
          title: const Text('Telemetry retention'),
          children: [
            for (final days in options)
              RadioListTile<int>(
                title: Text('$days day${days == 1 ? '' : 's'}'),
                value: days,
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      ref.read(settingsNotifierProvider.notifier).setTelemetryRetentionDays(picked);
    }
  }

  Future<void> _editSensorConfig() async {
    // Default values shown: firmware compile-time defaults.
    const txOptions = <String, int>{
      '30 s': 30000, '1 min': 60000, '5 min': 300000,
      '15 min': 900000, '30 min': 1800000, '1 h': 3600000,
    };
    const tempOptions = <String, int>{
      '0.1 °C': 10, '0.25 °C': 25, '0.5 °C': 50, '1 °C': 100, '2 °C': 200,
    };
    const rhOptions = <String, int>{
      '0.5 %': 50, '1 %': 100, '2 %': 200, '5 %': 500,
    };

    int txMs = 300000, minDeltaMs = 30000, deltaTemp = 50, deltaRh = 100, deltaVbat = 100;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return AlertDialog(
            title: const Text('Sensor TX Config'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Heartbeat interval'),
                  DropdownButton<int>(
                    isExpanded: true,
                    value: txMs,
                    items: txOptions.entries.map((e) =>
                        DropdownMenuItem(value: e.value, child: Text(e.key))).toList(),
                    onChanged: (v) => setState(() => txMs = v!),
                  ),
                  const SizedBox(height: 12),
                  const Text('Temperature change threshold'),
                  DropdownButton<int>(
                    isExpanded: true,
                    value: deltaTemp,
                    items: tempOptions.entries.map((e) =>
                        DropdownMenuItem(value: e.value, child: Text(e.key))).toList(),
                    onChanged: (v) => setState(() => deltaTemp = v!),
                  ),
                  const SizedBox(height: 12),
                  const Text('Humidity change threshold'),
                  DropdownButton<int>(
                    isExpanded: true,
                    value: deltaRh,
                    items: rhOptions.entries.map((e) =>
                        DropdownMenuItem(value: e.value, child: Text(e.key))).toList(),
                    onChanged: (v) => setState(() => deltaRh = v!),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Apply')),
            ],
          );
        });
      },
    );
    if (confirmed == true) {
      ref.read(connectionManagerProvider).sendRaw(
        RivrCompanionCodec.buildSetSensorConfig(
          txMs: txMs,
          minDeltaMs: minDeltaMs,
          deltaTemp: deltaTemp,
          deltaRh: deltaRh,
          deltaVbat: deltaVbat,
        ),
      );
    }
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
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
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

  Future<void> _setPositionFromMap() async {
    final result = await Navigator.of(context).push<(double, double)>(
      MaterialPageRoute(builder: (_) => const _MapPickerScreen()),
    );
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

  Future<void> _editCallsign(AppSettings settings) async {    _callsignCtrl.text = settings.myCallsign;
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

enum _PosPick { gps, mapPick, manual, clear }

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
      ref.read(connectionManagerProvider).setPendingConnectionType(selectedType);
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
      final connType =
          _mode == _ConnectMode.ble ? ConnectionType.ble : ConnectionType.usb;
      ref.read(connectionManagerProvider).setPendingConnectionType(connType);
      await ref.read(connectionManagerProvider).useTransport(service);
      await ref.read(connectionManagerProvider).connect(id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed: $e')),
        );
      }
    }
  }
}

// ── Web Upload section ────────────────────────────────────────────────────

class _WebUploadSection extends ConsumerWidget {
  const _WebUploadSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings   = ref.watch(settingsProvider);
    final statsAsync = ref.watch(webUploadStatsProvider);

    final stats    = statsAsync.value;
    Color dotColor = Colors.orange;
    String statusLine;

    if (stats == null) {
      statusLine = '${_shortUrl(settings.webUploadUrl)} — waiting for data…';
    } else if (stats.sent == 0 && stats.failed > 0) {
      statusLine = '${_shortUrl(settings.webUploadUrl)} — ${stats.failed} failed';
      dotColor   = Colors.red;
    } else {
      final lastStr = stats.lastSuccess != null
          ? _timeAgo(stats.lastSuccess!)
          : '—';
      statusLine = '${_shortUrl(settings.webUploadUrl)}  ·  '
          'Sent: ${stats.sent}  ·  Err: ${stats.failed}  ·  Last: $lastStr';
      dotColor = stats.failed > 0 ? Colors.orange : Colors.green;
    }

    return _SettingsSection(
      title: 'Web Upload',
      children: [
        ListTile(
          leading: Icon(Icons.cloud_done_outlined, color: dotColor),
          title: const Text('Forwarding data to rivr.co.nl'),
          subtitle: Text(statusLine),
          trailing: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }

  String _shortUrl(String url) =>
      url.replaceAll(RegExp(r'^https?://'), '').split('/').first;

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
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

// ── Map position picker ────────────────────────────────────────────────────

/// Full-screen map that lets the user tap or drag a pin to pick a position.
/// Returns `(latitude, longitude)` when confirmed, or pops with null.
class _MapPickerScreen extends StatefulWidget {
  const _MapPickerScreen();

  @override
  State<_MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<_MapPickerScreen> {
  // Default to a central-Europe starting view; will be overridden by GPS.
  static const _defaultCenter = LatLng(52.0, 5.0);

  late final MapController _mapController;
  LatLng _pin = _defaultCenter;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _tryInitFromGps();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _tryInitFromGps() async {
    setState(() => _locating = true);
    try {
      final svc = await Geolocator.isLocationServiceEnabled();
      if (!svc) return;
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) { return; }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      final here = LatLng(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() { _pin = here; });
        _mapController.move(here, 14);
      }
    } catch (_) {
      // Silently fall back to default centre.
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final latStr = _pin.latitude.toStringAsFixed(6);
    final lonStr = _pin.longitude.toStringAsFixed(6);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick position'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('Confirm'),
            onPressed: () =>
                Navigator.of(context).pop((_pin.latitude, _pin.longitude)),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _pin,
              initialZoom: 5,
              onTap: (_, point) => setState(() => _pin = point),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.rivr.companion',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _pin,
                    width: 48,
                    height: 48,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.location_pin,
                        size: 48, color: Colors.red),
                  ),
                ],
              ),
            ],
          ),

          // Coordinate readout at the bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Container(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Lat $latStr  Lon $lonStr',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    if (_locating)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
