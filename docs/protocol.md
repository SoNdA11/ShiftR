# ThinkRider X2 Max — BLE Protocol Notes

Reverse-engineered with `tools/ble_scanner.py` (`bleak`) and confirmed in
`lib/services/` (`flutter_blue_plus`). This doc is the source of truth for
UUIDs, frame formats and FE-C commands.

## 1. Services & characteristics

| Service | UUID | Char | UUID | Props | Role |
|---|---|---|---|---|---|
| Cycling Power | `00001818-…` | Power Measurement | `00002A63-…` | notify | power + crank revs/time |
| Cycling Speed & Cadence | `00001816-…` | CSC Measurement | `00002A5B-…` | notify | crank revs/time fallback |
| Custom control | `0000FFF0-…` | write | `0000FFF1-…` | write | vendor init (unused) |
| Custom control | `0000FFF0-…` | notify | `0000FFF4-…` | notify | 10-byte status, sum-checked |
| ANT+ FE-C (vendor) | `6E40FEC1-…` | notify | `6E40FEC2-…` | notify | observed, not parsed |
| ANT+ FE-C (vendor) | `6E40FEC1-…` | write | `6E40FEC3-…` | write | **control path** |

All custom UUIDs use base `…-0000-1000-8000-00805f9b34fb` except FE-C
(`6E40FECx-B5A3-F393-E0A9-E50E24DCCA9E`).

## 2. Cycling Power Measurement (`2A63`)

Little-endian, BLE standard layout:

```text
flags: u16 (bytes 0-1)
power: i16 watts (bytes 2-3, clamped >= 0)
offset = 4
if flags & 0x01: offset += 1   # pedal power balance
if flags & 0x04: offset += 2   # accumulated torque
if flags & 0x10: offset += 6   # wheel revs + event time
if flags & 0x20 and len >= offset+4:
  crank_revs: u16 (offset)
  crank_time: u16, 1/1024 s (offset+2)
```

Cadence (rpm) from deltas with wrap-around:

```text
dRevs = (revs - lastRevs) & 0xFFFF
dTime = (time - lastTime) & 0xFFFF
cadence = dRevs * 1024 * 60 / dTime   # ignored if dTime == 0 or cadence > 200
```

See `lib/services/power_parser.dart`.

## 3. CSC Measurement (`2A5B`)

```text
flags: u8 (byte 0)
offset = 1
if flags & 0x01: offset += 6   # wheel revs (u32) + time (u16)
if flags & 0x02 and len >= offset+4:
  crank_revs: u16, crank_time: u16 (1/1024 s)  # same cadence formula
```

Used as cadence fallback when `2A63` has no crank data.

## 4. Custom notify (`FFF4`)

10-byte frames. Validation:

```text
sum = bytes[0..7].sum()
crc = bytes[9] << 8 | bytes[8]
drop frame if sum != crc
if bytes[0] == 0x19: status = bytes[7]  # 0x25 == idle, else log change
```

Opaque vendor status; not used for shifting. Logged only.

## 5. ANT+ FE-C control (`FEC3` write)

13-byte ANT frames: `[0xA4, len, page, …, checksum]`.
Checksum = `bytes[1..11].sum() & 0xFF`, appended as byte 12.
**Never mutate the caller list** — copy before appending (see `FecController`).

| Command | Frame (before checksum) | Notes |
|---|---|---|
| Basic Resistance (`0x4F`) | `A4 09 4F 05 30 FF FF FF FF FF FF NN` | `NN = (level*2).clamp(0,200)`; level 0–100 from `GearMapper` |
| Target Power (`0x4B`) | `A4 09 4B 05 30 PW_LO PW_HI FF FF FF FF FF` | from FTMS Control Point op `0x05` |
| Request Control | `A4 09 00 01 00 FF FF FF FF FF FF 00` | sent by `requestControl()` |
| Start resistance mode | `A4 09 4F 05 30 FF FF FF FF FF FF 00` | sent by `startResistance()` |

Write with response (`withoutResponse: false`).

## 6. Speed model

Virtual speed (km/h) is computed locally, not read from the trainer:

```text
gearRatio = 1 + (gear - 1) * (4.54 - 1) / 23
speed = cadence * 0.06 * gearRatio * 2.1
```

Constants: max ratio `4.54`, wheel circumference `2.1` m.
See `lib/core/constants.dart`.

## 7. Unknowns / TODO

- `FFF1` init sequence (`5A 01 00 5B`) is implemented but never called — capture needed?
- `FEC2` notifications observed but not parsed — log samples with `ble_scanner.py --listen 120`.
- VS200 button frames: correlate button presses with `FFF4` type `0x19` status changes.
