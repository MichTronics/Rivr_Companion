import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/chat_screen.dart';
import 'screens/nodes_screen.dart';
import 'screens/network_map_screen.dart';
import 'screens/diagnostics_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/connection_banner.dart';
import 'providers/settings_provider.dart';

class RivrApp extends ConsumerWidget {
  const RivrApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      title: 'Rivr Companion',
      debugShowCheckedModeBanner: false,
      themeMode: settings.darkMode ? ThemeMode.dark : ThemeMode.light,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: const RivrShell(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final base = brightness == Brightness.dark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);
    return base.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1B6CA8),
        brightness: brightness,
      ),
    );
  }
}

class RivrShell extends ConsumerStatefulWidget {
  const RivrShell({super.key});

  @override
  ConsumerState<RivrShell> createState() => _RivrShellState();
}

class _RivrShellState extends ConsumerState<RivrShell> {
  int _selectedIndex = 0;

  static const _tabs = [
    NavigationDestination(
      icon: Icon(Icons.chat_bubble_outline),
      selectedIcon: Icon(Icons.chat_bubble),
      label: 'Chat',
    ),
    NavigationDestination(
      icon: Icon(Icons.device_hub_outlined),
      selectedIcon: Icon(Icons.device_hub),
      label: 'Nodes',
    ),
    NavigationDestination(
      icon: Icon(Icons.share_outlined),
      selectedIcon: Icon(Icons.share),
      label: 'Network',
    ),
    NavigationDestination(
      icon: Icon(Icons.monitor_heart_outlined),
      selectedIcon: Icon(Icons.monitor_heart),
      label: 'Diagnostics',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Settings',
    ),
  ];

  static const _screens = [
    ChatScreen(),
    NodesScreen(),
    NetworkMapScreen(),
    DiagnosticsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const ConnectionBanner(),
          Expanded(child: _screens[_selectedIndex]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: _tabs,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      ),
    );
  }
}
