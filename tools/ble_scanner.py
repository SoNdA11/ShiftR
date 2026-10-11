"""
ThinkRider X2 Max BLE Scanner.

Discovers all BLE services and characteristics of the trainer.
Run once to map the protocol, then use the findings to build the overlay.

Usage:
  pip install -r requirements.txt
  python ble_scanner.py [--scan 8] [--listen 45]

After connecting, press the VS200 buttons to see if any
characteristic changes its data.
"""

import argparse
import asyncio
import sys
from datetime import datetime

try:
    from bleak import BleakScanner, BleakClient
except ImportError:
    print("Run: pip install bleak")
    sys.exit(1)


# ── Defaults (overridable via CLI) ──────────────────────────────────────────
DEFAULT_SCAN_DURATION = 8    # seconds of BLE discovery
DEFAULT_LISTEN_DURATION = 45  # seconds listening for notifications
THINKRIDER_NAMES = ["thinkrider", "x2", "x2max", "x2 max", "tr"]
# ────────────────────────────────────────────────────────────────────────────


def ts():
    return datetime.now().strftime("%H:%M:%S.%f")[:-3]


def decode_value(data: bytes) -> str:
    """Decode bytes as hex + printable ascii."""
    hex_str = " ".join(f"{b:02x}" for b in data)
    try:
        ascii_str = data.decode("ascii", errors="replace")
        ascii_clean = "".join(c if c.isprintable() else "." for c in ascii_str)
        return f"hex=[{hex_str}] ascii=[{ascii_clean}]"
    except Exception:
        return f"hex=[{hex_str}]"


def is_thinkrider(name: str | None) -> bool:
    if not name:
        return False
    lower = name.lower()
    return any(n in lower for n in THINKRIDER_NAMES)


# ── Data collector ──────────────────────────────────────────────────────────
collected_data: dict[str, list] = {}
notification_count: dict[str, int] = {}


def on_notification(characteristic_uuid: str, data: bytes):
    """Called on every BLE notification."""
    uuid_lower = characteristic_uuid.lower()
    if uuid_lower not in collected_data:
        collected_data[uuid_lower] = []
        notification_count[uuid_lower] = 0

    notification_count[uuid_lower] += 1
    count = notification_count[uuid_lower]

    # Compact log: first 5, then every 10th
    if count <= 5 or count % 10 == 0:
        print(f"  [{ts()}] {characteristic_uuid} #{count}: {decode_value(data)}")

    collected_data[uuid_lower].append({
        "time": ts(),
        "hex": data.hex(),
        "bytes": list(data),
        "len": len(data),
    })


# ── Scan ────────────────────────────────────────────────────────────────────
async def scan_devices(scan_duration: int):
    print(f"\n{'='*60}")
    print(f"  [{ts()}] Scanning BLE devices ({scan_duration}s)...")
    print(f"{'='*60}\n")

    devices = await BleakScanner.discover(timeout=scan_duration)

    thinkrider_devices = []
    all_devices = []

    for d in devices:
        entry = {
            "name": d.name or "(unnamed)",
            "address": d.address,
            "rssi": d.rssi,
            "service_uuids": d.metadata.get("uuids", []),
        }
        all_devices.append(entry)
        if is_thinkrider(d.name):
            thinkrider_devices.append(entry)

    print(f"\n{'─'*60}")
    print(f"  ALL DEVICES FOUND ({len(all_devices)})")
    print(f"{'─'*60}")
    for d in sorted(all_devices, key=lambda x: x["rssi"], reverse=True):
        marker = " <<< THINKRIDER" if is_thinkrider(d["name"]) else ""
        services = ", ".join(d["service_uuids"][:5]) if d["service_uuids"] else "none"
        print(f"  {d['address']}  RSSI:{d['rssi']:>4}  {d['name']}{marker}")
        print(f"    Services: {services}")

    if not thinkrider_devices:
        print("\n  NO THINKRIDER FOUND!")
        print("  Check that the X2 Max is powered on and near the PC.")
        print("  If the name differs, add it to THINKRIDER_NAMES.")
        return None

    target = max(thinkrider_devices, key=lambda x: x["rssi"])
    print(f"\n{'='*60}")
    print(f"  TARGET: {target['name']} [{target['address']}]")
    print(f"{'='*60}")

    return target["address"]


