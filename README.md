# Soundcore R60i NC for macOS

A native macOS controller for **Soundcore R60i NC** earbuds (model ID D1202C). It replaces the
Soundcore mobile app, which has no Mac version.

**Status: Phase 1.** The repo has `scprobe`, a command-line probe that proves the Bluetooth
transport and protocol against the real earbuds. The menu-bar app (Phase 2) comes next.

- Protocol: [`docs/protocol.md`](docs/protocol.md)
- Requirements: Apple Silicon Mac, macOS 27, Xcode 27 (Swift 6.4). No third-party dependencies.

## Build and run

```sh
swift build                                  # builds everything
swift test                                   # unit tests (no Bluetooth needed)

swift run scprobe                            # connect, read and print the earbuds' state
swift run scprobe --hexdump                  # same, logging every byte sent/received to stderr
swift run scprobe set-mode anc               # or: transparency | normal
swift run scprobe --listen 30                # read state, then print packets the earbuds push for 30 s
swift run scprobe list                       # list paired devices + their Soundcore RFCOMM service
swift run scprobe --help
```

You can combine options, e.g. `swift run scprobe --hexdump set-mode transparency --listen 10`.
The built binary is at `.build/debug/scprobe`; `swift build -c release` puts it in `.build/release/`.

Before running:
- Pair the earbuds with the Mac (System Settings → Bluetooth).
- Take them out of the case. They don't need to be playing audio.

scprobe finds them by name ("R60i") or by their Soundcore service UUID. Use `--address` if
several devices match.

### Bluetooth permission

The first Bluetooth call shows a macOS permission prompt. Command-line tools usually inherit
permission from the **terminal app** you run them in (Orca, Terminal, iTerm…), so the prompt
names that app. If you denied it, or nothing works:

1. System Settings → Privacy & Security → **Bluetooth** → enable your terminal app.
2. Quit and reopen the terminal, then run scprobe again.

The binary also embeds an `Info.plist` (`Sources/scprobe/Info.plist`, bundle ID
`dev.local.scprobe`) with `NSBluetoothAlwaysUsageDescription`, so macOS has a usage string
whichever process it attributes the access to.

### What scprobe sends

Only two commands (see `docs/protocol.md` §12):
- `01 01` reads the state.
- `06 81` sets sound modes, used by `set-mode`. It sends back the full 8-byte sound-modes
  block it just read, with only the mode byte changed. It refuses if the earbuds report a
  value outside the documented set, or if the model can't be confirmed as D1202/D1202C.

It connects only to the Soundcore vendor service (channel 15 on a tested R60i NC). The
earbuds also publish firmware-update channels (`TOTA`, `BESOTA`), and scprobe never opens
those. Exiting closes only the RFCOMM channel. The earbuds' audio connection to the Mac
stays up.

### Troubleshooting

| Symptom | Try |
|---|---|
| `No paired Bluetooth devices are visible` | Bluetooth permission for your terminal (above) |
| `Couldn't find a paired Soundcore R60i NC` | `scprobe list`, then `--address AA-BB-CC-DD-EE-FF` |
| `Found no Soundcore RFCOMM service` | Make sure the buds are connected to this Mac; `scprobe list` shows every RFCOMM service they publish |
| `Opening the RFCOMM channel failed` | Take the buds out of the case; close the Soundcore app on your phone; retry |
| `No reply to 01 01` | Re-run with `--hexdump` and send me the output |

## Layout

```
Package.swift
Sources/SoundcoreProtocol/   pure-Swift framing, parsing, encoding (no Bluetooth)
Sources/scprobe/             IOBluetooth RFCOMM transport + CLI
Tests/                       unit tests (protocol fixtures, report rendering, delegate wiring)
docs/protocol.md             the protocol, with sources
vendor/OpenSCQ30             reference checkout (git-ignored)
```

To recreate the reference checkout:
`git clone https://github.com/Oppzippy/OpenSCQ30 vendor/OpenSCQ30 && git -C vendor/OpenSCQ30 checkout e75a68b`

## Credits

The protocol knowledge comes from [OpenSCQ30](https://github.com/Oppzippy/OpenSCQ30) by
Oppzippy (GPL-3.0). This project reimplements the protocol in Swift from the description in
`docs/protocol.md`; no OpenSCQ30 code is ported. Two things are taken from OpenSCQ30's tests as
data: the D1202 state-packet byte fixture and the frame test vectors used in our unit tests.
