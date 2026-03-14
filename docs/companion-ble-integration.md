# Rivr Companion App — BLE Integration Guide

This document covers everything the companion app needs to know to implement a correct, robust
BLE connection to a Rivr node running a `client_<board>_ble` firmware build.

---

## 1. Overview

The Rivr BLE transport is **not a custom protocol** — it is a thin bridge that carries the
**same binary Rivr packet frames** that normally travel over LoRa.  The companion app receives
live mesh traffic and can inject frames into the mesh exactly as if it were another mesh node.

```
Phone / Companion app
│
│  BLE (NUS GATT service)
│
Rivr node (client_*_ble firmware)
│
│  LoRa (SX1262 / SX1276)
│
rest of the mesh
```

The node acts as a **transparent bridge**: frames written by the phone are pushed into the node's
receive ring buffer and processed identically to frames arriving from LoRa (protocol decode,
dedupe, routing, RIVR engine).  Frames received from the mesh (before dedupe) are forwarded to
the connected phone via BLE notify.

---

## 2. BLE service UUIDs (Nordic NUS)

The node uses the **Nordic UART Service** UUIDs. These are widely supported in Flutter BLE
packages (`flutter_reactive_ble`, `flutter_blue_plus`, etc.) and are recognised by nRF Connect.

| Role | Characteristic | UUID | Properties |
|---|---|---|---|
| Service | — | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` | — |
| **RX** (phone → node) | Write | `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` | Write / Write Without Response |
| **TX** (node → phone) | Notify | `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` | Notify |

> **Memory aid:**  From the phone's perspective, _you write to RX_ and _subscribe to TX_.
> The name comes from the node's perspective (RX = what the node receives, TX = what it transmits).

---

## 3. Scanning for a node

### Advertisement name pattern

Every Rivr node advertises as:

```
RIVR-XXXX
```

Where `XXXX` is the **lower 16 bits** of the node's 32-bit ID in uppercase hex.

Examples:
- Node ID `0xAB12CD34` → advertises as **`RIVR-CD34`**
- Node ID `0x00000001` → advertises as **`RIVR-0001`**

### Service UUID in advertisement

The advertisement payload includes the **full 128-bit service UUID** (`6E400001-...`), allowing
the app to filter scan results by UUID instead of name if preferred.

### Advertising interval

The node advertises at **500–1000 ms** intervals.  Typical scan discovery time is under 2 s
with active scanning.

### Recommended scan filter

Filter on either:
```dart
// By service UUID (preferred — future-proof)
filterServiceUuid: Uuid.parse('6E400001-B5A3-F393-E0A9-E50E24DCCA9E')

