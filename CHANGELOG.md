# Changelog

All notable changes to ShiftR are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [1.0.1+2] — 2026-10-11

### Changed

- Promoted Flutter project to repo root (`shiftr_ble/` → `.`).
- Moved BLE reverse-engineering script to `tools/ble_scanner.py` (EN + `--scan`/`--listen`).
- Rewrote README, added `docs/protocol.md` + `docs/virtual_trainer.md`.
- Hardened `.gitignore` and `analysis_options.yaml`.
- Added Flutter CI (`analyze` + `test` + `apk`).
- Split `TrainerService` into `BleScanner` / `PowerParser` / `FecController` + facade; fixed FE-C checksum mutation, `dispose()` await, `print` → `debugPrint`, centralized constants/theme.
- Added unit + widget tests for parsing, FE-C encoding and gear mapping.
