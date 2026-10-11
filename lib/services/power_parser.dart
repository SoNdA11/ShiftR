import '../core/constants.dart';

/// Pure BLE measurement parsing (no flutter_blue_plus dependency).
///
/// Extracted from `TrainerService` so it can be unit-tested with raw bytes.
/// See `docs/protocol.md` for frame layouts.
class PowerParser {
  /// Parses Cycling Power Measurement (2A63).
  /// Returns (powerWatts, crankRevs, crankTime) — crank fields null when absent.
  static PowerMeasurement parsePowerMeasurement(List<int> data) {
    if (data.length < 4) return const PowerMeasurement(power: 0);
    final flags = data[0] | (data[1] << 8);
    final raw = (data[2] | (data[3] << 8)).toSigned(16);
    final power = raw >= 0 ? raw : 0;

    var offset = 4;
    if ((flags & 0x01) != 0) offset += 1;
    if ((flags & 0x04) != 0) offset += 2;
    if ((flags & 0x10) != 0) offset += 6;

    if ((flags & 0x20) != 0 && data.length >= offset + 4) {
      final revs = data[offset] | (data[offset + 1] << 8);
      final time = data[offset + 2] | (data[offset + 3] << 8);
      return PowerMeasurement(power: power, crankRevs: revs, crankTime: time);
    }
    return PowerMeasurement(power: power);
  }

  /// Parses CSC Measurement (2A5B) crank section. Null when absent.
  static CrankData? parseCscMeasurement(List<int> data) {
    if (data.isEmpty) return null;
    final flags = data[0];
    var offset = 1;
    if ((flags & 0x01) != 0) offset += 6; // wheel data
    if ((flags & 0x02) != 0 && data.length >= offset + 4) {
      return CrankData(
        revs: data[offset] | (data[offset + 1] << 8),
        time: data[offset + 2] | (data[offset + 3] << 8),
      );
    }
    return null;
  }

  /// Cadence (rpm) from crank-revolution deltas with 16-bit wrap-around.
  /// Returns null when the sample must be ignored (no delta or implausible).
  static double? cadenceFromDelta({
    required int revs,
    required int time,
    required int? lastRevs,
    required int? lastTime,
  }) {
    if (lastRevs == null || lastTime == null) return null;
    final dRevs = (revs - lastRevs) & 0xFFFF;
    final dTime = (time - lastTime) & 0xFFFF;
    if (dTime <= 0) return null;
    final cadence = dRevs * 1024.0 * 60.0 / dTime;
    if (cadence > SpeedModel.maxCadenceRpm) return null;
    return cadence;
  }

  /// Validates a 10-byte FFF4 vendor frame (sum of bytes 0..7 vs bytes 8..9).
  static bool isValidControlFrame(List<int> data) {
    if (data.length < 10) return false;
    final sum = data.sublist(0, 8).fold<int>(0, (a, b) => a + b);
    final crc = (data[9] << 8) | data[8];
    return sum == crc;
  }
}

class PowerMeasurement {
  final int power;
  final int? crankRevs;
  final int? crankTime;
  const PowerMeasurement({required this.power, this.crankRevs, this.crankTime});
  bool get hasCrank => crankRevs != null && crankTime != null;
}

class CrankData {
  final int revs;
  final int time;
  const CrankData({required this.revs, required this.time});
}