// Or by name prefix
filterLocalNameStartsWith: 'RIVR-'
```

---

## 4. Activation windows

BLE is **not always on** — the node manages an activation window to save power.  The app must
connect within the active window, or trigger a new one.

| Mode | Duration | Trigger |
|---|---|---|
| **BOOT_WINDOW** | 120 seconds after boot | Automatic (default) |
| **BUTTON** | 300 seconds (5 minutes) | User presses a hardware button on the node |
| **APP_REQUESTED** | Indefinite, until deactivated | Mesh command (future) |

### What this means for the app

1. **After the node boots**, connect within 120 s — or instruct the user to press the button.
2. **If the connection drops** and the window is still open, the node restarts advertising
   automatically.  Reconnect without any user action required.
3. **If the window expired**, the user must press the button (or reboot the node) to reopen BLE.
4. **The app cannot detect** whether the window is open before connecting.  Scan timeouts imply
   the window is closed.

> **UX suggestion:** Show a "searching…" state for 5–8 s.  If no device is found, prompt:
> _"Press the button on your Rivr node or restart it to enable Bluetooth."_

---

## 5. MTU and frame sizes

### MTU negotiation

The node firmware configures `CONFIG_BT_NIMBLE_ATT_PREFERRED_MTU = 128`.

**Always request a higher MTU** after connecting:

```dart
// flutter_reactive_ble example
await _ble.requestMtu(deviceId: deviceId, mtu: 247);
```

After negotiation, the effective payload per write/notify is:
```
effective_payload = negotiated_mtu - 3 (ATT header overhead)
```

| Negotiated MTU | Max bytes per write/notify |
|---|---|
| 23 (default, no negotiation) | **20 bytes** — too small for most Rivr frames |
| 128 (node preferred) | 125 bytes |
| 247 (BLE 4.2+, recommended) | 244 bytes — fits any Rivr frame (max 255 bytes) |

> ⚠ **Do not skip MTU negotiation.** The minimum Rivr frame is 25 bytes and the typical CHAT
> frame is 30–60 bytes.  The default 20-byte ATT payload will truncate most frames.

### Frame size limits

| Constant | Value |
|---|---|
| Minimum frame size | 25 bytes (23-byte header + 2-byte CRC) |
| Maximum frame size | 255 bytes (LoRa hardware limit) |
| Maximum payload inside a frame | 230 bytes |

The node rejects writes that exceed 255 bytes with `ATT_ERR_INVALID_ATTR_VALUE_LEN`.

---

## 6. Wire format — binary Rivr packet

All communication uses the **binary Rivr frame format**, identical to LoRa frames.
The app must encode frames it sends and decode frames it receives using this layout.

### Frame layout

```
Offset  Len  Field           Type     Notes
──────  ───  ──────────────  ───────  ────────────────────────────────────────
  0      2   magic           u16 LE   Always 0x5256 ("RV"). Reject if wrong.
  2      1   version         u8       Protocol version. Currently 1.
  3      1   pkt_type        u8       See packet type table below.
  4      1   flags           u8       Bitmask: 0x01=ACK_REQ, 0x02=RELAYED, 0x04=FALLBACK
  5      1   ttl             u8       Hops remaining. Default 7. Decrement on relay.
  6      4   src_id          u32 LE   Originating node ID.
 10      4   dst_id          u32 LE   Destination node ID. 0xFFFFFFFF = broadcast.
 14      2   net_id          u16 LE   Network partition ID. 0x0000 = default.
 16      1   hop_count       u8       Hops taken so far.
 17      2   seq             u16 LE   Per-source sequence counter (message ordering).
 19      2   pkt_id          u16 LE   Deduplication fingerprint (do not set — firmware fills).
 21      1   payload_len     u8       Number of application payload bytes that follow.
 22      1   (reserved)      u8       Always 0.
 23     [N]  payload         bytes    Application-specific bytes (payload_len bytes).
 23+N    2   crc             u16 LE   CRC-16/CCITT over bytes [0 .. 23+N-1].
```

### Packet types

| Value | Constant | Description |
|---|---|---|
| 1 | `PKT_CHAT` | Text message (`@CHT` JSON log) |
| 2 | `PKT_BEACON` | Periodic node-presence advertisement |
| 3 | `PKT_ROUTE_REQ` | Route request (routing control) |
| 4 | `PKT_ROUTE_RPL` | Route reply (routing control) |
| 5 | `PKT_ACK` | Acknowledgement |
| 6 | `PKT_DATA` | Generic sensor / application data |
| 7 | `PKT_PROG_PUSH` | OTA RIVR program push (Ed25519-signed) |
| 8 | `PKT_TELEMETRY` | Structured telemetry payload |
| 9 | `PKT_MAILBOX` | Store-and-forward message |
| 10 | `PKT_ALERT` | High-priority alert |

### CRC algorithm

```
CRC-16/CCITT (CRC-16/CCITT-FALSE)
  Width    : 16
  Poly     : 0x1021
  Init     : 0xFFFF
  RefIn    : false
  RefOut   : false
  XorOut   : 0x0000
```

The CRC covers **all bytes from offset 0 through the last byte of the payload** (i.e. the CRC
itself is excluded from the calculation).

### PKT_CHAT payload format

```
Offset  Len  Field
  0      1   (reserved, 0x00)
  1      1   (reserved, 0x00)
  2      2   msg_seq   u16 LE   per-origin chat message sequence
  4      3   (reserved, 0x00)
  7     [N]  text      UTF-8    message body (N = payload_len − 7)
