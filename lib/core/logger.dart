import 'package:flutter/foundation.dart';

/// Tiny logger wrapper so production code never calls `print` directly
/// (enforced by `avoid_print` lint).
void logInfo(Object? message) => debugPrint('[ShiftR] $message');

void logError(String context, Object error) =>
    debugPrint('[ShiftR:$context] error: $error');
