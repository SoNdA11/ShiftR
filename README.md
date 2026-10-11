# ShiftR

[![flutter](https://github.com/YOUR_USER/ShiftR/actions/workflows/flutter.yml/badge.svg)](https://github.com/YOUR_USER/ShiftR/actions/workflows/flutter.yml)

Virtual shifting for ThinkRider smart trainers via BLE FTMS.

ShiftR connects to a ThinkRider X2 Max over BLE, reads power/cadence, lets you
shift through 24 virtual gears, drives resistance via ANT+ FE-C, and
re-advertises the phone as a standard FTMS trainer so Zwift and similar apps
can connect to it.

```text
ThinkRider X2 Max ──BLE──▶ ShiftR (phone) ──BLE FTMS──▶ Zwift / Argus
```

## Supported hardware

- ThinkRider X2 Max trainer + VS200 shifter buttons (reverse-engineered protocol, see `docs/protocol.md`).
- Android phone with BLE + BLE advertising (GATT server). iOS/desktop are not supported for the virtual-trainer path.

## How it works

1. **Connect** — scan BLE, connect to the trainer (`0x1818/2A63` power, `0x1816/2A5B` CSC, `FFF0` custom, `6E40FECx` FE-C).
2. **Ride** — live power / cadence / virtual speed, gear 1–24, resistance %, shifting sensitivity 5/8/12 %.
3. **Shift** — SHIFT UP/DOWN sends FE-C Basic Resistance (`0x4F`) or Target Power (`0x4B`).
4. **Bridge** — the phone advertises CPS (`0x1818`) + FTMS (`0x1826`); FTMS Control Point writes (`0x04/0x05`) are forwarded back to the ThinkRider. See `docs/virtual_trainer.md`.

## Requirements

- Flutter 3.7+ (stable), Dart SDK `^3.7.2`.
- Android with Bluetooth on; grant Location + Bluetooth Scan/Connect/Advertise at runtime.
- Trainer powered on and nearby.

## Quickstart

```bash
flutter pub get
flutter run
```

Pairing flow: open the app → grant permissions → pick your trainer in the scan
list → ride. Keep the app in the foreground while Zwift connects to the phone.

Troubleshooting:

- No devices: trainer on? Bluetooth on? Permissions granted?
- Zwift can't see the phone: start a trainer session first, check the virtual badge (`advertising` / `PC connected`), see `docs/virtual_trainer.md`.
- No notifications: open ThinkRider tools, press VS200 buttons, re-run `tools/ble_scanner.py`.

## Project layout

```text
lib/                  # Flutter app (models, services, screens, widgets)
  core/               # constants, theme, logger
  services/           # ble_scanner, power_parser, fec_controller, trainer_service
android/…             # VirtualTrainerServer.kt + MainActivity.kt (FTMS GATT server)
tools/                # ble_scanner.py (bleak reverse-engineering helper)
docs/                 # protocol.md, virtual_trainer.md
test/                 # unit + widget tests
.github/workflows/    # flutter analyze + test + apk
```

## Tests & checks

```bash
flutter analyze --no-pub
flutter test --coverage
flutter build apk --debug
./checklist.sh
```

## Roadmap

- Parse `FEC2` notifications; correlate VS200 button frames.
- Auto-reconnect + retry; connection error states.
- More trainers / gear profiles.

## Contributing

PRs welcome. Run `flutter analyze` + `flutter test` before pushing; keep
`docs/protocol.md` in sync when touching BLE parsing.

## License

MIT — see [LICENSE](LICENSE).
