import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'screens/connect_screen.dart';
import 'services/ftms_service.dart';

void main() {
  runApp(const ShiftRApp());
}

class ShiftRApp extends StatefulWidget {
  const ShiftRApp({super.key});

  @override
  State<ShiftRApp> createState() => _ShiftRAppState();
}

class _ShiftRAppState extends State<ShiftRApp> {
  final TrainerService _ftmsService = TrainerService();

  @override
  void initState() {
    super.initState();
    FlutterBluePlus.setLogLevel(LogLevel.info);
  }

  @override
  void dispose() {
    _ftmsService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appTitle,
      debugShowCheckedModeBanner: false,
      theme: buildShiftRTheme(),
      home: ConnectScreen(ftmsService: _ftmsService),
    );
  }
}
