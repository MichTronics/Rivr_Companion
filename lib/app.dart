import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/channel_list_screen.dart';
import 'screens/nodes_screen.dart';
import 'screens/network_map_screen.dart';
import 'screens/diagnostics_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/connection_banner.dart';
import 'providers/settings_provider.dart';
import 'providers/app_providers.dart';

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
    // Rivr website palette
    const primary = Color(0xFF6C63FF);   // --accent
    const secondary = Color(0xFF00E5A0); // --green
    const error = Color(0xFFFF5252);     // --red
    const warning = Color(0xFFFFCA28);   // --yellow

    if (brightness == Brightness.dark) {
      const bg       = Color(0xFF0A0A0F); // --background
      const surface  = Color(0xFF12121A); // --surface
      const surface2 = Color(0xFF1A1A26); // --surface-2
      const fg       = Color(0xFFE8EAF6); // --foreground
      const muted    = Color(0xFF8B8FA8); // --text-muted
      const border   = Color(0x336C63FF); // rgba(108,99,255,0.2)

      final cs = ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.dark,
      ).copyWith(
        primary: primary,
        onPrimary: Colors.white,
        primaryContainer: surface2,
        onPrimaryContainer: fg,
        secondary: secondary,
        onSecondary: bg,
        secondaryContainer: surface,
        onSecondaryContainer: fg,
        tertiary: warning,
        onTertiary: bg,
        error: error,
        onError: Colors.white,
        surface: surface,
        onSurface: fg,
        onSurfaceVariant: muted,
        outline: border,
        outlineVariant: const Color(0x1A6C63FF),
      );

      return ThemeData(
        useMaterial3: true,
        colorScheme: cs,
        scaffoldBackgroundColor: bg,
        appBarTheme: const AppBarTheme(
          backgroundColor: surface,
          foregroundColor: fg,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: surface,
          indicatorColor: const Color(0x286C63FF),
          iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? primary : muted,
          )),
          labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            color: states.contains(WidgetState.selected) ? primary : muted,
            fontSize: 12,
          )),
        ),
        cardTheme: CardThemeData(
          color: surface2,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: border),
          ),
        ),
        dividerTheme: const DividerThemeData(color: border, space: 1),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: primary, width: 1.5),
          ),
        ),
      );
    } else {
      return ThemeData.light(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          brightness: Brightness.light,
        ).copyWith(
          secondary: secondary,
          tertiary: warning,
          error: error,
        ),
      );
    }
  }
}

class RivrShell extends ConsumerStatefulWidget {
  const RivrShell({super.key});

  @override
  ConsumerState<RivrShell> createState() => _RivrShellState();
}

class _RivrShellState extends ConsumerState<RivrShell> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    // Eagerly read the forward provider so it is created (and the service
    // starts) as soon as the shell mounts — even before any navigation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(telemetryForwardProvider);
    });
  }

  static const _tabs = [
    NavigationDestination(
      icon: Icon(Icons.forum_outlined),
      selectedIcon: Icon(Icons.forum),
      label: 'Channels',
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
    ChannelListScreen(),
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
