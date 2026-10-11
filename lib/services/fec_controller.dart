import '../core/constants.dart';

/// Pure ANT+ FE-C frame builders (no BLE dependency).
///
/// Frames are 13-byte ANT packets: `[0xA4, len, page, …, checksum]`
/// with `checksum = bytes[1..11].sum() & 0xFF`.
/// Builders never mutate their input — checksum is appended to a copy.
/// See `docs/protocol.md`.
class FecController {
  /// Checksum over bytes 1..end (excludes header 0xA4, excludes checksum).
  static int checksum(List<int> bytesWithoutChecksum) {
    return bytesWithoutChecksum.sublist(1).fold<int>(0, (a, b) => a + b) & 0xFF;
  }

  /// Returns a new 13-byte frame with checksum appended.
  static List<int> withChecksum(List<int> bytesWithoutChecksum) {
    final frame = [...bytesWithoutChecksum];
    frame.add(checksum(bytesWithoutChecksum));
    return frame;
  }

  /// Basic Resistance page (0x4F). [level] 0–100 → wire byte `(level*2).clamp(0,200)`.
  static List<int> buildBasicResistance(int level) {
    final b = level.clamp(0, 100);
    final newtons = (b * 2).clamp(0, 200);
    return withChecksum([
      FecConstants.header,
      FecConstants.length,
      FecConstants.pageBasicResistance,
      FecConstants.dataPage,
      FecConstants.dataByte,
      FecConstants.fill,
      FecConstants.fill,
      FecConstants.fill,
      FecConstants.fill,
      FecConstants.fill,
      FecConstants.fill,
      newtons,
    ]);
  }

  /// Target Power page (0x4B), power in watts (u16 LE).
  static List<int> buildTargetPower(int power) {
    final p = power.clamp(0, 65535);
    return withChecksum([
      FecConstants.header,
      FecConstants.length,
      FecConstants.pageTargetPower,
      FecConstants.dataPage,
      FecConstants.dataByte,
      (p & 0xFF),
      ((p >> 8) & 0xFF),
      FecConstants.fill,
      FecConstants.fill,
      FecConstants.fill,
      FecConstants.fill,
      FecConstants.fill,
    ]);
  }

  /// Request-control page (0x00).
  static List<int> buildRequestControl() {
    return withChecksum([
      FecConstants.header,
      FecConstants.length,
      FecConstants.pageCommandStatus,
      0x01,
      0x00,
      FecConstants.fill,
      FecConstants.fill,
      FecConstants.fill,
      FecConstants.fill,
      FecConstants.fill,
      FecConstants.fill,
      0x00,
    ]);
  }

  /// Start-resistance-mode page (0x4F with 0x00 load).
  static List<int> buildStartResistanceMode() {
    return withChecksum([
      FecConstants.header,
      FecConstants.length,
      FecConstants.pageBasicResistance,
      FecConstants.dataPage,
      FecConstants.dataByte,
      FecConstants.fill,
      FecConstants.fill,
      FecConstants.fill,
      FecConstants.fill,
      FecConstants.fill,
      FecConstants.fill,
      0x00,
    ]);
  }
}