```

---

## 7. Receiving frames from the node (node → phone)

1. **Subscribe to notifications** on the TX characteristic (`6E400003-...`) after connecting.
2. Each notification carries **one complete binary Rivr frame** (no framing layer, no length
   prefix — the BLE notification length is the frame length).
3. **The app receives all mesh traffic** seen by the node before deduplication — including
   frames from other nodes that the client node forwarded.
4. Validate the frame: check magic (`0x5256`), verify CRC.  Drop silently on failure.
5. Inspect `pkt_type` to route to the appropriate UI handler.

```dart
// flutter_reactive_ble example
final sub = _ble.subscribeToCharacteristic(txChar).listen((data) {
  final bytes = Uint8List.fromList(data);
  if (!validateRivrFrame(bytes)) return;   // check magic + CRC
  final pktType = bytes[3];
  switch (pktType) {
    case PKT_CHAT:      handleChat(bytes);      break;
    case PKT_BEACON:    handleBeacon(bytes);    break;
    case PKT_TELEMETRY: handleTelemetry(bytes); break;
    // ...
  }
});
```

---

## 8. Sending frames to the node (phone → node)

1. **Build a complete binary Rivr frame** including magic, all header fields, payload, and CRC.
2. **Set `src_id`** to the phone's virtual node ID — pick a fixed random 32-bit value and persist
   it locally (do not generate a new ID each session).
3. Set `dst_id` to `0xFFFFFFFF` for broadcast CHAT, or the target's node ID for unicast.
4. Set `ttl` to 7 (default).  The node will decrement on relay.
5. Set `seq` to an incrementing counter per `src_id`.
6. **Leave `pkt_id` as 0** — the node's firmware does not use the phone's `pkt_id` for
   its own dedup fingerprint on frames that originate from the phone.
7. Write to the RX characteristic (`6E400002-...`):
   - Use **Write Without Response** for lower latency (`BLE_GATT_CHR_F_WRITE_NO_RSP`).
   - Use **Write With Response** if you want delivery confirmation from the node.
8. Maximum write size: `negotiated_mtu - 3` bytes per write.  For Rivr frames ≤ 125 bytes,
   a single write is sufficient after MTU negotiation to 128.  For frames up to 255 bytes,
   negotiate to 247+.

> ⚠ **No fragmentation layer exists in the firmware.** Each write must be a single, complete
> Rivr frame.  Do not split a frame across multiple writes and do not send multiple frames in
> one write.

---

## 9. Connection lifecycle

```
App                              Rivr node (BLE active)
 │                                   │
 │── scan (filter: RIVR- or UUID) ──►│  (advertising 500–1000 ms)
 │                                   │
 │── connect ────────────────────────►│  GAP CONNECT event
 │                                   │  g_metrics.ble_connections++
 │── request MTU (247) ──────────────►│  MTU event logged
 │                                   │
 │── subscribe TX notify ────────────►│  SUBSCRIBE event logged
 │                                   │
 │◄── notify (mesh frame) ───────────│  for each frame from mesh
 │── write RX (Rivr frame) ──────────►│  pushed into rf_rx_ringbuf → main loop
 │                                   │
 │── disconnect (or window expires) ──►│  GAP DISCONNECT event
 │                                   │  restarts advertising (if window open)
 │                                   │  g_metrics.ble_connections not bumped again
