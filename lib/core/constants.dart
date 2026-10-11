/// Centralized constants for ShiftR.
///
/// BLE UUIDs, FE-C framing, speed model and timeouts live here so the
/// protocol is documented in one place (see `docs/protocol.md`).
library;

/// BLE GATT UUIDs (short form, 16-bit core + vendor).
class BleUuids {
  static const cyclingPowerService = '00001818-0000-1000-8000-00805f9b34fb';
  static const powerMeasurement = '00002a63-0000-1000-8000-00805f9b34fb';
  static const cscService = '00001816-0000-1000-8000-00805f9b34fb';
  static const cscMeasurement = '00002a5b-0000-1000-8000-00805f9b34fb';
  static const customControlService = '0000fff0-0000-1000-8000-00805f9b34fb';
  static const controlWrite = '0000fff1-0000-1000-8000-00805f9b34fb';
  static const controlNotify = '0000fff4-0000-1000-8000-00805f9b34fb';
  static const fecService = '6e40fec1-b5a3-f393-e0a9-e50e24dcca9e';
  static const fecWrite = '6e40fec3-b5a3-f393-e0a9-e50e24dcca9e';
  static const fecNotify = '6e40fec2-b5a3-f393-e0a9-e50e24dcca9e';
}

/// ANT+ FE-C framing constants.
class FecConstants {
  static const header = 0xA4;
  static const length = 0x09;
  static const pageBasicResistance = 0x4F;
  static const pageTargetPower = 0x4B;
  static const pageCommandStatus = 0x00;
  static const dataPage = 0x05;
  static const dataByte = 0x30;
  static const fill = 0xFF;
}

/// Virtual speed model: speed = cadence * 0.06 * gearRatio * wheelCirc.
class SpeedModel {
  static const minGearRatio = 1.0;
  static const maxGearRatio = 4.54;
  static const wheelCircumferenceM = 2.1;
  static const maxCadenceRpm = 200.0;

  static double gearRatio(int gear, {int minGear = 1, int maxGear = 24}) {
    return 1.0 + (gear - 1) * (maxGearRatio - minGearRatio) / (maxGear - minGear);
  }
}

/// Timeouts and method-channel names.
class AppConstants {
  static const scanTimeout = Duration(seconds: 10);
  static const connectTimeout = Duration(seconds: 15);
  static const virtualTrainerChannel = 'com.shiftr/virtual_trainer';
  static const appTitle = 'ShiftR';
}

/// Shifting sensitivity presets shown in the UI.
class ShiftingPresets {
  static const slight = 0.05;
  static const moderate = 0.08;
  static const sprint = 0.12;
}
