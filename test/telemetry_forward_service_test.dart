import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rivr_companion/models/telemetry_reading.dart';
import 'package:rivr_companion/protocol/rivr_protocol.dart';
import 'package:rivr_companion/services/telemetry_forward_service.dart';

void main() {
  test('disabled telemetry forward service stays inert', () async {
    final service = TelemetryForwardService(
      baseUrl: 'https://rivr.co.nl',
      token: '',
    );
    final eventController = StreamController<RivrEvent>.broadcast();
    final stats = <WebUploadStats>[];
    final statsSub = service.statsStream.listen(stats.add);

    service.attach(eventController.stream);

    eventController.add(
      TelemetryEvent(
        TelemetryReading(
          srcNodeId: 0xAABBCCDD,
          sensorId: kSensorDs18b20Temp,
          valueX100: 2150,
          unitCode: kUnitCelsius,
          timestampS: 42,
          receivedAt: DateTime.fromMillisecondsSinceEpoch(1000),
        ),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(stats, isEmpty);

    await statsSub.cancel();
    await eventController.close();
    service.dispose();
  });
}