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
    _sub = eventStream.listen(_onEvent);
  }

  void _onEvent(RivrEvent event) {
    Map<String, dynamic>? payload;

    if (event is NodeEvent && event.node.hasPosition) {
      payload = {
        'type': 'node',
        'data': {
          'nodeId': event.node.nodeIdHex,
          'callsign': event.node.callsign,
          'lat': event.node.lat,
          'lon': event.node.lon,
          'rssi': event.node.rssiDbm,
          'hopCount': event.node.hopCount,
          'role': event.node.role,
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
