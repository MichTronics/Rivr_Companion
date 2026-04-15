import 'package:equatable/equatable.dart';

/// Sensor IDs as defined in firmware_core/sensors.c
const int kSensorDs18b20Temp = 1; // DS18B20 temperature
const int kSensorAm2302Rh   = 2; // AM2302 relative humidity
const int kSensorAm2302Temp = 3; // AM2302 temperature
const int kSensorVbat        = 4; // Battery voltage (mV)

/// Unit codes as defined in firmware_core/protocol.h
const int kUnitCelsius    = 1;
const int kUnitPercentRh  = 2;
const int kUnitMillivolts = 3;

/// A single decoded @TEL telemetry reading from a Rivr node.
///
/// Wire format:
///   @TEL {"src":"0xAABBCCDD","sid":2,"val":4120,"unit":2,"unit_str":"%RH*100","ts":951}
///
/// [valueX100] is the raw firmware value (e.g. 2160 = 21.60 °C or 4120 = 41.20 %RH).
class TelemetryReading extends Equatable {
  final int srcNodeId;    // 32-bit source node ID
  final int sensorId;     // kSensor* constant above
  final int valueX100;    // value × 100 (int32, signed)
  final int unitCode;     // kUnit* constant above
  final int timestampS;   // seconds since node boot
  final DateTime receivedAt;

  const TelemetryReading({
    required this.srcNodeId,
    required this.sensorId,
    required this.valueX100,
    required this.unitCode,
    required this.timestampS,
    required this.receivedAt,
  });

  /// Human-readable label for this sensor slot.
  String get sensorLabel {
    switch (sensorId) {
      case kSensorDs18b20Temp: return 'DS18B20 Temp';
      case kSensorAm2302Rh:   return 'AM2302 RH';
      case kSensorAm2302Temp: return 'AM2302 Temp';
      case kSensorVbat:        return 'Battery';
      default:                return 'Sensor $sensorId';
    }
  }

  /// True when this is a voltage sensor.
  bool get isVoltage => unitCode == kUnitMillivolts;

  /// Floating-point value.
  /// For temperature/humidity: valueX100 ÷ 100.
  /// For battery voltage (UNIT_MILLIVOLTS): valueX100 is already in mV.
  double get value {
    if (isVoltage) return valueX100 / 1000.0;   // mV → V
    return valueX100 / 100.0;
  }

  /// Short unit string shown after the value.
  String get unitSuffix {
    if (unitCode == kUnitPercentRh)  return '%';
    if (unitCode == kUnitMillivolts) return 'V';
    return '°C';
  }

  /// Formatted value string, e.g. "21.60 °C", "41.20 %", "3.72 V".
  String get formatted {
    if (isVoltage) return '${value.toStringAsFixed(2)} V';
    return '${value.toStringAsFixed(2)} $unitSuffix';
  }

  /// True when this is a temperature sensor.
  bool get isTemperature => unitCode == kUnitCelsius;

  /// True when this is a humidity sensor.
  bool get isHumidity => unitCode == kUnitPercentRh;

  @override
  List<Object?> get props =>
      [srcNodeId, sensorId, valueX100, unitCode, timestampS, receivedAt];
}
