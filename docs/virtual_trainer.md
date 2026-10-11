# Virtual Trainer (phone-as-FTMS)

ShiftR makes the phone look like a smart trainer so apps like Zwift can
connect to it, while the phone itself stays connected to the real ThinkRider.

```text
ThinkRider X2 Max ──BLE──▶ phone (ShiftR) ──BLE advertise──▶ Zwift / Argus
                              │                        ▲
                              └── FE-C 0x4F / 0x4B ────┘ (Control Point 0x04/0x05)
```

## 1. Layers

| Layer | File | Role |
|---|---|---|
| Dart bridge | `lib/services/virtual_trainer_server.dart` | `MethodChannel('com.shiftr/virtual_trainer')`, 6-state machine, `updateData()` |
| Android GATT server | `android/…/VirtualTrainerServer.kt` | CPS + FTMS services, advertising, Control Point handler |
| Android entry | `android/…/MainActivity.kt` | `start/stop/updateData` channel wiring |
| Glue | `lib/services/trainer_service.dart` | forwards FTMS → FE-C, pushes power/cadence/speed |

## 2. GATT layout (advertised)

- CPS service `00001818-…`: Measurement `2A63` (notify), Feature `2A65` (read `00 00 00 00`), Sensor Location `2A5D` (read `00`).
- FTMS service `00001826-…`: Feature `2ACC` (read `32 00 00 00 0C 00 00 00` = cadence+resistance+power, resistance+power targets), Indoor Bike Data `2AD2` (notify), Control Point `2AD9` (write/indicate).
- Advertise: device name + FTMS UUID, low-latency / high-TX, connectable.

## 3. Data flow

- Dart → native: `updateData(power, cadence, speed)` on every trainer update.
  Native notifies CPS `2A63` immediately, then `2AD2` after 15 ms (avoids Android BLE buffer overlap).
- `2AD2` flags `0x44 0x00`, speed `u16 = kmh*100`, cadence `u16 = rpm*2`, power `u16`.

## 4. Control flow (Zwift → trainer)

| FTMS op | Native (`VirtualTrainerServer.kt`) | Dart callback |
|---|---|---|
| `0x04` Set Resistance | `onResistanceRequest(resistance u8)` + indicate `80 04 01` | `setResistance()` → FE-C `0x4F` |
| `0x05` Set Target Power | `onTargetPowerRequest(power u16le)` + indicate `80 05 01` | FE-C `0x4B` |
| `0x00/0x01/0x07/0x08` | auto-ack `80 op 01` | — |
| other | `80 op 02` (not supported) | — |

## 5. Lifecycle & states

`idle → starting → ready → advertising → connected ⇄ advertising`, plus `error`.
Dart `start(trainerName:)` sets the handler, invokes native `start`, mirrors
`onReady/onAdvertising/onConnected/onDisconnected/onError/onLog`.
`stop()` clears the handler **after** invoking native `stop`; native restores
the original BT name and closes GATT/advertiser. UI badge in `RideScreen`
reflects the latest status.

## 6. Requirements & troubleshooting

- Android only (BLE advertising + GATT server). Needs `BLUETOOTH_ADVERTISE` + location/BT runtime permissions.
- If Zwift can't see the phone: check advertising error (`too many advertisers` / `feature unsupported`), ensure the ThinkRider session is connected first, and keep the app in the foreground.
- Logs from native arrive as `onLog` → `debugPrint` in Dart.
