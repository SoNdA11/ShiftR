import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/constants.dart';

/// BLE permission + scan helpers extracted from `TrainerService`.
///
/// Keeps all `flutter_blue_plus` / `permission_handler` scan logic in one
/// place; connection + GATT setup stays in the facade.
class BleScanner {
  Future<bool> requestPermissions() async {
    if (Platform.isMacOS) return true;
    final statuses = await [
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  Stream<List<ScanResult>> scanResults() => FlutterBluePlus.scanResults;

  Stream<BluetoothAdapterState> adapterState() => FlutterBluePlus.adapterState;

  Future<void> startScan({Duration timeout = AppConstants.scanTimeout}) async {
    if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) return;
    await FlutterBluePlus.startScan(timeout: timeout);
  }
}
