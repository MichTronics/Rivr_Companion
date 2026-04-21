import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../protocol/rivr_protocol.dart';

/// Live upload statistics — exposed via [TelemetryForwardService.statsStream].
class WebUploadStats {
  final int sent;
  final int failed;
  final DateTime? lastSuccess;

  const WebUploadStats({
    this.sent = 0,
    this.failed = 0,
    this.lastSuccess,
  });
}

/// Forwards received Rivr events to the Rivr website ingest API.
///
/// Only forwards when [webUploadUrl] is non-empty. Failures are silently
/// ignored so the companion app is never blocked by connectivity issues.
///
/// Start by calling [attach] with the connection manager's event stream.
/// Call [dispose] when no longer needed.
class TelemetryForwardService {
  final String _baseUrl;
  final String _token;

  StreamSubscription<RivrEvent>? _sub;
  final http.Client _client = http.Client();

  int _sent = 0;
  int _failed = 0;
  DateTime? _lastSuccess;

  final _statsController = StreamController<WebUploadStats>.broadcast();
  // Caches the most recently seen role per node so that position-only updates
  // (BEACON pos log lines, role=0) can still be uploaded with the correct role.
  final Map<int, int> _roleCache = {};

  /// Live stream of upload statistics — listen in the UI to show status.
  Stream<WebUploadStats> get statsStream => _statsController.stream;

  TelemetryForwardService({required String baseUrl, required String token})
      : _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _token = token;

  /// Start listening to [eventStream] and forwarding events.
  void attach(Stream<RivrEvent> eventStream) {
    _sub?.cancel();
    _roleCache.clear();
    _sub = eventStream.listen(_onEvent);
  }

  void _onEvent(RivrEvent event) {
    Map<String, dynamic>? payload;

    if (event is NodeEvent) {
      final node = event.node;
      if (node.role != 0) _roleCache[node.nodeId] = node.role;
      if (node.hasPosition) {
        final resolvedRole = node.role != 0 ? node.role : (_roleCache[node.nodeId] ?? 0);
        payload = {
          'type': 'node',
          'data': {
            'nodeId': node.nodeIdHex,
            'callsign': node.callsign,
            'lat': node.lat,
            'lon': node.lon,
            'rssi': node.rssiDbm,
            'hopCount': node.hopCount,
            'role': resolvedRole,
          },
          'ts': DateTime.now().millisecondsSinceEpoch,
        };
      }
    } else if (event is DeviceInfoEvent &&
        event.nodeId != 0 &&
        event.lat != null &&
        event.lon != null &&
        event.role != 0) {
      payload = {
        'type': 'node',
        'data': {
          'nodeId':
              '0x${event.nodeId.toRadixString(16).toUpperCase().padLeft(8, '0')}',
          'callsign': event.callsign,
          'lat': event.lat,
          'lon': event.lon,
          'rssi': null,
          'hopCount': 0,
          'role': event.role,
        },
        'ts': DateTime.now().millisecondsSinceEpoch,
      };
    } else if (event is TelemetryEvent) {
      final r = event.reading;
      payload = {
        'type': 'telemetry',
        'data': {
          'nodeId': '0x${r.srcNodeId.toRadixString(16).toUpperCase().padLeft(8, '0')}',
          'sensorId': r.sensorId,
          'value': r.value,
          'unit': r.unitSuffix,
        },
        'ts': r.receivedAt.millisecondsSinceEpoch,
      };
    } else if (event is ChatEvent) {
      final m = event.message;
      payload = {
        'type': 'chat',
        'data': {
          'sender': m.senderName,
          'text': m.text,
        },
        'ts': m.timestamp.millisecondsSinceEpoch,
      };
    }

    if (payload != null) {
      _post(payload);
    }
  }

  void _post(Map<String, dynamic> payload) {
    _client
        .post(
          Uri.parse('$_baseUrl/api/ingest'),
          headers: {
            'Content-Type': 'application/json',
            'x-ingest-token': _token,
          },
          body: jsonEncode(payload),
        )
        .then((response) {
          if (response.statusCode >= 200 && response.statusCode < 300) {
            _sent++;
            _lastSuccess = DateTime.now();
          } else {
            _failed++;
          }
          _emitStats();
        })
        .catchError((_) {
          _failed++;
          _emitStats();
        });
  }

  void _emitStats() {
    if (!_statsController.isClosed) {
      _statsController.add(WebUploadStats(
        sent: _sent,
        failed: _failed,
        lastSuccess: _lastSuccess,
      ));
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _statsController.close();
    _client.close();
  }
}