```

**Reconnection:** on disconnect, the node restarts advertising immediately (if the activation
window is still open).  The app should attempt reconnection with exponential back-off (e.g.
1 s → 2 s → 5 s) before prompting the user.

---

## 10. Security — current state

| Property | v0.1.0-beta |
|---|---|
| Encryption | ❌ None (plaintext BLE) |
| Pairing / bonding | ❌ None |
| Authentication | ❌ None |
| Filter by address | ❌ Not implemented |

**Implication for the companion app:** any phone or BLE scanner in range can connect to the node
during an active window and inject frames into the mesh.  This is intentional for the beta —
treat the BLE interface as a local physical-proximity trust boundary, equivalent to plugging in
a serial cable.

A future version will add NimBLE SM pairing (passkey or OOB).  The API will expose a
`RIVR_BLE_SECURITY` config flag when pairing is implemented.

---

## 11. Metrics the app can monitor

The node emits an `@MET` JSON snapshot on request (`metrics` CLI command) or continuously
on the `@MET` serial log channel.  The following counters are BLE-specific:

| Key | Meaning |
|---|---|
| `ble_conn` | Cumulative successful BLE connections |
| `ble_rx` | Frames received from the phone and injected into the mesh |
| `ble_tx` | Frames forwarded to the phone via TX notify |
| `ble_err` | BLE stack errors (mbuf alloc failure, write out of range) |

The app can request a snapshot by sending the ASCII string `metrics\r\n` as a **PKT_DATA or
serial CLI** message (not a BLE write — the serial CLI is separate from the BLE interface).
Alternatively, if connected via USB serial concurrently, the `metrics` command is available on
UART0.

---

## 12. Flutter package recommendations

| Package | Notes |
|---|---|
| [`flutter_reactive_ble`](https://pub.dev/packages/flutter_reactive_ble) | Recommended. Reactive streams, good MTU support, works on Android + iOS. |
| [`flutter_blue_plus`](https://pub.dev/packages/flutter_blue_plus) | Also suitable. Broader platform support (Android, iOS, macOS, Linux, Windows). |

Both packages support Nordic NUS UUIDs out of the box.  For `flutter_reactive_ble`:

```dart
const kServiceUuid  = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';
const kRxCharUuid   = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';
const kTxCharUuid   = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';

final rxChar = QualifiedCharacteristic(
  serviceId:      Uuid.parse(kServiceUuid),
  characteristicId: Uuid.parse(kRxCharUuid),
  deviceId: deviceId,
);

final txChar = QualifiedCharacteristic(
  serviceId:      Uuid.parse(kServiceUuid),
  characteristicId: Uuid.parse(kTxCharUuid),
  deviceId: deviceId,
);

// Subscribe to incoming mesh frames
_ble.subscribeToCharacteristic(txChar).listen(onFrame);

// Send a frame to the mesh
await _ble.writeCharacteristicWithoutResponse(rxChar, value: frameBytes);
```

---

## 13. Platform permissions

### Android (required in `AndroidManifest.xml`)

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<!-- API level < 31: -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

### iOS / macOS (required in `Info.plist`)

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Rivr uses Bluetooth to communicate with LoRa mesh nodes.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>Rivr uses Bluetooth to communicate with LoRa mesh nodes.</string>
```

### Linux

Requires BlueZ ≥ 5.50 and the `bluetooth` system service running.  No additional permissions
beyond adding the user to the `bluetooth` group.

### Windows

Requires Windows 10 1703 (Creators Update) or later.  Use `flutter_blue_plus` for Windows BLE
support (`flutter_reactive_ble` does not support Windows as of 2026).

---

## 14. Known limitations (v0.1.0-beta)

| Limitation | Detail |
|---|---|
| **One client at a time** | `CONFIG_BT_NIMBLE_MAX_CONNECTIONS = 1`. A second phone cannot connect while one is already connected. |
| **No fragmentation** | Each BLE write / notify is exactly one complete Rivr frame. Frames > (`mtu - 3`) cannot be carried without MTU negotiation. |
| **No encryption** | BLE traffic is plaintext. See Section 10. |
| **Activation window** | BLE is not always on. See Section 4. |
| **No phone↔phone relay** | Frames injected via BLE are processed by the connected node only; they do not bypass the node's relay policy. A PKT_CHAT written by the phone is subject to the same duty-cycle and relay rules as any LoRa frame. |
| **ESP32-S3 BLE stability** | Heltec V3 and LilyGo T3-S3 use ESP32-S3. NimBLE on ESP32-S3 with IDF 5.x is stable but has less community testing than ESP32 classic. Report regressions. |
