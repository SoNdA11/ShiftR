import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../core/constants.dart';
import '../services/ftms_service.dart';
import 'ride_screen.dart';

class ConnectScreen extends StatefulWidget {
  final TrainerService ftmsService;

  const ConnectScreen({super.key, required this.ftmsService});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  List<ScanResult> _devices = [];
  bool _isScanning = false;
  bool _btReady = false;
  bool _permissionsGranted = false;
  String? _connectingDeviceId;
  bool _scanInitiated = false;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _btStateSub;
  StreamSubscription? _connectionStateSub;

  @override
  void initState() {
    super.initState();
    _initBtState();
    unawaited(_initPermissionsAndScan());
  }

  Future<void> _initPermissionsAndScan() async {
    _permissionsGranted = await widget.ftmsService.requestPermissions();
    if (_btReady && _permissionsGranted && mounted) {
      unawaited(_startScan(showMessages: false));
    }
  }

  void _initBtState() {
    _btStateSub = widget.ftmsService.bluetoothState.listen((state) {
      if (!mounted) return;
      final nowReady = state == BluetoothAdapterState.on;
      final wasNotReady = !_btReady;
      setState(() => _btReady = nowReady);
      if (nowReady && wasNotReady && _permissionsGranted) {
        unawaited(_startScan(showMessages: false));
      }
    });
  }

  Future<void> _startScan({bool showMessages = true}) async {
    if (!_btReady || !_permissionsGranted || _scanInitiated) return;
    _scanInitiated = true;

    setState(() {
      _isScanning = true;
      _devices = [];
    });

    await _scanSubscription?.cancel();
    _scanSubscription = widget.ftmsService.scanDevices().listen((results) {
      if (mounted) {
        for (final r in results) {
          debugPrint('ScanResult: ${r.device.platformName} (${r.device.remoteId}) rssi=${r.rssi}');
        }
        setState(() => _devices = results);
      }
    });

    await widget.ftmsService.startScan(timeout: AppConstants.scanTimeout);

    if (mounted) {
      setState(() => _isScanning = false);
      if (_devices.isEmpty && showMessages) {
        _showSnack('No trainers found nearby');
      }
    }
    _scanInitiated = false;
  }

  Future<void> _connect(ScanResult result) async {
    if (_connectingDeviceId != null) return;
    setState(() => _connectingDeviceId = result.device.remoteId.str);

    await _connectionStateSub?.cancel();
    _connectionStateSub =
        widget.ftmsService.connectionStateStream.listen((state) {
      if (!mounted) return;
      switch (state) {
        case BtConnectionState.connected:
          _navigateToRide(result.device.platformName);
          break;
        case BtConnectionState.failed:
          setState(() => _connectingDeviceId = null);
          _showSnack('Failed to connect to ${result.device.platformName}');
          break;
        case BtConnectionState.disconnected:
          setState(() => _connectingDeviceId = null);
          break;
        default:
          break;
      }
    });

    await widget.ftmsService.connect(result.device);
  }

  void _navigateToRide(String deviceName) {
    setState(() => _connectingDeviceId = null);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RideScreen(
          ftmsService: widget.ftmsService,
          deviceName: deviceName,
        ),
      ),
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _btStateSub?.cancel();
    _connectionStateSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Connect Trainer'),
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        actions: [
          if (_isScanning)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () { _scanInitiated = false; _startScan(); },
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_permissionsGranted) {
      return _buildErrorState(
        icon: Icons.shield_outlined,
        message: 'Bluetooth permissions required',
        actionLabel: 'Grant permissions',
        onAction: () async {
          _permissionsGranted = await widget.ftmsService.requestPermissions();
          if (mounted) setState(() {});
        },
      );
    }

    if (!_btReady) {
      return _buildErrorState(
        icon: Icons.bluetooth_disabled,
        message: 'Bluetooth is off',
        subtitle: 'Turn on Bluetooth to find your trainer',
      );
    }

    if (_isScanning && _devices.isEmpty) {
      return _buildScanningState();
    }

    if (_devices.isEmpty) {
      return _buildErrorState(
        icon: Icons.bluetooth_searching,
        message: 'No trainers found',
        subtitle: 'Make sure your trainer is on and nearby',
        actionLabel: 'Scan again',
        onAction: () { _scanInitiated = false; _startScan(); },
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: _devices.length,
      itemBuilder: (context, index) {
        final result = _devices[index];
        final device = result.device;
        final isConnecting = _connectingDeviceId == device.remoteId.str;
        final name = device.platformName.isNotEmpty
            ? device.platformName
            : 'Unknown Device';

        return Card(
          color: isConnecting ? Colors.grey[850] : Colors.grey[900],
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: Stack(
              children: [
                Icon(Icons.bluetooth, color: Colors.blue[400], size: 32),
                if (isConnecting)
                  const Positioned.fill(
                    child: Center(
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            ),
            title: Text(
              name,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            ),
            subtitle: Row(
              children: [
                _rssiIndicator(result.rssi),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    device.remoteId.str.length > 17
                        ? '${device.remoteId.str.substring(0, 17)}…'
                        : device.remoteId.str,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey[600], fontSize: 11),
                  ),
                ),
              ],
            ),
            trailing: isConnecting
                ? Text('Connecting…', style: TextStyle(color: Colors.blue[300], fontSize: 12))
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'FTMS',
                      style: TextStyle(color: Colors.green[400], fontSize: 11),
                    ),
                  ),
            onTap: isConnecting ? null : () => _connect(result),
          ),
        );
      },
    );
  }

  Widget _rssiIndicator(int rssi) {
    final bars = rssi > -50
        ? 4
        : rssi > -70
            ? 3
            : rssi > -85
                ? 2
                : 1;
    return Row(
      children: List.generate(4, (i) {
        return Container(
          width: 3,
          height: 4 + i * 3.5,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: i < bars ? Colors.green[400] : Colors.grey[800],
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }

  Widget _buildScanningState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 24),
          Text(
            'Scanning for trainers…',
            style: TextStyle(color: Colors.grey[400], fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Make sure your trainer is on',
            style: TextStyle(color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState({
    required IconData icon,
    required String message,
    String? subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Colors.grey[700]),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(color: Colors.grey[500], fontSize: 18),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey[700]),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: onAction,
                child: Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
