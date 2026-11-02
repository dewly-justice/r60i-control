# R60i Control

A native macOS menu bar app for **Soundcore R60i NC** earbuds (model ID D1202C). It replaces the
Soundcore mobile app, which has no Mac version. Built for personal use on Apple Silicon and
macOS 27.

- **Menu bar:** battery for left, right and case; Noise Cancelling / Normal / Transparency;
  adaptive ANC; manual ANC strength; scene and transparency options; wind noise reduction.
- **Settings (⌘,):** noise control details, equalizer (22 presets plus custom 8-band), spatial
  audio, LDAC, touch controls per gesture per earbud, which modes Switch Sound Mode cycles
  through, dual connection and its device list, auto
  power-off, touch tone, low-battery prompt, volume limit, device info.
- **Behavior:** like AirPods in macOS, the app only shows up while the earbuds are connected to
  the Mac. The menu bar icon appears when they connect and goes away when they disconnect, and
  Settings shows the earbud panes only while they're connected. It connects automatically,
  reconnects after drops and sleep, and reads the earbuds' state on connect so the UI always
  matches them. Optional global shortcut to cycle the sound mode.

Only settings whose packets are documented in [OpenSCQ30](https://github.com/Oppzippy/OpenSCQ30)
are offered; see [`docs/protocol.md`](docs/protocol.md). Firmware updates and HearID are out of
scope.

## Build and run

Requirements: Apple Silicon Mac, macOS 27, Xcode 27 (Swift 6.4), and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make app      # generate R60iControl.xcodeproj with XcodeGen and build "build/R60i Control.app"
make run      # build, then open the app
make test     # SoundcoreKit unit tests (no Bluetooth needed)
make probe ARGS="--hexdump"   # the command-line probe, see below
make clean
```

`make app` signs with your "Apple Development" certificate if the keychain has one, so macOS
keeps the Bluetooth permission across rebuilds. Without one it signs ad hoc, and macOS may ask
for Bluetooth permission again after each rebuild. To work in Xcode, run `make project` and
open `R60iControl.xcodeproj`. The project file is generated, so edit `project.yml` instead.

To install, copy `build/R60i Control.app` to `/Applications`. Turn on **Open at Login** in
Settings → General.

### First launch

1. Pair the earbuds with the Mac in System Settings → Bluetooth (once).
2. Open the app. It asks for Bluetooth permission; if you said no, enable it in System
   Settings → Privacy & Security → Bluetooth. Until it has connected once, it opens Settings to
   show what it's waiting for.
3. Take the earbuds out of the case. The app connects in a few seconds and its icon appears in
   the menu bar.

The app has no Dock icon, and no menu bar icon while the earbuds are away. To reach Settings
then (for example to change the shortcut or quit with ⌘Q), open the app again from Finder or
Spotlight.

## Things to know

- **One controller at a time.** The earbuds accept a single control connection. While the
  Soundcore app on your phone holds it, the Mac can't connect. Close the phone app.
- **Touch controls follow the current situation.** As in the Soundcore app, editing a control
  changes the two-earbud mapping when both buds are in use, and the one-earbud mapping when only
  one is.
- **The equalizer needs both earbuds.** Like OpenSCQ30, the app only changes the EQ while both
  buds are in; otherwise the other bud would keep its old EQ.
- **EQ, spatial audio and LDAC interact.** The earbuds turn spatial audio off whenever the
  equalizer changes. LDAC and spatial audio can't be on together (Soundcore FAQ), so the app
  greys out whichever one is blocked. Gaming, under Spatial Audio, is the low-latency mode.
- **LDAC** only matters for Android devices; Macs don't use it. If the earbuds acknowledge
  "LDAC on" but keep it off, the app says so instead of pretending it worked.

**Not supported**, because no packet for it is documented for this model:
Fit Test, the HearID hearing test, the AI assistant and AI Translation, and firmware updates.
The earbuds have no swipe or head gestures. See
[`docs/research/r60i-nc-features.md`](docs/research/r60i-nc-features.md).

## Troubleshooting

| Symptom | Try |
|---|---|
| No menu bar icon | The earbuds aren't connected to this Mac. Open the app again to see their status in Settings, and click Connect there or pick them in the Bluetooth menu |
| "Not paired with this Mac" | Pair the earbuds in System Settings → Bluetooth, and allow Bluetooth for the app in Privacy & Security |
| "Couldn't connect" | Close the Soundcore app on your phone, then Try Again |
| Nothing happens after granting Bluetooth permission | Quit and reopen the app |
| See what the app sends | `log stream --info --debug --predicate 'subsystem == "dev.local.R60iControl"'` |

## scprobe: command-line probe and test harness

`scprobe` drives the same `SoundcoreDevice` model as the app. Every setting change re-reads
the state and prints exactly what changed, so it doubles as the hardware test harness.

```sh
make probe                                     # read and print everything
make probe ARGS="--hexdump"                    # also log every byte to stderr
make probe ARGS="set-mode anc"                 # anc | transparency | normal
make probe ARGS="set eq acoustic"              # any setting; see --help for the list
make probe ARGS="devices"                      # dual-connection devices
make probe ARGS="--listen 30"                  # print packets the earbuds push for 30 s
make probe ARGS="list"                         # paired devices and their RFCOMM services
make probe ARGS="--help"
```

Run it from a terminal app that has Bluetooth permission. The binary embeds an Info.plist
(bundle ID `dev.local.scprobe`) with a Bluetooth usage string.

## Layout

```
project.yml                  XcodeGen spec for the app (the .xcodeproj is generated)
Makefile                     one-command build, run, test, probe
App/                         SwiftUI menu bar app (MenuBarExtra + Settings)
SoundcoreKit/                Swift package
  Sources/SoundcoreKit/
    Protocol/                framing, state parsing, every write encoder (pure Swift)
    Bluetooth/               IOBluetooth RFCOMM link, SDP discovery, errors
    Device/                  packet session (§3 rules) and the @Observable SoundcoreDevice
  Sources/scprobe/           command-line probe
  Tests/                     unit tests: OpenSCQ30 test vectors, real-device captures, fake link
docs/protocol.md             the protocol, with sources and hardware verification (§7.5)
vendor/OpenSCQ30             reference checkout (git-ignored)
```

To recreate the reference checkout:
`git clone https://github.com/Oppzippy/OpenSCQ30 vendor/OpenSCQ30 && git -C vendor/OpenSCQ30 checkout e75a68b`

## Credits and license

The protocol knowledge comes from [OpenSCQ30](https://github.com/Oppzippy/OpenSCQ30) by
Oppzippy (GPL-3.0). This project reimplements the protocol in Swift from the description in
`docs/protocol.md`; no OpenSCQ30 code is ported. Some test data comes from OpenSCQ30's tests:
the D1202 state-packet fixture and the frame, EQ, spatial-audio, button and dual-connection
test vectors. Other fixtures were captured from a real R60i NC.

Soundcore is a trademark of Anker Innovations. This project is not affiliated with Anker.
