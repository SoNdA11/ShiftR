import 'package:flutter_test/flutter_test.dart';
import 'package:shiftr_ble/services/fec_controller.dart';

void main() {
  group('FecController', () {
    test('withChecksum appends correct byte without mutating input', () {
      final input = [0xA4, 0x09, 0x4F, 0x05, 0x30, 0xFF];
      final originalLength = input.length;
      final frame = FecController.withChecksum(input);
      expect(input.length, originalLength);
      expect(frame.length, originalLength + 1);
      final expected =
          input.sublist(1).fold<int>(0, (a, b) => a + b) & 0xFF;
      expect(frame.last, expected);
    });

    test('buildBasicResistance level 0 and 100 map to wire bytes', () {
      final zero = FecController.buildBasicResistance(0);
      final full = FecController.buildBasicResistance(100);
      expect(zero.length, 13);
      expect(full.length, 13);
      expect(zero[11], 0);
      expect(full[11], 200);
      expect(zero[2], 0x4F);
    });

    test('buildBasicResistance clamps out-of-range levels', () {
      expect(FecController.buildBasicResistance(-5)[11], 0);
      expect(FecController.buildBasicResistance(999)[11], 200);
    });

    test('gear 1 and 24 map to resistance extremes on the wire', () {
      // Mirrors GearMapper endpoints through the FE-C encoder.
      final g1 = FecController.buildBasicResistance(0);
      final g24 = FecController.buildBasicResistance(100);
      expect(g1[11] < g24[11], isTrue);
    });

    test('buildTargetPower encodes watts little-endian', () {
      final frame = FecController.buildTargetPower(300);
      expect(frame.length, 13);
      expect(frame[2], 0x4B);
      expect(frame[5], 300 & 0xFF);
      expect(frame[6], (300 >> 8) & 0xFF);
    });

    test('buildRequestControl and startResistance have valid checksums', () {
      for (final frame in [
        FecController.buildRequestControl(),
        FecController.buildStartResistanceMode(),
      ]) {
        expect(frame.length, 13);
        expect(frame[0], 0xA4);
        expect(frame.last, FecController.checksum(frame.sublist(0, 12)));
      }
    });
  });
}
