import 'package:flutter_test/flutter_test.dart';
import 'package:shiftr_ble/models/gear_mapper.dart';

void main() {
  group('GearMapper', () {
    test('gear 1 maps to resistance 0', () {
      expect(GearMapper.gearToResistance(1), 0);
    });

    test('gear 24 maps to resistance 100', () {
      expect(GearMapper.gearToResistance(24), 100);
    });

    test('gear values are clamped between 1 and 24', () {
      expect(GearMapper.clampGear(0), 1);
      expect(GearMapper.clampGear(25), 24);
      expect(GearMapper.clampGear(12), 12);
    });

    test('higher gears have higher resistance', () {
      var prev = GearMapper.gearToResistance(1);
      for (var g = 2; g <= 24; g++) {
        final cur = GearMapper.gearToResistance(g);
        expect(cur >= prev, isTrue, reason: 'gear $g should be >= gear ${g - 1}');
        prev = cur;
      }
    });

    test('all shifting presets span 0..100', () {
      for (final step in [0.05, 0.08, 0.12]) {
        expect(GearMapper.gearToResistance(1, step), 0);
        expect(GearMapper.gearToResistance(24, step), 100);
      }
    });

    test('mid gear scales with step sensitivity', () {
      final slight = GearMapper.gearToResistance(12, 0.05);
      final sprint = GearMapper.gearToResistance(12, 0.12);
      expect(slight, isNot(equals(sprint)));
    });

    test('gearLabel returns clamped gear string', () {
      expect(GearMapper.gearLabel(1), '1');
      expect(GearMapper.gearLabel(24), '24');
      expect(GearMapper.gearLabel(0), '1');
    });
  });
}
