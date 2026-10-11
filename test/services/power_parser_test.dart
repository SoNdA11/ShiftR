import 'package:flutter_test/flutter_test.dart';
import 'package:shiftr_ble/services/power_parser.dart';

void main() {
  group('PowerParser.parsePowerMeasurement', () {
    test('parses power without crank data', () {
      // flags=0x0000, power=200W LE
      final m = PowerParser.parsePowerMeasurement([0x00, 0x00, 0xC8, 0x00]);
      expect(m.power, 200);
      expect(m.hasCrank, isFalse);
    });

    test('short payload returns zero power', () {
      expect(PowerParser.parsePowerMeasurement([]).power, 0);
      expect(PowerParser.parsePowerMeasurement([0x00, 0x00]).power, 0);
    });

    test('clamps negative power to zero', () {
      // 0xFFFF as i16 = -1
      final m = PowerParser.parsePowerMeasurement([0x00, 0x00, 0xFF, 0xFF]);
      expect(m.power, 0);
    });

    test('parses crank revs when flag 0x20 set', () {
      // flags=0x20, power=150, revs=1000 (0x03E8), time=2048 (0x0800)
      final m = PowerParser.parsePowerMeasurement(
          [0x20, 0x00, 0x96, 0x00, 0xE8, 0x03, 0x00, 0x08]);
      expect(m.power, 150);
      expect(m.crankRevs, 1000);
      expect(m.crankTime, 2048);
    });

    test('ignores crank section when truncated', () {
      final m = PowerParser.parsePowerMeasurement([0x20, 0x00, 0x64, 0x00]);
      expect(m.power, 100);
      expect(m.hasCrank, isFalse);
    });
  });

  group('PowerParser.parseCscMeasurement', () {
    test('returns null for empty data', () {
      expect(PowerParser.parseCscMeasurement([]), isNull);
    });

    test('parses crank revs with flag 0x02', () {
      final c = PowerParser.parseCscMeasurement(
          [0x02, 0x0A, 0x00, 0x00, 0x04]);
      expect(c, isNotNull);
      expect(c!.revs, 10);
      expect(c.time, 1024);
    });

    test('skips wheel data when flag 0x01 set', () {
      // flags=0x03: 6 wheel bytes, then crank revs=5, time=512
      final c = PowerParser.parseCscMeasurement(
          [0x03, 1, 2, 3, 4, 5, 6, 0x05, 0x00, 0x00, 0x02]);
      expect(c, isNotNull);
      expect(c!.revs, 5);
      expect(c.time, 512);
    });

    test('returns null when crank flag absent', () {
      expect(PowerParser.parseCscMeasurement([0x00]), isNull);
    });
  });

  group('PowerParser.cadenceFromDelta', () {
    test('computes 60rpm for 1 rev per 1024 ticks', () {
      final cadence = PowerParser.cadenceFromDelta(
          revs: 11, time: 1024, lastRevs: 10, lastTime: 0);
      expect(cadence, closeTo(60.0, 0.01));
    });

    test('handles 16-bit wrap-around', () {
      final cadence = PowerParser.cadenceFromDelta(
          revs: 1, time: 2048, lastRevs: 0xFFFF, lastTime: 0);
      expect(cadence, closeTo(60.0, 0.01));
    });

    test('returns null without history', () {
      expect(
          PowerParser.cadenceFromDelta(
              revs: 5, time: 100, lastRevs: null, lastTime: null),
          isNull);
    });

    test('returns null when time delta is zero', () {
      expect(
          PowerParser.cadenceFromDelta(
              revs: 6, time: 100, lastRevs: 5, lastTime: 100),
          isNull);
    });

    test('rejects implausible cadence over 200rpm', () {
      // 10 revs in 1024 ticks = 600rpm
      expect(
          PowerParser.cadenceFromDelta(
              revs: 10, time: 1024, lastRevs: 0, lastTime: 0),
          isNull);
    });
  });

  group('PowerParser.isValidControlFrame', () {
    test('accepts frame with matching checksum', () {
      // bytes 0..7 sum = 1+2+...+8 = 36; crc LE bytes: 36, 0
      final frame = [1, 2, 3, 4, 5, 6, 7, 8, 36, 0];
      expect(PowerParser.isValidControlFrame(frame), isTrue);
    });

    test('rejects frame with bad checksum', () {
      expect(
          PowerParser.isValidControlFrame(
              [1, 2, 3, 4, 5, 6, 7, 8, 0, 0]),
          isFalse);
    });

    test('rejects short frames', () {
      expect(PowerParser.isValidControlFrame([1, 2, 3]), isFalse);
    });
  });
}
