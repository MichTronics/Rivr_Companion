# Rivr Companion

A Flutter mobile and desktop app for monitoring and controlling a [Rivr](https://github.com/MichTronics/Rivr) LoRa mesh network.

## Features

- **Chat** — multi-channel messaging (Global, Ops, Local, Emergency, Sensor, and custom channels); send and receive `PKT_CHAT` frames over the mesh
- **Nodes** — live view of neighbour nodes with RSSI, SNR, hop count, link score, and role
- **Network Map** — geographic mesh map with GPS markers for nodes that report a position; haversine distance between nodes
- **Diagnostics** — real-time `PKT_METRICS` counter display and `@SUPPORTPACK` capture
- **Settings** — connection management, callsign, node GPS position (set/clear), dark mode, and advanced controls

## Connectivity

The companion app connects to a Rivr node via:

- **USB serial** (Android, Linux, Windows) — direct UART at 115 200 baud
- **Bluetooth LE** — wireless connection to a BLE-enabled node

## Getting Started

### Prerequisites

| Tool | Minimum version |
|---|---|
| Flutter SDK | 3.22.0 |
| Dart SDK | 3.3.0 |
| Android SDK / Xcode | as required by your target platform |

### Build and run

```bash
cd rivr_companion
flutter pub get
flutter run
```

### Supported platforms

| Platform | Status |
|---|---|
| Android | Supported (USB + BLE) |
| Linux | Supported (USB serial) |
| Windows | Supported (USB serial) |
| iOS | Planned |
| macOS | Planned |

## Connecting to a node

1. Flash a Rivr client node (see [FLASHING.md](../FLASHING.md))
2. Open the app and tap **Settings → Connect**
3. Select **USB Serial** or **Bluetooth LE**
4. The app will negotiate the connection and begin streaming metrics

## Bug reports

Tap **Diagnostics → Export Supportpack** to capture a `@SUPPORTPACK` JSON block,
then attach it to your issue at [github.com/MichTronics/Rivr/issues](https://github.com/MichTronics/Rivr/issues).
