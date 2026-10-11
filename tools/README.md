# tools/

Reverse-engineering helpers for ShiftR. Not part of the Flutter app.

## ble_scanner.py

Standalone BLE discovery script used once to map the ThinkRider X2 Max protocol.

```bash
pip install -r requirements.txt
python ble_scanner.py --scan 8 --listen 45
```

What it does:

1. Scans BLE devices and picks the strongest ThinkRider match.
2. Connects and lists all GATT services / characteristics / descriptors.
3. Subscribes to every notify/indicate characteristic for `--listen` seconds.
4. Prints a notification summary (counts + hex samples).

During phase 4, press the VS200 shifter buttons several times so the
gear-data characteristic shows up in the log.

> Results are documented in `../docs/protocol.md`. This script is kept for
> reproducibility; the app itself uses `flutter_blue_plus`, not `bleak`.
