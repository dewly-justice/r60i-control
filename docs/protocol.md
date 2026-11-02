# Soundcore R60i NC (D1202C) control protocol

This is the wire protocol the Mac app will use to read and change settings on the
Soundcore R60i NC earbuds (model ID **D1202C**). It was worked out by reading
[OpenSCQ30](https://github.com/Oppzippy/OpenSCQ30), and it describes behavior in our
own words. No OpenSCQ30 code is copied here.

| | |
|---|---|
| Source | OpenSCQ30 `main` @ `e75a68b` (2026-10-29), GPL-3.0 |
| Device module | `lib/src/devices/soundcore/d1202.rs`. OpenSCQ30 maps **both** `SoundcoreD1202` (P31i) and `SoundcoreD1202C` (R60i NC) to this one module (`lib/src/devices/device_model.rs:134-135`). |
| Path shorthand | `sc/…` means `lib/src/devices/soundcore/…` in the OpenSCQ30 tree |
| Local checkout | `vendor/OpenSCQ30` (git-ignored) |
| Feature research | [`docs/research/r60i-nc-features.md`](research/r60i-nc-features.md): what Soundcore documents for the R60i NC, and what OpenSCQ30 covers |

> **Rule for this project:** we only send a write packet if its byte layout appears
> in this document **and** is cited to OpenSCQ30. If a packet is not listed under §7,
> we do not send it. Firmware update is out of scope.

---

## 1. Transport

| Item | Value | Source |
|---|---|---|
| Radio | Bluetooth **Classic (BR/EDR)**. The protocol does **not** use BLE. | OpenSCQ30 only has RFCOMM backends: `lib/src/connection_backend/{linux,windows}/rfcomm.rs`, `lib/src/api/connection.rs` (`RfcommBackend`) |
| Profile | **RFCOMM** (serial-port style byte stream) | same |
| Service selection | From the device's SDP service UUIDs, use the first one that matches the Soundcore vendor pattern. If none matches, fall back to the standard SPP UUID. | `sc/common/device.rs:89-101` (`SoundcoreDeviceConfig::default`), `lib/src/devices/soundcore.rs:42-49` |
| Vendor UUID pattern | `0CF12D31-FAC3-4553-BD80-D6832E7xxxxx`. The first 108 bits must match; the last 5 hex digits can be anything (mask `ffffffff-ffff-ffff-ffff-fffffff00000`). | `lib/src/devices/soundcore.rs:43-48` |
| Vendor UUID for D1202C | `0CF12D31-FAC3-4553-BD80-D6832E71202C` (the last digits spell the model ID) | `tools/soundcore-device-faker/devices/d1202c.toml` |
| SPP fallback UUID | `00001101-0000-1000-8000-00805F9B34FB`. OpenSCQ30 only; **we don't fall back** (see "Observed on a real R60i NC" below). | `lib/src/devices/soundcore.rs:42` |
| RFCOMM channel | **Not hard-coded.** Read it from the SDP record of the selected service. | Linux uses BlueZ `connect_profile(uuid)`; Windows uses `RfcommDeviceService` by service ID |
| Advertised name | `soundcore R60i NC` | `tools/soundcore-device-faker/devices/d1202c.toml` |
| Checksum mode | Every frame ends with a checksum byte (OpenSCQ30's default `ChecksumKind::Suffix`). D1202 does not override it. | `sc/common/packet.rs` (`ChecksumKind`), `sc/common/device.rs:83-101` |

**macOS mapping.** We checked these APIs against the installed Xcode 27.0 / macOS 27.0 SDK
headers:
`IOBluetoothDevice.pairedDevices()` → `getServiceRecord(for: IOBluetoothSDPUUID)` (or
`services` after `performSDPQuery`) → `IOBluetoothSDPServiceRecord.getRFCOMMChannelID` →
`IOBluetoothDevice.openRFCOMMChannelSync(_:withChannelID:delegate:)`.
Incoming bytes arrive on `rfcommChannelData(_:data:length:)` and we send with
`writeSync(_:length:)`. CoreBluetooth cannot be used because it is BLE-only.

**Observed on a real R60i NC** (firmware 03.89, macOS 27, 2026-11-02). macOS caches 14 SDP
records for the earbuds. The ones with an RFCOMM channel:

| RFCOMM channel | Service name | ServiceClassIDList | What it is |
|---:|---|---|---|
| 1 | — | `0x111E` / `0x1203` | Hands-Free / Audio Gateway (HFP) |
| 12 | `TOTA` | `0x1101` (Serial Port) | likely the earbud chip's (BES) OTA/test channel |
| 13 | `BESOTA` | `66666666-6666-6666-6666-666666666666` | BES firmware-update (OTA) channel |
| **15** | `soundcore Liberty NC` | **`0CF12D31-FAC3-4553-BD80-D6832E71202C`** | **the control channel this document describes** |
| 17 | `RFCOMM COM` | `DF21FE2C-2515-4FDB-8886-F12C4D67927C` | unknown |
| 29 | — | `99999999-9999-9999-9999-999999999999` | unknown |

Consequences for our implementation:
- **ServiceClassIDList (attribute `0x0001`) is a bare UUID**, not the sequence of UUIDs the
  Bluetooth spec requires. A parser that only accepts a sequence finds nothing. Accept both.
- **No Serial Port fallback.** OpenSCQ30 falls back to `0x1101` when no vendor UUID is present,
  but on this device that is `TOTA`, which looks like an OTA/test channel. We never connect
  to it, or to `BESOTA`. Firmware update is out of scope.
- The vendor channel was 15 here. It is still read from SDP rather than hard-coded.

**macOS 27 IOBluetooth quirks** (observed 2026-11-02, handled in `SoundcoreKit`):
- **The first RFCOMM open in a process often fails silently.** `openRFCOMMChannelAsync` returns
  success but never calls `rfcommChannelOpenComplete`, and the sync variant returns
  `kIOReturnError` (`0xE00002BC`) after about 3.1 s. bluetoothd's log shows no open request at
  all. An immediate second attempt opens in 0.1–0.5 s. `RFCOMMLink.open` gives the first
  attempt a 4 s timeout and retries.
- **Connect notifications arrive on a private queue**
  (`com.apple.bluetooth.iobluetooth.coordinatorQueue`), not the main thread. Main-actor code
  called from there traps. Every IOBluetooth callback hops to the main actor.
- **Only one control client at a time.** While the Soundcore phone app holds the channel, the
  Mac's open fails. Close the phone app.

---

## 2. Frame format

Both directions use the same frame layout. Multi-byte integers in the header are little-endian.

```
offset  size  field
0       5     direction prefix
5       2     command  [group, id]
7       2     total frame length, u16 LE (includes ALL bytes: prefix+command+length+body+checksum)
9       N     body
9+N     1     checksum = (sum of bytes 0 .. 8+N) mod 256
```

| Direction | Prefix |
|---|---|
| host → device ("outbound") | `08 EE 00 00 00` |
| device → host ("inbound") | `09 FF 00 00 01` |

- `length = 10 + N`, so the body length is `length − 10`.
- The checksum is a plain 8-bit wrapping sum of every byte before it. It is not a CRC.
- A **command** is two bytes. A pattern we noticed but that is not a stated rule: in the
  second byte, set/write commands have the high bit set (`0x81`, `0x83`, `0x87`, …), while
  reads and notifications usually don't (`0x01`…). Examples: `06 01` is a sound-mode
  notification and `06 81` sets sound modes; `01 7F` is an LDAC notification and `01 FF`
  sets LDAC.

Source: `sc/common/packet.rs` (`Packet::take`, `Packet::bytes`, `Direction::bytes`),
`sc/common/packet/checksum.rs`.

Verified example (OpenSCQ30 test `sc/common/packet/outbound/request_state.rs`):

```
RequestState:  08 EE 00 00 00 | 01 01 | 0A 00 | (no body) | 02
               prefix          cmd     len=10              checksum
```

---

## 3. Exchange rules

Source: `sc/common/packet/packet_io_controller.rs`, `sc/common/packet/multi_queue.rs`,
`sc/common/packet_manager.rs`.

1. **Stream reassembly.** RFCOMM reads can split one frame into several chunks or deliver
   several frames together. Append incoming bytes to a buffer and parse frames off the
   front. A partial frame means wait for more bytes. If the prefix doesn't match or the
   checksum is wrong, OpenSCQ30 clears the whole buffer and starts over.
2. **Matching replies.** A request is answered by the next **inbound** frame that has the
   **same command bytes**. OpenSCQ30 keeps a FIFO queue per command, so requests with
   different commands can be in flight together, while requests with the same command are
   serialized.
3. **Write acknowledgement.** For a write such as `06 81`, OpenSCQ30 waits for an inbound
   `06 81` and ignores its body. Its tests and demo device model this ACK as an
   **empty-body** inbound frame. Example (from an OpenSCQ30 test):
   `09 FF 00 00 01 06 81 0A 00 9A`.
4. **Retries.** Send, wait 500 ms; resend, wait 1000 ms; resend, wait 1500 ms; then give up
   with a timeout error.
5. **Unsolicited packets.** An inbound frame that doesn't match a pending request is a push
   notification. It is routed by command to the handlers in §6. If the command is unknown,
   the frame is logged and ignored.
6. **The host never acknowledges inbound frames.**
7. **Multi-packet replies** (only used for `0B 01` dual-connection devices): send one
   request, then collect inbound `0B 01` frames until `current_index == total`. If no frame
   arrives within 2 s, stop. Accept at most 20 frames.

---

## 4. Session start-up (D1202)

Source: `sc/d1202.rs:31-91`.

1. Open the RFCOMM channel (§1).
2. Send **`01 01` RequestState** with an empty body. The reply is the full state packet
   (§6.1). Parse it.
3. If the "dual connections enabled" byte in that state (offset 0x83) is `1`, send
   **`0B 01`** (request dual-connection devices) and collect the multi-packet reply (§6.8).
4. Then listen for push notifications (§6) for the rest of the session.

OpenSCQ30 does **not** poll after start-up. Battery and similar values only update when the
device pushes them.

---

## 5. Common encodings

| Encoding | Rule | Source |
|---|---|---|
| bool | `1` = true; **any other value** = false | `sc/common/packet/parsing/basics.rs` (`take_bool`) |
| Earbud battery level | raw `0…9`; shown as `(raw+1)/10`, i.e. 10 %…100 %. `255` means that bud is absent (not connected to the other bud). | `sc/d1202.rs:75-78` (`max_level 10, level_offset 1`), `sc/common/modules/dual_battery/setting_handler.rs` |
| Case battery level | same scale as earbuds. `255` means unavailable (for example, both buds are out of the case). | `sc/d1202.rs:79-82`, `sc/common/modules/case_battery_level.rs` |
| Charging | `1` = charging, anything else = not charging | `sc/common/structures/battery.rs` |
| Firmware version | 5 ASCII chars `"MM.mm"` (e.g. `30 31 2E 38 33` = `01.83`). If one side is all `00` or all `FF`, that side is absent. Both sides absent is a parse error. | `sc/common/structures/firmware_version.rs` |
| Serial number | 16 ASCII alphanumeric chars. Usually the model number followed by the MAC address in reverse byte order. | `sc/common/structures/serial_number.rs` |
| EQ band value | `byte = tenths_of_dB + 120`. So `120` = 0.0 dB, `0` = −12.0 dB, `254` = +13.4 dB. One step is 0.1 dB. | `sc/common/structures/equalizer_configuration.rs` (`CommonEqualizerConfiguration` = min −120, max 134, 1 fraction digit), `volume_adjustments.rs` |
| EQ channel absent | if the **first** byte of a 10-byte channel block is `0xFF`, the whole channel is "not present". When writing an absent channel, send ten `0xFF` bytes. | `sc/common/structures/volume_adjustments.rs` (`take_optional`, `OptionalVolumeAdjustmentsExt::bytes`) |
| Button action byte | low nibble = action when **both buds are linked** (TWS connected); high nibble = action when **one bud is used alone**. Nibble `0xF` = gesture disabled. | `sc/common/structures/button_configuration.rs` (`ActionKind::TwsLowBits`) |
| Unknown enum values | OpenSCQ30 maps an unrecognized enum byte to the enum's first variant. **We keep the raw byte when reading. Writes refuse** if a field to be written holds a value outside the documented set, so we never send a value the device didn't report. | `sc/common/macros.rs` (`sound_mode_enum!`); ours: `SoundcoreKit/Sources/SoundcoreKit/Protocol/SoundModes.swift` |

---

## 6. Device → host packets

### 6.1 `01 01` — full state (reply to RequestState, can also be pushed)

Body layout. The parse order comes from `sc/d1202/packets/inbound/state_update.rs:64-142`.
Offsets were checked by decoding the real-device fixture in the `sc/d1202.rs` tests
(firmware 01.83).

| Off (dec) | Off (hex) | Len | Field | Fixture value → meaning |
|---:|---:|---:|---|---|
| 0 | 0x00 | 1 | TWS host device: `0` Left, `1` Right | `01` → Right |
| 1 | 0x01 | 1 | TWS connected (buds linked) — bool | `01` → yes |
| 2 | 0x02 | 1 | Left battery level | `09` → 10/10 |
| 3 | 0x03 | 1 | Right battery level | `09` → 10/10 |
| 4 | 0x04 | 1 | Left charging | `00` → no |
| 5 | 0x05 | 1 | Right charging | `00` → no |
| 6 | 0x06 | 5 | Left firmware (ASCII) | `01.83` |
| 11 | 0x0B | 5 | Right firmware (ASCII) | `01.83` |
| 16 | 0x10 | 16 | Serial number (ASCII) | `12023409C9B403CE` |
| 32 | 0x20 | 5 | **unknown** (OpenSCQ30 guesses case firmware) | `01.83` |
| 37 | 0x25 | 1 | Case battery level | `03` → 4/10 |
| 38 | 0x26 | 2 | EQ preset ID, u16 LE (§8.6) | `00 00` → SoundcoreSignature |
| 40 | 0x28 | 10 | EQ left channel, 10 bands | all `78` (0 dB) |
| 50 | 0x32 | 10 | EQ right channel, 10 bands | all `FF` → absent |
| 60 | 0x3C | 1 | unknown | `00` |
| 61 | 0x3D | 1 | HearID enabled — bool | `00` |
| 62 | 0x3E | 10 | HearID left | |
| 72 | 0x48 | 10 | HearID right | |
| 82 | 0x52 | 4 | HearID timestamp, **u32 BE** | |
| 86 | 0x56 | 1 | HearID type: `0` Initial, `1` Custom, `2` FavoriteMusicGenre | `02` |
| 87 | 0x57 | 10 | HearID custom left | |
| 97 | 0x61 | 10 | HearID custom right | |
| 107 | 0x6B | 2 | HearID favorite music genre, u16 LE | |
| 109 | 0x6D | 1 | unknown | `0A` |
| 110 | 0x6E | 1 | Button: Left single press | `FF` → disabled |
| 111 | 0x6F | 1 | Button: Right single press | `FF` → disabled |
| 112 | 0x70 | 1 | Button: Left double press | `63` → linked: NextSong, solo: PlayPause |
| 113 | 0x71 | 1 | Button: Right double press | `66` → PlayPause / PlayPause |
| 114 | 0x72 | 1 | Button: Left triple press | `FF` |
| 115 | 0x73 | 1 | Button: Right triple press | `FF` |
| 116 | 0x74 | 1 | Button: Left long press | `44` → AmbientSoundMode |
| 117 | 0x75 | 1 | Button: Right long press | `44` → AmbientSoundMode |
| 118 | 0x76 | 1 | Sound-mode cycle (§6.10). OpenSCQ30's D1202 module skips it as unknown | `33` |
| 119 | 0x77 | 8 | **Sound modes block** (§6.2) | `00 50 00 02 00 00 00 00` |
| 127 | 0x7F | 1 | unknown | `32` |
| 128 | 0x80 | 1 | Touch tone — bool | `01` |
| 129 | 0x81 | 1 | Low battery voice prompt — bool | `01` |
| 130 | 0x82 | 1 | LDAC — bool | `00` |
| 131 | 0x83 | 1 | Dual connections enabled — bool | `01` |
| 132 | 0x84 | 1 | Auto power-off enabled — bool | `01` |
| 133 | 0x85 | 1 | Auto power-off duration index (§8.8) | `02` → 30 min |
| 134 | 0x86 | 1 | Volume limit enabled — bool | `00` |
| 135 | 0x87 | 1 | Volume limit dB | `5A` → 90 dB |
| 136 | 0x88 | 1 | dB reading refresh rate (§8.9) | `00` → real time |
| 137 | 0x89 | 1 | Spatial audio enabled — bool | `00` |
| 138 | 0x8A | 1 | Spatial audio mode (§8.5) | `00` → Music |
| 139+ | | … | trailing bytes; OpenSCQ30 does not parse them | fixture has 13 more: `00×8, FF×5` |

The fixture body is 152 bytes, so the full frame is 162 bytes (`length = A2 00`). The parser
needs at least 139 bytes and ignores anything after that.

**Real R60i NC capture** (firmware 03.89; only the right bud out of the case; fixture
`Fixtures.r60iStateFrame`). Also 152 bytes. Every offset above decodes to a plausible value.
Where it differs from the OpenSCQ30 fixture:

| Off | Field | Real R60i NC |
|---:|---|---|
| 0–5 | TWS / battery / charging | `01 00 FF 09 00 00` → host Right, buds not linked, left absent, right 10/10 |
| 37 | Case battery | `07` → 80 % |
| 60 | unknown | `FF` (fixture `00`) |
| 62–81, 87–106 | HearID EQ data | all `FF`: HearID has never been run |
| 82–85 | HearID timestamp | `FF 00 00 00` |
| 86 | HearID type | `FF`, outside OpenSCQ30's `0…2` |
| 119–126 | Sound modes | `02 55 00 01 01 00 00 01` → Normal, manual 5, adaptive nibble **5** (§6.2), NC Adaptive, wind suppression on, real-time adaptive on |
| 127 | unknown | `31` (fixture `32`) |
| 137–138 | Spatial audio | `01 00` → **on**, Music. Unverified whether the R60i NC has spatial audio (§10) |
| 139+ | trailing | `01 00 00 00 00 00 00 01 FF FF FF FF FF` |

Bytes that change on their own (no write involved), seen across reads on the same day:
- Sound-modes byte 1, low nibble (adaptive): `5`, then `3`. It looks like a live adaptive
  level.
- Offset 139 (`0x8B`, first trailing byte): `01`, `00`, `01`, `00`. Meaning unknown.

After an `03 87` EQ write, offset 60 (`0x3C`) reads `00` (it was `FF`). That matches the two
"unknown" bytes the EQ body always sends as `00 00` (§7.3), and OpenSCQ30's fixture.

### 6.2 Sound modes block (8 bytes) — also the `06 01` push body and the `06 81` write body

Source: `sc/d1202/structures.rs:18-97`,
`sc/common/structures/manual_adaptive_noise_canceling.rs`, `sc/common/structures/wind_noise.rs`.

| Byte | Field | Values |
|---:|---|---|
| 0 | Ambient sound mode | `0` Noise Canceling, `1` Transparency, `2` Normal |
| 1 | high nibble: **manual ANC level**; low nibble: **adaptive ANC strength** | manual `1…5` (OpenSCQ30 clamps to 1…5). Adaptive `0` Weak, `1` Moderate, `2` Strong. **Adaptive strength is read-only**: the device reports it, and OpenSCQ30 shows it as information and rejects setting it (`sc/d1202/modules/sound_modes/setting_handler.rs`). **A real R60i NC reports `5`.** OpenSCQ30 maps that to Weak and so writes `0` back. We send the nibble back exactly as the device reported it. |
| 2 | Transparency mode | `0` Fully transparent, `1` Vocal mode |
| 3 | Noise-canceling mode | `0` Manual, `1` Adaptive, `2` Multi-scene |
| 4 | Wind noise bitfield | bit 0 = wind-noise **suppression enabled** (settable); bit 1 = wind **currently detected** (read-only) |
| 5 | unknown | OpenSCQ30 ignores it on read and **always writes `0`**, which OpenSCQ30 issue #424 questions. We send it back as read. Every capture so far has `00`, so the bytes are the same today. |
| 6 | Multi-scene ANC | `0` Transport, `1` Outdoor, `2` Indoor |
| 7 | Real-time adaptive ANC — bool | |

### 6.3 `06 01` — sound modes changed (push)

Body: the 8-byte block from §6.2. The device sends it when the mode changes on the buds
themselves, for example after a long press.
Source: `sc/common/modules/sound_modes_v2/packet_handler.rs`, `sc/d1202/modules/sound_modes.rs`.

### 6.4 `01 02` — TWS status (push)

Body: 2 bytes, `[host_device, tws_connected]`, same meaning as state bytes 0–1. The parser
rejects any extra bytes. Source: `sc/common/packet/inbound/tws_status.rs`,
`sc/common/modules/tws_status.rs`.

### 6.5 `01 03` — battery level (push)

Body: `[left_level, right_level]`, which may be followed by 2 more bytes whose meaning is
unknown. OpenSCQ30 ignores those 2 bytes. Source: `sc/common/packet/inbound/battery_level.rs`
(`DualBatteryLevel`), `sc/common/modules/dual_battery/packet_handler.rs`.

### 6.6 `01 04` — charging status (push)

Body: `[left_charging, right_charging]`. Source: `sc/common/packet/inbound/battery_charging.rs`
(`DualBatteryCharging`).

### 6.7 `01 05` — firmware + serial (push)

Body: left firmware (5) + right firmware (5) + serial (16) = 26 bytes. Source:
`sc/common/packet/inbound/serial_number_and_firmware_version.rs`,
`sc/common/modules/serial_number_and_dual_firmware_version.rs`.

### 6.8 `0B 01` — dual-connection device list (multi-packet reply or push)

Source: `sc/common/packet/inbound/dual_connections_device.rs`,
`sc/common/structures/dual_connections.rs`,
`sc/common/modules/dual_connections/packet_handler.rs`.

```
byte 0     total packets in this list
byte 1     index of this packet, starting at 1
then repeat until body ends:
  1   record length L (counts from this byte to end of record; OpenSCQ30 emits 0x28 = 40)
  1   connected — bool
  6   MAC address, in **reverse** byte order (last octet first)
  L-8 device name, UTF-8, padded with zeros (stop at first 0x00)
```

**Byte order, verified on hardware.** A real R60i NC reported this Mac (`5C:9B:A6:6E:D3:17`) as
`17 D3 6E A6 9B 5C` and an iPhone (`A8:AB:B5:01:16:3D`) as `3D 16 01 B5 AB A8`. OpenSCQ30 shows
the bytes as received, so it displays addresses reversed. It also sends the same bytes back in
`0B 81/82/83`, which is correct on the wire. We do the same and only reverse for display.

When a packet with index 1 arrives, OpenSCQ30 clears its device list. Real devices have
been seen sending a last record that is a few bytes shorter than its length byte says.
OpenSCQ30 truncates the name in that case instead of failing.

### 6.9 `01 7F` — LDAC state (push)

Body: exactly 1 byte, a bool. Source: `sc/common/modules/flag.rs` (`Ldac` flag,
`update_command`).

> No push packet exists for EQ, buttons, case battery, auto power-off, volume limit, touch
> tone, low battery prompt or spatial audio. Those values only refresh from a full `01 01`
> state packet.

### 6.10 Sound-mode cycle (state offset 0x76) — not in OpenSCQ30's D1202 module

Which modes the "Switch Sound Mode" button action (press and hold, by default) steps through.
Soundcore documents the setting for the R60i NC: "You can add Normal mode via the Anker
soundcore app" (support article "How do I switch between ANC and Transparency Mode via touch
control on my P31i/R60i NC?"; `docs/research/r60i-nc-features.md`).

OpenSCQ30 skips this byte for D1202 (`take(1usize)` before the sound modes in
`sc/d1202/packets/inbound/state_update.rs:87`). We read it with the layout OpenSCQ30 uses for
the **A3968**, whose state packet matches D1202's field for field up to the sound-modes block
and has `AmbientSoundModeCycleTws` in this exact slot (`sc/a3968/packets/inbound/state_update.rs:92-96`):

| Bits | Meaning (`sc/common/structures/ambient_sound_mode_cycle.rs`) |
|---|---|
| low nibble | cycle while both earbuds are connected (`tws_enabled`) |
| high nibble | cycle while only one is (`tws_disabled`) |
| bit 0 / 1 / 2 of a nibble | Noise Cancelling / Transparency / Normal is in the cycle |
| bit 3 | not defined; we send it back as read |

Our R60i NC reports `33`: Noise Cancelling ↔ Transparency in both situations, which is the
documented default ("press and hold for 2 s: ANC ↔ Transparency", manual CONTROLS). The OpenSCQ30
D1202 fixture has `33` too. Written with `06 82` (§7.2). Like the buttons, the app edits the
nibble for the current TWS state, as OpenSCQ30's `ambient_sound_mode_cycle_tws/setting_handler.rs`
does, and refuses a cycle with fewer than two modes.

---

## 7. Host → device packets

Unless a row says otherwise, every write waits for an ACK (an inbound frame with the same
command, §3).

### 7.1 Reads (empty body)

| Cmd | Name | Reply | Used by D1202 module? | Source |
|---|---|---|---|---|
| `01 01` | RequestState | `01 01` full state | **yes** (start-up, and after a button reset) | `sc/common/packet/outbound/request_state.rs` |
| `0B 01` | Request dual-connection devices | one or more `0B 01` | **yes** (start-up, if dual connections is enabled) | `sc/common/packet/outbound/dual_connections.rs` |
| `01 03` | Request battery level | `01 03` | no (defined, unused) | `sc/common/packet/outbound/request_battery_level.rs` |
| `01 04` | Request charging | `01 04` | no (defined, unused) | `request_battery_charging.rs` |
| `01 05` | Request serial + firmware | `01 05` | no (defined, unused) | `request_serial_number_and_firmware_version.rs` |
| `01 7F` | Request LDAC state | `01 7F` | no (defined, unused) | `request_ldac_state.rs` |

We will use only `01 01` and `0B 01`. The other reads are confirmed but not needed, since
`01 01` already covers them.

### 7.2 Writes used by the D1202 module

| Cmd | Name | Body | Source |
|---|---|---|---|
| `06 81` | Set sound modes | the 8-byte block from §6.2 (full struct) | `sc/common/modules/sound_modes_v2/state_modifier.rs`, `sc/d1202/structures.rs:31-46` |
| `03 87` | Set equalizer (D1202 layout) | 114 bytes, §7.3 | `sc/d1202/packets/outbound.rs:19-99` |
| `10 81` | Set spatial audio | `[enabled, 0x00, mode]` | `sc/d1202/packets/outbound.rs:8-17` |
| `04 81` | Set one button's action | `[side, button_id, action_byte]` (side `0` L, `1` R; IDs in §8.7; action byte is both nibbles, §5) | `sc/common/packet/outbound/set_button_configuration.rs` |
| `04 82` | Reset all buttons to defaults | empty; then send `01 01` again to refresh | `set_button_configuration.rs`, `sc/common/modules/reset_button_configuration.rs` |
| `20 82` | Set volume limit | `[enabled, dB]`, where dB is 75…100 in steps of 5 | `sc/common/packet/outbound/set_limit_high_volume.rs` |
| `20 81` | Set dB-reading refresh rate | `[rate]` (§8.9) | same |
| `0B 84` | Enable/disable dual connections | `[bool]` | `sc/common/packet/outbound/dual_connections.rs` |
| `0B 83` | Forget a paired device | 6-byte MAC | same |
| `0B 82` | Connect a paired device | 6-byte MAC. **Fire-and-forget: no ACK awaited.** | same, `sc/common/modules/dual_connections/state_modifier.rs` |
| `0B 81` | Disconnect a device | 6-byte MAC. **Fire-and-forget: no ACK awaited.** | same |
| `01 86` | Set auto power-off | `[enabled, duration_index]` (§8.8) | `sc/common/packet/outbound/set_auto_power_off.rs` |
| `01 83` | Set touch tone | `[bool]` | `sc/common/packet/outbound.rs` (`SET_TOUCH_TONE_COMMAND`), `sc/common/modules/flag/state_modifier.rs` |
| `10 82` | Set low-battery prompt | `[bool]` | `SET_LOW_BATTERY_PROMPT_COMMAND`, same |
| `01 FF` | Set LDAC | `[bool]` | `sc/common/modules/flag.rs` (`Ldac`) |
| `06 82` | Set sound-mode cycle (§6.10). **Not used by OpenSCQ30's D1202 module.** | `[cycle byte]`: high nibble one-earbud cycle, low nibble two-earbud cycle | `set_ambient_sound_mode_cycle_tws`, `sc/common/packet/outbound/set_ambient_sound_mode_cycle.rs:24`, as the A3968 uses it (`sc/common/modules/ambient_sound_mode_cycle_tws/state_modifier.rs`). Verified on hardware: §7.5 |

> ⚠️ **Same command, different layout.** OpenSCQ30's common code also uses `06 81`
> (`sc/common/packet/outbound/set_sound_modes.rs`, a **4-byte** body for other models) and
> `03 87` (`set_equalizer_and_custom_hear_id.rs`, a different body). The D1202 module
> replaces both with its own encoders, listed above. For D1202C, use **only** the
> 8-byte §6.2 block and the 114-byte §7.3 body.

**Not for D1202.** These are defined in OpenSCQ30's common code, but the D1202 module doesn't
use them, so we will **not** send them: `04 83` (button enabled flag), `04 84` (set all
buttons), `01 87` gaming mode, `01 81` auto play/pause &
wearing detection, `01 8C` wearing tone, `04 86` touch lock, `10 86` sound-leak compensation,
`02 86` surround, `01 90` voice prompt, `10 94` disable all buttons, `02 81` / `02 83` /
`03 86` (other EQ variants).

### 7.3 `03 87` set-equalizer body (114 bytes)

Checked byte-for-byte against the `set_preset_eq` and `disable_spatial_audio` test vectors
in `sc/d1202.rs`.

| Off | Len | Field | What OpenSCQ30 sends |
|---:|---:|---|---|
| 0 | 2 | Preset ID, u16 LE | preset ID, or `0xFEFE` for custom |
| 2 | 2 | HearID favorite genre, u16 LE | echoed from state |
| 4 | 10 | EQ left | band bytes (§5), or `FF×10` if the channel is absent |
| 14 | 10 | EQ right | same |
| 24 | 2 | unknown | `00 00` |
| 26 | 1 | HearID enabled | **always `00`**. OpenSCQ30 doesn't support enabling HearID. |
| 27 | 10 | HearID left | echoed from state |
| 37 | 10 | HearID right | echoed |
| 47 | 4 | HearID timestamp, **u32 BE** | echoed |
| 51 | 1 | HearID type | echoed |
| 52 | 10 | HearID custom left | echoed |
| 62 | 10 | HearID custom right | echoed |
| 72 | 20 | "Effective" EQ left: each of the 10 band bytes followed by `00` | since HearID is off, this is the EQ-left bytes interleaved with zeros |
| 92 | 20 | "Effective" EQ right, interleaved the same way | |
| 112 | 2 | trailer | `00 00` |

**Building the EQ values.** Source: `sc/common/modules/equalizer.rs:261-429`,
`sc/common/modules/equalizer/setting_handler.rs:340-470`.

- **Preset:** use the preset's 10 values (§8.6) for **both** channels. Bands 9 and 10 are
  always `0, −120`, i.e. bytes `78 00`.
- **Custom:** preset ID `0xFEFE`. The user edits 8 bands at 100, 200, 400, 800, 1600, 3200,
  6400 and 12800 Hz, from −12.0 to +13.4 dB in 0.1 dB steps. The two hidden bands are fixed
  at `0, 0` (bytes `78 78`). Channel 1's values are copied to both channels.
- OpenSCQ30 stores named custom profiles **on the computer** (its SQLite DB), not on the
  earbuds. The device only knows the current values and preset ID.

### 7.4 Coupling between spatial audio and EQ

Source: `sc/d1202/modules/equalizer/state_modifier.rs`.

- When an EQ change is sent with `03 87`, the earbuds turn spatial audio **off**. OpenSCQ30
  updates its local state to match.
- **To turn spatial audio on, or change its mode while on:** send `10 81 [01, 00, mode]`.
- **To turn spatial audio off:** do **not** send `10 81 [00, …]`. Like the official app, send
  `03 87` with the current preset ID, both channels set to channel 1's values, band 9 = `0`
  and band 10 = −12.0 dB (byte `00`). If the mode is also changing, first send
  `10 81 [01, 00, newMode]`.
- If one request changes both EQ and spatial audio, OpenSCQ30 sends only the EQ packet.

### 7.5 Verified on a real R60i NC

Firmware 03.89, 2026-11-02, connected to a Mac (only the right bud out of the case, so TWS
not linked). Each write was sent with `scprobe set …`, then the state was re-read and the
setting restored. Every one was acknowledged with an empty-body frame, as §3 describes.

| Write | Result |
|---|---|
| `06 81` mode, NC mode, manual level, multi-scene, transparency, wind, real-time adaptive | applied and restored. The adaptive nibble was sent back as read (§6.2) |
| `03 87` preset (Acoustic), custom EQ, Soundcore Signature | applied; spatial audio turned off, as §7.4 says. HearID bytes unchanged (type `FF` sent back as `FF`). **Caveat:** only the right bud was linked. OpenSCQ30 refuses EQ changes while TWS is unlinked (`common/modules/equalizer/setting_handler.rs`, commit `7cfe336`), because the other bud would keep its old EQ. SoundcoreKit now refuses too |
| `10 81` spatial audio on (Music, Movie) / off via `03 87` | applied and restored |
| `04 81` right double press (solo nibble, since TWS was not linked) | applied and restored |
| `01 86` auto power-off 60 → 30 min | applied and restored |
| `01 83` touch tone, `10 82` low-battery prompt | applied and restored |
| `20 82` volume limit 85 dB on → 90 dB off, `20 81` refresh rate | applied and restored |
| `0B 84` dual connection off → on | applied and restored |
| `0B 01` device list | 2 records, MAC bytes reversed (§6.8) |
| `01 FF` LDAC on | **acknowledged but not applied**: offset 0x82 stayed `00`, no `01 7F` push. Same result with dual connection off. Spatial audio was **on** during both tries, and Soundcore's FAQ says LDAC and spatial audio exclude each other (see the research doc). A later try from the app, one second after spatial audio was turned off (both buds in, iPhone also connected), also left LDAC off. That fits Soundcore's "LDAC is only available on Android devices" |
| `06 82` sound-mode cycle `33` → `37` (both buds linked, 15:30) | acknowledged; offset 0x76 read back `37`, also after reconnecting. Pressing and holding then stepped Normal → Noise Cancelling → Transparency → Normal (`06 01` pushes), so Normal really was in the cycle. Restored to `33` |
| `04 82` reset buttons, `0B 81/82/83` | not tested on hardware. Reset can't be undone while TWS is unlinked (only one nibble is writable), and forget can't be undone at all |

Restoring the EQ needed one extra write. Every OpenSCQ30 preset sets hidden band 10 to −12 dB
(byte `00`), and the earbuds had `78` there. A `03 87` with preset 0 and the original ten
`78` bytes, followed by `10 81 [01 00 00]`, restored it.

---

## 8. Enumerations

### 8.1 Ambient sound mode (sound-modes byte 0)
`0` NoiseCanceling · `1` Transparency · `2` Normal — `sc/common/structures/sound_modes.rs`

### 8.2 Noise-canceling mode (byte 3)
`0` Manual · `1` Adaptive · `2` MultiScene — `sc/d1202/structures.rs:106-112`

### 8.3 Multi-scene (byte 6)
`0` Transport · `1` Outdoor · `2` Indoor — `sc/d1202/structures.rs:114-120`

### 8.4 Transparency (byte 2)
`0` FullyTransparent · `1` VocalMode — `sc/d1202/structures.rs:99-104`

### 8.5 Spatial audio mode
`0` Music · `2` Movie · `3` Gaming (there is no `1`) — `sc/d1202/structures.rs:146-152`

### 8.6 EQ presets (`sc/common/modules/equalizer.rs:261-411`, `common_settings_type_2`)

Values are in tenths of a dB for bands 1–8, then the two hidden bands.

| ID | Name | Bands (×0.1 dB) |
|---:|---|---|
| 0 | Soundcore Signature | 0 0 0 0 0 0 0 0 · 0 −120 |
| 1 | Acoustic | 40 10 20 20 40 40 40 20 · 0 −120 |
| 2 | Bass Booster | 40 30 10 0 0 0 0 0 · 0 −120 |
| 3 | Bass Reducer | −40 −30 −10 0 0 0 0 0 · 0 −120 |
| 4 | Classical | 30 30 −20 −20 0 20 30 40 · 0 −120 |
| 5 | Podcast | −30 20 40 40 30 20 0 −20 · 0 −120 |
| 6 | Dance | 20 −30 −10 10 20 20 10 −30 · 0 −120 |
| 7 | Deep | 20 10 30 30 20 −20 −40 −50 · 0 −120 |
| 8 | Electronic | 30 20 −20 20 10 20 30 30 · 0 −120 |
| 9 | Flat | −20 −20 −10 0 0 0 −20 −20 · 0 −120 |
| 10 | Hip-Hop | 20 30 −10 −10 20 −10 20 30 · 0 −120 |
| 11 | Jazz | 20 20 −20 −20 0 20 30 40 · 0 −120 |
| 12 | Latin | 0 0 −20 −20 −20 0 30 50 · 0 −120 |
| 13 | Lounge | −10 20 40 30 0 −20 20 10 · 0 −120 |
| 14 | Piano | 0 30 30 20 40 50 30 40 · 0 −120 |
| 15 | Pop | −10 10 30 30 10 −10 −20 −30 · 0 −120 |
| 16 | R&B | 60 20 −20 −20 20 30 30 40 · 0 −120 |
| 17 | Rock | 30 20 −10 −10 10 30 40 50 · 0 −120 |
| 18 | Small Speakers | 40 30 10 0 −20 −30 −40 −40 · 0 −120 |
| 19 | Spoken Word | −30 −20 10 20 20 10 0 −30 · 0 −120 |
| 20 | Treble Booster | −20 −20 −20 −10 10 20 20 40 · 0 −120 |
| 21 | Treble Reducer | 0 0 0 −20 −30 −40 −40 −60 · 0 −120 |
| 0xFEFE | Custom | user values · 0 0 |

### 8.7 Buttons (`sc/d1202.rs:93-151`)

The state packet lists buttons in this order: L-single, R-single, L-double, R-double,
L-triple, R-triple, L-long, R-long.

| Gesture | `button_id` for `04 81` | Allowed actions |
|---|---:|---|
| Single press | 2 | 0, 1, 2, 3, 6 (OpenSCQ30 notes this matches the app's limit, not necessarily the device's) |
| Double press | 0 | 0–6 |
| Triple press | 5 | 0–6 |
| Long press | 1 | 0–6 |

Action IDs (`sc/common/modules/button_configuration.rs`): `0` Volume up · `1` Volume down ·
`2` Previous track · `3` Next track · `4` Ambient sound mode (cycle) · `5` Voice assistant ·
`6` Play/Pause · `0xF` disabled. Gaming mode (`9`) isn't offered for D1202.

Every gesture on every side can be disabled on its own (`IndividualDisable`). D1202 has no
separate "enabled" byte, so disabling a gesture means writing `0xF` into its action nibble.
OpenSCQ30 only edits the nibble for the **current** TWS state (low nibble when the buds are
linked, high nibble when one is used alone) and sends the full byte, keeping the other
nibble unchanged.

### 8.8 Auto power-off duration index
`0` 10 min · `1` 20 min · `2` 30 min · `3` 60 min. "Off" is `enabled = 0`.
— `sc/d1202.rs:68-70`, `sc/common/modules/auto_power_off.rs`

### 8.9 dB-reading refresh rate
`0` Real time · `1` 10 s · `2` 1 min — `sc/common/structures/limit_high_volume.rs`

---

## 9. Settings OpenSCQ30 exposes for D1202/D1202C

This is the complete list, so it is the upper limit of what the app can offer:

- **Status (read-only):** L/R battery + charging, case battery, TWS link + host side,
  L/R firmware, serial number, wind currently detected, adaptive ANC strength.
- **Sound modes:** ambient mode (ANC / Transparency / Normal), NC mode (Manual / Adaptive /
  Multi-scene), manual ANC level 1–5, multi-scene (Transport / Outdoor / Indoor),
  transparency (Full / Vocal), wind-noise suppression, real-time adaptive ANC.
- **Equalizer:** 22 presets plus a custom 8-band EQ, with named custom profiles stored locally.
- **Buttons:** 8 gestures (L/R × single/double/triple/long), each with an action or
  disabled, plus "reset to defaults".
- **Dual connections:** on/off, plus the list of paired devices with connect, disconnect
  and forget.
- **Miscellaneous:** spatial audio on/off + mode (Music/Movie/Gaming), LDAC, auto power-off,
  touch tone, low-battery prompt, volume limit (on/off, 75–100 dB, refresh rate).

> ⚠️ OpenSCQ30 uses the same module for the P31i (D1202) and the R60i NC (D1202C). So some
> settings, for example LDAC or spatial audio, might be present in the packet but have no
> effect on the R60i NC. We'll compare against the official app screenshots in
> `reference/` and the state captured from the real device before showing them in the UI.

---

## 10. Unknowns and open questions

- State bytes at 0x20 (5 bytes), 0x3C, 0x6D and 0x7F, plus anything from 0x8B on:
  meaning unknown. We parse them, keep them, and never write them.
- Sound-modes byte 5: meaning unknown. OpenSCQ30 always writes `0`, and we'll do the same.
- The 2 extra bytes in `01 03` (battery) pushes: meaning unknown.
- `0B 02` push, body `[00|01] + 6 bytes`, e.g. `00 17 D3 6E A6 9B 5C` then `01 17 D3 6E A6 9B 5C`
  (seen twice in 2 minutes with dual connection on). The 6 bytes look like a MAC in wire order
  (§6.8), so it's probably a dual-connection device dropping and coming back. Not handled yet.
- HearID: we only echo the values back unchanged. We won't build HearID features. On a real
  R60i NC that has never run HearID, these bytes are `FF` and the type byte (86) is `FF`,
  outside OpenSCQ30's enum. Check how `03 87` (§7.3) handles that before Phase 2 sends any EQ write.
- Spatial audio: confirmed on the R60i NC (Music/Movie on and off all apply, §7.5).
- LDAC: the R60i NC acknowledged `01 FF [01]` but kept LDAC off, with spatial audio on and
  again with it off (no Android source connected). Soundcore documents that LDAC and spatial
  audio exclude each other, that LDAC is Android-only, and that switching codecs takes about
  10 s. Untested with an Android phone connected.
- Adaptive ANC nibble: the R60i NC reports values outside OpenSCQ30's `0…2` names (`5`, `3`),
  changing on its own. It looks like a live level. It is read-only either way (§6.2).
- State offset `0x8B`: flips between `00` and `01` on its own. Meaning unknown.
- Whether the device acknowledges `0B 81` / `0B 82`: OpenSCQ30 doesn't wait for an ACK, and
  neither will we.

---

## 11. Worked frames

The first two frames appear verbatim in OpenSCQ30 tests. We computed the rest by applying
§2 to bodies documented above.

```
RequestState (host→dev)            08 EE 00 00 00 01 01 0A 00 02
ACK for 06 81 (dev→host)           09 FF 00 00 01 06 81 0A 00 9A
Set sound modes → ANC              08 EE 00 00 00 06 81 12 00 00 50 00 00 00 00 00 00 DF
   (body: ANC, manual 5 / adaptive weak, full transparency, NC manual, wind off, 0, transport, RT off)
Same, but ambient = Transparency   08 EE 00 00 00 06 81 12 00 01 50 00 00 00 00 00 00 E0
Same, but ambient = Normal         08 EE 00 00 00 06 81 12 00 02 50 00 00 00 00 00 00 E1
Spatial audio on, Music            08 EE 00 00 00 10 81 0D 00 01 00 00 95
Touch tone on                      08 EE 00 00 00 01 83 0B 00 01 86
Right double press → Play/Pause    08 EE 00 00 00 04 81 0D 00 01 00 66 EF
   (side 1, button_id 0, action 0x66 = Play/Pause both linked and solo)
Full state reply header            09 FF 00 00 01 01 01 A2 00 …152-byte body… <checksum>
```

---

## 12. What `scprobe` and the app send

Both use `SoundcoreKit`'s `SoundcoreDevice`, so they send exactly the same packets.

| When | Packets |
|---|---|
| Connect | `01 01` RequestState (§6.1); if dual connection is on, `0B 01` (§6.8) |
| While connected | `01 01` again every 5 minutes and when the menu opens: the case battery has no push |
| Any setting change | the one write from §7.2 for that setting, built from the last state read, then wait for the ACK. EQ, spatial audio, button reset, LDAC and dual connection also re-read the state afterwards |

Rules every write follows:
- The model must be confirmed by the vendor UUID suffix (`1202C`/`D1202`), otherwise writes are
  refused.
- Sound-mode writes copy the 8-byte block, change only the requested field, and apply
  OpenSCQ30's normalizations (manual level 1–5; wind bits 0–1). The read-only adaptive nibble
  and the unknown byte 5 are sent back as reported (§6.2). They refuse if another enum byte is
  unknown.
- EQ writes need both buds linked (as in OpenSCQ30) and send the HearID block back as reported
  (§7.3).
- Button writes change only the nibble for the current TWS state (§8.7). So do sound-mode
  cycle writes (§6.10), which also re-read the state to confirm the earbuds stored them.
- If the earbuds don't acknowledge a write (3 attempts, §3), the cached state is rolled back and
  re-read.
- The connection only ever uses the vendor service (§1), never the Serial Port or OTA channels.

Example: for the real R60i NC capture (sound modes `02 55 00 01 01 00 00 01`), switching to
Transparency sends `08 EE 00 00 00 06 81 12 00 01 55 00 01 01 00 00 01 E8`. This is tested in
`SoundcoreKit/Tests/SoundcoreKitTests/R60iCaptureTests.swift`.
