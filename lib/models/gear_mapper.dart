import 'dart:math';

class GearMapper {
  static const int minGear = 1;
  static const int maxGear = 24;

  static int clampGear(int gear) {
    return gear.clamp(minGear, maxGear);
  }

  static int gearToResistance(int gear, [double stepPercent = 0.08]) {
    final clamped = clampGear(gear);
    final rawMin = 1.0;
    final rawMax = pow(1.0 + stepPercent, maxGear - minGear);
    final rawCurrent = pow(1.0 + stepPercent, clamped - minGear);

    // Scale so that Marcha 1 maps to 0% and Marcha 24 maps to 100%
    final resistance = 100.0 * (rawCurrent - rawMin) / (rawMax - rawMin);
    return resistance.round().clamp(0, 100);
  }

  static String gearLabel(int gear) {
    final clamped = clampGear(gear);
    return '$clamped';
  }
}
