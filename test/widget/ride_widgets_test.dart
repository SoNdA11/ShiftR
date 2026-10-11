import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftr_ble/models/trainer_data.dart';
import 'package:shiftr_ble/widgets/gear_display.dart';
import 'package:shiftr_ble/widgets/shifter_buttons.dart';
import 'package:shiftr_ble/widgets/trainer_stats.dart';

void main() {
  group('GearDisplay', () {
    testWidgets('shows gear number with semantics', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: GearDisplay(gear: 12))));
      expect(find.text('12'), findsOneWidget);
      expect(find.text('GEAR'), findsOneWidget);
      expect(
          find.bySemanticsLabel(RegExp('Current gear 12')), findsOneWidget);
    });
  });

  group('ShifterButtons', () {
    testWidgets('calls shift callbacks when enabled', (tester) async {
      var up = 0;
      var down = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ShifterButtons(
                  onShiftUp: () => up++,
                  onShiftDown: () => down++))));
      await tester.tap(find.text('SHIFT UP'));
      await tester.tap(find.text('SHIFT DOWN'));
      expect(up, 1);
      expect(down, 1);
    });

    testWidgets('disables buttons when not enabled', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ShifterButtons(
                  onShiftUp: () {},
                  onShiftDown: () {},
                  enabled: false))));
      final buttons =
          tester.widgetList<ElevatedButton>(find.byType(ElevatedButton));
      expect(buttons.every((b) => b.onPressed == null), isTrue);
    });
  });

  group('TrainerStats', () {
    testWidgets('renders power, cadence and speed', (tester) async {
      const data =
          TrainerData(power: 200, cadence: 90, speed: 32.5);
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: TrainerStats(data: data))));
      expect(find.text('200'), findsOneWidget);
      expect(find.text('90'), findsOneWidget);
      expect(find.text('32.5'), findsOneWidget);
      expect(find.text('POWER'), findsOneWidget);
      expect(find.text('CADENCE'), findsOneWidget);
      expect(find.text('SPEED'), findsOneWidget);
    });
  });
}