# ── Connect + Discover Services ─────────────────────────────────────────────
async def discover_services(address: str, listen_duration: int):
    print(f"\n[{ts()}] Connecting to {address}...")

    async with BleakClient(address) as client:
        print(f"[{ts()}] Connected! Services:\n")

        services = client.services
        for service in services:
            print(f"  ┌─ Service: {service.uuid}")
            print(f"  │  Handle: {service.handle}")

            for char in service.characteristics:
                props = ", ".join(char.properties)
                print(f"  │  ┌─ Char: {char.uuid}")
                print(f"  │  │  Handle: {char.handle}")
                print(f"  │  │  Props: {props}")

                if "read" in char.properties:
                    try:
                        val = await client.read_gatt_char(char.uuid)
                        print(f"  │  │  Value: {decode_value(val)}")
                    except Exception as e:
                        print(f"  │  │  Read error: {e}")

                for desc in char.descriptors:
                    print(f"  │  │  Desc: {desc.uuid} (handle={desc.handle})")

                print("  │  └─")

            print("  └─")

        notify_chars = []
        for service in services:
            for char in service.characteristics:
                if "notify" in char.properties or "indicate" in char.properties:
                    notify_chars.append((service.uuid, char.uuid))

        if notify_chars:
            print(f"\n{'='*60}")
            print(f"  SUBSCRIBING TO {len(notify_chars)} NOTIFY CHARACTERISTICS")
            print(f"{'='*60}")

            for service_uuid, char_uuid in notify_chars:
                try:
                    def callback(sender, data, cu=char_uuid):
                        on_notification(cu, data)

                    await client.start_notify(char_uuid, callback)
                    print(f"  [OK] {char_uuid}")
                except Exception as e:
                    print(f"  [ERROR] {char_uuid}: {e}")

            print(f"\n{'='*60}")
            print(f"  LISTENING ({listen_duration}s)")
            print("  >>> PRESS THE VS200 BUTTONS NOW! <<<")
            print("  >>> Shift up/down several times! <<<")
            print(f"{'='*60}\n")

            await asyncio.sleep(listen_duration)

            for service_uuid, char_uuid in notify_chars:
                try:
                    await client.stop_notify(char_uuid)
                except Exception:
                    pass
        else:
            print("\n  NO NOTIFY CHARACTERISTICS FOUND")

        print(f"\n{'='*60}")
        print("  NOTIFICATION SUMMARY")
        print(f"{'='*60}")

        if notification_count:
            for uuid, count in sorted(notification_count.items(), key=lambda x: x[1], reverse=True):
                samples = collected_data[uuid][:3]
                sample_hex = ", ".join(s["hex"][:30] for s in samples)
                print(f"  {uuid}: {count} notifications")
                print(f"    Samples: {sample_hex}")
        else:
            print("  No notifications received.")
            print("  Possible causes:")
            print("  - VS200 is not connected to the X2 Max right now")
            print("  - The protocol does not use notifications")
            print("  - Try: ThinkRider tools open + press buttons")


# ── Main ────────────────────────────────────────────────────────────────────
async def main(scan_duration: int, listen_duration: int):
    print("""
╔══════════════════════════════════════════════════════════╗
║        ThinkRider X2 Max - BLE Service Scanner          ║
║                                                          ║
║  1. Scans BLE devices                                    ║
║  2. Connects to the X2 Max                               ║
║  3. Lists all services and characteristics               ║
║  4. Listens for notifications                            ║
║                                                          ║
║  DURING PHASE 4: press the VS200 buttons!                ║
╚══════════════════════════════════════════════════════════╝
""")
    print(f"  scan={scan_duration}s listen={listen_duration}s\n")

    address = await scan_devices(scan_duration)
    if not address:
        return

    await discover_services(address, listen_duration)

    print(f"\n[{ts()}] Scan finished.")
    print("  Paste the output above to identify")
    print("  which service/characteristic carries the gear data.")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="ThinkRider X2 Max BLE scanner")
    p.add_argument("--scan", type=int, default=DEFAULT_SCAN_DURATION,
                   help="BLE discovery duration in seconds")
    p.add_argument("--listen", type=int, default=DEFAULT_LISTEN_DURATION,
                   help="notification listening duration in seconds")
    return p.parse_args()


if __name__ == "__main__":
    args = parse_args()
    try:
        asyncio.run(main(args.scan, args.listen))
    except KeyboardInterrupt:
        print("\nInterrupted.")
