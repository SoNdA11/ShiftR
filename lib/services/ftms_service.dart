import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../core/constants.dart';
import '../core/logger.dart';
import '../models/trainer_data.dart';
import '../models/gear_mapper.dart';
import 'ble_scanner.dart';
import 'fec_controller.dart';
import 'power_parser.dart';
import 'virtual_trainer_server.dart';

export 'ble_scanner.dart';
export 'fec_controller.dart';
export 'power_parser.dart';

enum BtConnectionState { disconnected, connecting, connected, failed }

/// Facade over BLE scanning, measurement parsing, FE-C control and the
/// virtual FTMS bridge. Pure parsing/encoding lives in [PowerParser] and
/// [FecController] (unit-tested); this class owns BLE subscriptions only.
class TrainerService {
  static final Guid cyclingPowerService =
      Guid(BleUuids.cyclingPowerService);
  static final Guid powerMeasurementChar =
      Guid(BleUuids.powerMeasurement);
  static final Guid cscService = Guid(BleUuids.cscService);
  static final Guid cscMeasurementChar =
      Guid(BleUuids.cscMeasurement);
  static final Guid customControlService =
      Guid(BleUuids.customControlService);
  static final Guid controlWriteChar =
      Guid(BleUuids.controlWrite);
  static final Guid controlNotifyChar =
      Guid(BleUuids.controlNotify);
  static final Guid fecService = Guid(BleUuids.fecService);
  static final Guid fecWriteChar = Guid(BleUuids.fecWrite);
  static final Guid fecNotifyChar = Guid(BleUuids.fecNotify);

  final StreamController<TrainerData> _dataController =
      StreamController<TrainerData>.broadcast();
  final StreamController<BtConnectionState> _connectionController =
      StreamController<BtConnectionState>.broadcast();
  final BleScanner _bleScanner = BleScanner();

  BluetoothDevice? _device;
  StreamSubscription? _connectionSub;
  StreamSubscription? _powerSub;
  StreamSubscription? _cscSub;
  StreamSubscription? _controlNotifySub;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _fecWriteChar;
  bool _hasControl = false;
  final VirtualTrainerServer _virtualServer = VirtualTrainerServer();

  // Internal states
  int _gear = 1;
  double _shiftingStep = ShiftingPresets.moderate;
  int _currentPower = 0;
  double _currentCadence = 0.0;

  int? _lastCrankRevs;
  int? _lastCrankTime;
  int? _lastCscCrankRevs;
  int? _lastCscCrankTime;

  Stream<TrainerData> get dataStream => _dataController.stream;
  Stream<BtConnectionState> get connectionStateStream =>
      _connectionController.stream;
  Stream<VirtualServerStatus> get virtualServerState =>
      _virtualServer.stateStream;
  Stream<BluetoothAdapterState> get bluetoothState =>
      _bleScanner.adapterState();
  bool get hasControl => _hasControl;

  int get gear => _gear;
  double get shiftingStep => _shiftingStep;

  void setGear(int newGear) {
    _gear = GearMapper.clampGear(newGear);
    _updateResistance();
  }

  void setShiftingStep(double step) {
    _shiftingStep = step;
    _updateResistance();
  }

  void _updateResistance() {
    final resistance = GearMapper.gearToResistance(_gear, _shiftingStep);
    unawaited(setResistance(resistance));
    _updateTrainerDataInternal(fullUpdate: true);
  }

  void _updateTrainerDataInternal({bool fullUpdate = false}) {
    final gearRatio = SpeedModel.gearRatio(_gear);
    final speed =
        _currentCadence * 0.06 * gearRatio * SpeedModel.wheelCircumferenceM;

    final trainerData = TrainerData(
      speed: speed,
      cadence: _currentCadence,
      power: _currentPower,
      gear: _gear,
      resistance: GearMapper.gearToResistance(_gear, _shiftingStep),
    );

    _dataController.add(trainerData);
    if (fullUpdate) {
      unawaited(_virtualServer.updateData(
        power: _currentPower,
        cadence: _currentCadence,
        speed: speed,
      ));
    }
  }

  Future<bool> requestPermissions() => _bleScanner.requestPermissions();

  Stream<List<ScanResult>> scanDevices() => _bleScanner.scanResults();

  Future<void> startScan({Duration timeout = AppConstants.scanTimeout}) {
    return _bleScanner.startScan(timeout: timeout);
  }

