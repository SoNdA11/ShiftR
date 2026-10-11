import 'dart:async';
import 'package:flutter/services.dart';
import '../core/constants.dart';
import '../core/logger.dart';

enum VirtualServerState { idle, starting, ready, advertising, connected, error }

class VirtualServerStatus {
  final VirtualServerState state;
  final String? error;
  const VirtualServerStatus(this.state, {this.error});
  bool get hasError => error != null;
}

class VirtualTrainerServer {
  static const _channel =
      MethodChannel(AppConstants.virtualTrainerChannel);

  final _stateController = StreamController<VirtualServerStatus>.broadcast();
  Stream<VirtualServerStatus> get stateStream => _stateController.stream;

  bool _started = false;
  bool get isStarted => _started;

  void Function(int resistance)? onResistanceRequest;
  void Function(int power)? onTargetPowerRequest;

  Future<void> start({String? trainerName}) async {
    if (_started) return;
    _stateController.add(VirtualServerStatus(VirtualServerState.starting));
    _channel.setMethodCallHandler(_handleMethodCall);
    try {
      await _channel.invokeMethod('start', {'trainerName': trainerName});
      _started = true;
      _stateController.add(VirtualServerStatus(VirtualServerState.ready));
    } catch (e) {
      _stateController.add(VirtualServerStatus(VirtualServerState.error, error: 'start failed: $e'));
    }
  }

  Future<void> stop() async {
    if (!_started) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      logError('VirtualTrainerServer.stop', e);
    } finally {
      _channel.setMethodCallHandler(null);
    }
    _started = false;
    _stateController.add(VirtualServerStatus(VirtualServerState.idle));
  }

  Future<void> updateData({
    required int power,
    required double cadence,
    required double speed,
  }) async {
    if (!_started) return;
    try {
      await _channel.invokeMethod('updateData', {
        'power': power,
        'cadence': cadence,
        'speed': speed,
      });
    } catch (e) {
      logError('VirtualTrainerServer.updateData', e);
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onReady':
        _stateController.add(VirtualServerStatus(VirtualServerState.ready));
      case 'onAdvertising':
        final success = call.arguments as bool;
        _stateController.add(VirtualServerStatus(
          success ? VirtualServerState.advertising : VirtualServerState.error,
          error: success ? null : 'advertising rejected',
        ));
      case 'onConnected':
        _stateController.add(VirtualServerStatus(VirtualServerState.connected));
      case 'onDisconnected':
        _stateController.add(VirtualServerStatus(VirtualServerState.advertising));
      case 'onResistanceRequest':
        onResistanceRequest?.call(call.arguments as int);
      case 'onTargetPowerRequest':
        onTargetPowerRequest?.call(call.arguments as int);
      case 'onError':
        final err = call.arguments as String? ?? 'unknown error';
        _stateController.add(VirtualServerStatus(VirtualServerState.error, error: err));
      case 'onLog':
        logInfo('VirtualTrainerServer: ${call.arguments}');
    }
  }

  void dispose() {
    _stateController.close();
  }
}
