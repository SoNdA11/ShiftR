import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shiftr_ble/core/constants.dart';
import 'package:shiftr_ble/models/gear_mapper.dart';
import 'package:shiftr_ble/models/trainer_data.dart';
import 'package:shiftr_ble/services/ftms_service.dart';
import 'package:shiftr_ble/services/virtual_trainer_server.dart';
import 'package:shiftr_ble/widgets/gear_display.dart';
import 'package:shiftr_ble/widgets/shifter_buttons.dart';
import 'package:shiftr_ble/widgets/trainer_stats.dart';

class RideScreen extends StatefulWidget {
  final TrainerService ftmsService;
  final String deviceName;

  const RideScreen({
    super.key,
    required this.ftmsService,
    required this.deviceName,
  });

  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> {
  TrainerData _trainerData = const TrainerData();
  bool _connected = true;
  VirtualServerStatus _virtualStatus = const VirtualServerStatus(VirtualServerState.idle);
  StreamSubscription? _dataSub;
  StreamSubscription? _connectionSub;
  StreamSubscription? _virtualSub;

  @override
  void initState() {
    super.initState();
    _trainerData = TrainerData(
      gear: widget.ftmsService.gear,
      resistance: GearMapper.gearToResistance(
        widget.ftmsService.gear,
        widget.ftmsService.shiftingStep,
      ),
    );
    _dataSub = widget.ftmsService.dataStream.listen(_onTrainerData);
    _connectionSub =
        widget.ftmsService.connectionStateStream.listen(_onConnectionState);
    _virtualSub = widget.ftmsService.virtualServerState.listen((s) {
      if (mounted) setState(() => _virtualStatus = s);
    });
  }

  @override
  void dispose() {
    _dataSub?.cancel();
    _connectionSub?.cancel();
    _virtualSub?.cancel();
    super.dispose();
  }

  void _onConnectionState(BtConnectionState state) {
    if (!mounted) return;
    if (state == BtConnectionState.disconnected) {
      setState(() => _connected = false);
      _showSnack('Trainer disconnected');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  void _onTrainerData(TrainerData data) {
    if (mounted) {
      setState(() => _trainerData = data);
    }
  }

  void _shiftUp() {
    widget.ftmsService.setGear(_trainerData.gear + 1);
  }

  void _shiftDown() {
    widget.ftmsService.setGear(_trainerData.gear - 1);
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _connected ? Colors.green : Colors.red,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.deviceName,
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
                  ),
                  const SizedBox(width: 16),
                  _buildVirtualBadge(),
                ],
              ),
              const SizedBox(height: 32),
              TrainerStats(data: _trainerData),
              const SizedBox(height: 32),
              GearDisplay(gear: _trainerData.gear),
              const SizedBox(height: 12),
              Text(
                'Resistance: ${_trainerData.resistance}%',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                  fontFamily: 'monospace',
                ),
              ),
              const Spacer(),
              _buildShiftingStepSelector(),
              const Spacer(),
              ShifterButtons(
                onShiftUp: _shiftUp,
                onShiftDown: _shiftDown,
                enabled: widget.ftmsService.hasControl && _connected,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _disconnect,
                  icon: const Icon(Icons.link_off),
                  label: const Text('DISCONNECT'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShiftingStepSelector() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'SHIFTING SENSITIVITY (STEP)',
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 10,
            letterSpacing: 1.5,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildStepButton(ShiftingPresets.slight, '5%', 'Slight'),
            const SizedBox(width: 12),
            _buildStepButton(ShiftingPresets.moderate, '8%', 'Moderate'),
            const SizedBox(width: 12),
            _buildStepButton(ShiftingPresets.sprint, '12%', 'Sprint'),
          ],
        ),
      ],
    );
  }

  Widget _buildStepButton(double step, String label, String subtitle) {
    final isSelected = widget.ftmsService.shiftingStep == step;
    final color = step == ShiftingPresets.slight
        ? Colors.blueAccent
        : step == ShiftingPresets.moderate
            ? Colors.greenAccent
            : Colors.orangeAccent;

    return GestureDetector(
      onTap: () {
        setState(() {
          widget.ftmsService.setShiftingStep(step);
        });
        _showSnack('Shifting step set to $label ($subtitle)');
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.12) : Colors.grey[950],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.grey[900]!,
            width: isSelected ? 2.0 : 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[400],
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: isSelected ? color : Colors.grey[600],
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _disconnect() {
    widget.ftmsService.disconnect();
    Navigator.pop(context);
  }

  Widget _buildVirtualBadge() {
    final status = _virtualStatus;
    String label;
    Color color;

    if (status.hasError) {
      label = status.error!;
      color = Colors.redAccent;
    } else {
      switch (status.state) {
        case VirtualServerState.idle:
          label = 'offline';
          color = Colors.grey;
        case VirtualServerState.starting:
        case VirtualServerState.ready:
          label = 'starting…';
          color = Colors.yellowAccent;
        case VirtualServerState.advertising:
          label = 'advertising';
          color = Colors.greenAccent;
        case VirtualServerState.connected:
          label = 'PC connected';
          color = Colors.greenAccent;
        case VirtualServerState.error:
          label = 'error';
          color = Colors.redAccent;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontFamily: 'monospace'),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