  Future<void> connect(BluetoothDevice device) async {
    _connectionController.add(BtConnectionState.connecting);
    _device = device;

    try {
      await _connectionSub?.cancel();
      _connectionSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _connectionController.add(BtConnectionState.disconnected);
        }
      });

      await device.connect(
          license: License.nonprofit, timeout: AppConstants.connectTimeout);
      _connectionController.add(BtConnectionState.connected);

      // Reset state for new session
      _gear = 1;
      _currentPower = 0;
      _currentCadence = 0.0;
      _lastCrankRevs = null;
      _lastCrankTime = null;
      _lastCscCrankRevs = null;
      _lastCscCrankTime = null;

      await _discoverAndSetup();

      // Forward FTMS Control Point requests from Zwift/Argus back to ThinkRider
      _virtualServer.onResistanceRequest = (resistance) {
        logInfo('FTMS→FE-C: set resistance to $resistance');
        unawaited(setResistance(resistance));
        _updateTrainerDataInternal(fullUpdate: true);
      };
      _virtualServer.onTargetPowerRequest = (power) {
        logInfo('FTMS→FE-C: set target power to $power');
        _sendFecFrame(FecController.buildTargetPower(power));
        _updateTrainerDataInternal(fullUpdate: true);
      };

      // Initialize resistance on trainer
      _updateResistance();

      final name = device.platformName.isNotEmpty ? device.platformName : null;
      await _virtualServer.start(trainerName: name);
    } catch (e) {
      logError('TrainerService.connect', e);
      _connectionController.add(BtConnectionState.failed);
      _device = null;
    }
  }

  Future<void> _discoverAndSetup() async {
    if (_device == null) return;
    final services = await _device!.discoverServices();

    for (final service in services) {
      if (service.uuid == cyclingPowerService) {
        for (final char in service.characteristics) {
          if (char.uuid == powerMeasurementChar) {
            await char.setNotifyValue(true);
            _powerSub = char.onValueReceived.listen(_onPowerMeasurement);
            logInfo('Subscribed to Cycling Power Measurement');
          }
        }
      }

      if (service.uuid == cscService) {
        for (final char in service.characteristics) {
          if (char.uuid == cscMeasurementChar) {
            await char.setNotifyValue(true);
            _cscSub = char.onValueReceived.listen(_onCscMeasurement);
            logInfo('Subscribed to CSC Measurement');
          }
        }
      }

      if (service.uuid == customControlService) {
        for (final char in service.characteristics) {
          if (char.uuid == controlWriteChar) {
            _writeChar = char;
          }
          if (char.uuid == controlNotifyChar) {
            await char.setNotifyValue(true);
            _controlNotifySub =
                char.onValueReceived.listen(_onControlNotification);
            logInfo('Subscribed to control notification');
          }
        }
      }

      if (service.uuid == fecService) {
        for (final char in service.characteristics) {
          if (char.uuid == fecWriteChar) {
            _fecWriteChar = char;
            logInfo('Found FE-C write char (FEC3)');
          }
          if (char.uuid == fecNotifyChar) {
            await char.setNotifyValue(true);
            logInfo('Found FE-C notify char (FEC2)');
          }
        }
      }
    }

    _hasControl = _fecWriteChar != null;
    if (_hasControl) {
      logInfo('FE-C control available via FEC3');
    }
  }

  void _onPowerMeasurement(List<int> data) {
    final m = PowerParser.parsePowerMeasurement(data);
    _currentPower = m.power;

    if (m.hasCrank) {
      final cadence = PowerParser.cadenceFromDelta(
        revs: m.crankRevs!,
        time: m.crankTime!,
        lastRevs: _lastCrankRevs,
        lastTime: _lastCrankTime,
      );
      if (cadence != null) _currentCadence = cadence;
      _lastCrankRevs = m.crankRevs;
      _lastCrankTime = m.crankTime;
    }

    _updateTrainerDataInternal();
  }

  void _onCscMeasurement(List<int> data) {
    final crank = PowerParser.parseCscMeasurement(data);
    if (crank == null) return;

    final cadence = PowerParser.cadenceFromDelta(
      revs: crank.revs,
      time: crank.time,
      lastRevs: _lastCscCrankRevs,
      lastTime: _lastCscCrankTime,
    );
    if (cadence != null) _currentCadence = cadence;

    _lastCscCrankRevs = crank.revs;
    _lastCscCrankTime = crank.time;
    _updateTrainerDataInternal();
  }

  void _onControlNotification(List<int> data) {
    if (!PowerParser.isValidControlFrame(data)) {
      if (data.length >= 10) {
        logInfo('FFF4 CRC mismatch, dropping frame');
      }
      return;
    }

    final type = data[0];
    if (type == 0x19) {
      final status = data[7];
      if (status != 0x25) {
        logInfo('FFF4 type=0x19 status changed: 0x${status.toRadixString(16)}');
      }
    }
  }

  /// Sends a vendor command to FFF1 (reserved for future use).
  Future<void> sendCustomCommand(List<int> bytes) async {
    final char = _writeChar;
    if (char == null) return;
    try {
      await char.write(bytes, withoutResponse: false);
    } catch (e) {
      logError('TrainerService.sendCustomCommand', e);
    }
  }

  /// Writes an already-checksummed FE-C frame. Use [FecController] builders.
  Future<void> _sendFecFrame(List<int> frame) async {
    final char = _fecWriteChar;
    if (char == null) return;
    try {
      await char.write(frame, withoutResponse: false);
    } catch (e) {
      logError('TrainerService._sendFecFrame', e);
    }
  }

  Future<void> setResistance(int level) async {
    await _sendFecFrame(FecController.buildBasicResistance(level));
  }

  Future<void> requestControl() async {
    await _sendFecFrame(FecController.buildRequestControl());
    logInfo('FE-C: request control sent');
  }

  Future<void> startResistance() async {
    await _sendFecFrame(FecController.buildStartResistanceMode());
    logInfo('FE-C: resistance mode started');
  }

  Future<void> disconnect() async {
    await _virtualServer.stop();
    await _powerSub?.cancel();
    await _cscSub?.cancel();
    await _controlNotifySub?.cancel();
    await _connectionSub?.cancel();
    _powerSub = null;
    _cscSub = null;
    _controlNotifySub = null;
    _connectionSub = null;
    try {
      if (_device != null) await _device!.disconnect();
    } catch (e) {
      logError('TrainerService.disconnect', e);
    }
    _connectionController.add(BtConnectionState.disconnected);
    _device = null;
    _writeChar = null;
    _fecWriteChar = null;
    _hasControl = false;
    _lastCrankRevs = null;
    _lastCrankTime = null;
    _lastCscCrankRevs = null;
    _lastCscCrankTime = null;
  }

  void dispose() {
    unawaited(disconnect());
    _virtualServer.dispose();
    unawaited(_dataController.close());
    unawaited(_connectionController.close());
  }
}
