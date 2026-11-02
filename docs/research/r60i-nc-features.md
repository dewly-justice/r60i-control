# Soundcore R60i NC (D1202C): official features vs. OpenSCQ30 support

**Date:** 2026-11-02 · **OpenSCQ30 reference:** `vendor/OpenSCQ30` @ `e75a68b` (2026-10-29)
**Path shorthand:** `sc/…` = `vendor/OpenSCQ30/lib/src/devices/soundcore/…` (same as `docs/protocol.md`)

## Summary

1. **First-party sources confirm every R60i NC setting that OpenSCQ30's D1202 module encodes**: Adaptive, Manual (levels 1–5) and Multi-Scene ANC; real-time adaptive ANC; wind noise reduction; transparency; EQ presets and custom EQ; spatial audio (Music/Movie/Gaming); LDAC; dual connection; touch-control remapping; and volume limit ("Safe Volume"). Build all of them.
2. **"50 ms low-latency game mode" on this model is Spatial Audio › Gaming Mode** (Soundcore KB). Use the D1202 spatial-audio packet `10 81` with mode `3`. Never send the `01 87` gaming-mode flag, which OpenSCQ30 only uses for other models.
3. **LDAC and spatial audio exclude each other** (official FAQ). Grey out spatial audio while LDAC is on. LDAC is "only available on Android devices" (manual), so on a Mac the toggle only affects the other connected phone.
4. **Adaptive ANC value 5 is not unique to our buds.** Another R60i NC on firmware 04.89 (OpenSCQ30 #268) reports `5` with real-time adaptive on, and a third (#311) reports `1`. OpenSCQ30's R50i NC/P30i module reads the same kind of nibble as "N/5". No first-party document describes adaptive levels, so keep the value read-only and show it raw, if at all.
5. **No public firmware release notes exist.** The firmware versions people have posted are: P31i 01.83 and 02.89; R60i NC **04.89** (three reports, May–Jun 2026). Ours is 03.89. Whether 03.89 is older than 04.89 can't be confirmed. Every R60i NC state packet seen (03.89, 04.89) is 152 bytes and decodes cleanly with the D1202 layout. No source reports a layout change.
6. **Don't build** these. No protocol exists anywhere: Fit Test, the HearID test, the Anka AI assistant / AI Translation, and firmware update. OpenSCQ30 encodes these only for other models: "add Normal to the long-press cycle", adaptive sensitivity, find earbuds, wear detection, and the gaming-mode flag.
   *Update (same day):* the long-press cycle turned out to be readable after all. D1202's state byte 0x76, which OpenSCQ30 skips, sits where the A3968 keeps `AmbientSoundModeCycleTws`, and holds the documented default. It is now built with `06 82`; see `docs/protocol.md` §6.10.
7. **Upstream:** there are no commits after `e75a68b`. Two open issues (#423, #424, both 2026-10-27) affect the D1202 sound-modes path: inverted change notification, and round-tripping of byte 5 and the wind-detected bit. Read them before writing `06 81`.
8. **Build, but verify on hardware first.** Touch tone, low-battery prompt and the auto power-off duration are in the D1202 module, but no first-party document mentions them as app settings. Toggle each one and re-read `01 01` before shipping it.

## How sources were read

- **Manual:** the official English user guide is "soundcore R60i NC User Guide (D1202C)", from <https://service.soundcore.com/article-description/soundcore-R60i-NC-User-Guide-D1202C>. The PDF is <https://salesforce-knowledge-download.s3.us-west-2.amazonaws.com/000030778/en_US/000030778.pdf>. It is byte-identical (MD5 `1830deb9…`) to the P31i guide `000029164.pdf`. The PDF was created on 2025-10-24 and is titled for both models ("soundcore P31i / R60i NC"). It is cited below as **[M]**.
- **Support site:** the shared support page is <https://service.soundcore.com/product-description/a08e2000002muutAAA>, cited as **[SP]**. It lists Bluetooth 6.1 and SBC/AAC/LDAC. Its article pages render client-side, so I read the article text from the site's own JSON endpoint (`POST https://help.anker.com/support/api/gcs/knowledge/content` with `{urlName, language}`). Each article's public URL is `https://service.soundcore.com/article-description/<urlName>`. They are cited as **[KB-…]**, with the urlNames listed in the appendix.
- **R60i NC product page:** I could not reach it. `soundcore.com/ae-en/products/soundcore-r60i-nc-d1202` returns a 301 to `store.anker.com/ae`, and the `/uk` and `/ca` variants return 404. In its place I used the US **P31i** product page (same hardware, D1202), cited as **[P31i]**: <https://us.soundcore.com/products/d1202-p31i-wirless-earbuds-with-anc>. Its Shopify JSON shows it was created on 2025-10-23 and published on 2025-10-28, with SKUs `D1202Z11/21/31/51`.
- **R60i NC launch press release:** soundcore/Anker's press release (Kuala Lumpur, 2025-11-12, via PRNewswire), as reproduced on a third-party host: <https://www.itiger.com/news/2582347976>. Cited as **[PR]**.
- Anything marked **(secondary)** comes from reviews, forums or user reports.

## Feature table

| Feature | In Soundcore app for R60i NC? (source) | OpenSCQ30 D1202 support (file:line) | Recommendation |
|---|---|---|---|
| Ambient mode: Noise Cancellation / Normal / Transparency | **Yes.** [M] "AMBIENT SOUND"; [KB-ANCTOUCH] | `sc/d1202.rs:51`; `sc/d1202/modules/sound_modes/setting_handler.rs:36-38, 87-89`; byte 0 of `sc/d1202/structures.rs:31-46` | **Build** |
| NC mode: Adaptive / Manual / Multi-Scene | **Yes.** "Noise Cancellation > Mode > Adaptive ANC/Manual Mode/Multi-Scene ANC" [KB-ANC] | `sc/d1202/modules/sound_modes/setting_handler.rs:42-44, 96-98`; enum `sc/d1202/structures.rs:106-112` | **Build** |
| Manual ANC level 1–5 | **Yes.** "5 levels, ranging from 1 (minimum) to 5 (maximum)" [KB-LEVEL]; slider [KB-BGNOISE] | `sc/d1202/modules/sound_modes/setting_handler.rs:49-55` (range `1..=5`), `:100-103` | **Build** |
| Multi-Scene ANC scene (Transport / Outdoor / Indoor) | **Yes** for Multi-Scene ANC [KB-ANC]. The scene names don't appear in first-party docs; the user sees them in the app | `sc/d1202/modules/sound_modes/setting_handler.rs:56-58, 108-110`; enum `sc/d1202/structures.rs:114-120` | **Build.** Check the labels against the app |
| Real-time adaptive ANC | **Yes.** "Enable Real-time Adaptive ANC in the app" [KB-ANC] | `sc/d1202/modules/sound_modes/setting_handler.rs:70-72, 93-95` | **Build** |
| Adaptive ANC strength/level (low nibble of sound-modes byte 1) | **Not documented.** The product page only says adaptive "automatically chooses the best noise-cancelling level" [P31i] | Read-only: `sc/d1202/modules/sound_modes/setting_handler.rs:45-48, 99`. Names Weak/Moderate/Strong `sc/common/structures/manual_adaptive_noise_canceling.rs:132-137`. Unknown values become Weak (`:145-149`) | **Build read-only.** Show the raw value in diagnostics only, and echo it unchanged on writes (protocol.md §6.2) |
| Wind noise reduction | **Yes.** "turn on Wind Noise Reduction on the Noise Cancellation home page" [KB-WIND]; [KB-ANC] step 6 | `sc/d1202/modules/sound_modes/setting_handler.rs:59-61, 104-106`; bit 0 of `sc/common/structures/wind_noise.rs:20-30` | **Build** |
| Wind currently detected | Not documented | `sc/d1202/modules/sound_modes/setting_handler.rs:62-69, 107` (read-only, bit 1) | **Build read-only** (optional) |
| Transparency type: Full / Vocal | Transparency **yes** [M]. "Vocal mode" doesn't appear in first-party docs. Both 04.89 R60i NC packets have the byte set to `1` = Vocal (#268, #311) | `sc/d1202/modules/sound_modes/setting_handler.rs:39-41, 90-92`; enum `sc/d1202/structures.rs:99-104` | **Build.** Mark it unverified until it is seen in the app |
| Adaptive ANC sensitivity (0–10) | Not documented | Not in D1202. Exists for A3959 only: `sc/a3959/modules/sound_modes/setting_handler.rs:64-72` | **Don't build: other-model packet only** |
| Fit Test | **Yes.** [M] "Take a fit test in the soundcore app"; [KB-WEAR]; [KB-ANC] | Not in OpenSCQ30 (`grep -ri fit lib/src` finds no fit-test code) | **Don't build: no protocol** |
| EQ presets | **Yes.** "Experiment with different EQ modes" [KB-SQ]; "select 'Bass Booster' from the EQ options" [KB-BASS] | `sc/d1202.rs:53-55`; presets `sc/common/modules/equalizer.rs:261-411`; write `sc/d1202/packets/outbound.rs:19-99` | **Build.** Hide while one bud is out, as OpenSCQ30 does: `sc/d1202/modules/equalizer.rs:62`, `sc/common/modules/equalizer/setting_handler.rs:136-145` |
| Custom EQ | **Yes.** "go to Custom EQ and adjust" [KB-BASS] | Same as presets | **Build** |
| HearID sound test / HearID EQ | **Yes.** "Tap HearID Sound Test" [KB-HEARID]; [M] | HearID is parsed and echoed only. OpenSCQ30 says "We don't support enabling hear id anyway": `sc/d1202/packets/outbound.rs:56-58` | **Don't build: no protocol.** Keep echoing the bytes |
| Spatial audio on/off + Music / Movie / Gaming | **Yes.** "Sounds Effects > Mode > Spatial Audio > Music Mode/Movie Mode/Gaming Mode" [KB-SPATIAL]; German KB adds that LDAC blocks it [KB-DE-APP] | `sc/d1202.rs:66`; `sc/d1202/modules/spatial_audio/setting_handler.rs:27-60`; enum `sc/d1202/structures.rs:146-152`; on/mode `sc/d1202/packets/outbound.rs:8-17`; off is sent via the EQ packet `sc/d1202/modules/equalizer/state_modifier.rs:145-176` | **Build.** Disable it while LDAC is on, and require both buds ("Wear both earbuds" [KB-SPATIAL]) |
| Game mode / low latency | **Yes**, as Spatial Audio › Gaming Mode: "If you require low latency, you can enable Gaming Mode via the app by going to Sound Effects > Spatial Audio > Gaming Mode" [KB-LATENCY]. "50ms Low Latency Game Mode" [PR] | Covered by `SpatialAudioMode::Gaming = 3`, `sc/d1202/structures.rs:150` | **Build** as a spatial-audio mode |
| Standalone gaming-mode flag (`01 87`) | n/a | Not in D1202. `sc/common/modules/flag.rs:52-61`, used by `sc/a3959.rs:59`, `sc/a3947.rs:62`, `sc/a3957.rs:65` | **Don't build: other-model packet only** |
| LDAC | **Yes.** [M] "LDAC" (Android 8.0+; switching takes ~10 s); "More Settings > Sound Mode > Preferred audio quality LDAC" [KB-SQ]; codecs [SP] | `sc/d1202.rs:67`; `sc/common/modules/flag.rs:151-160` (set `01 FF`, push `01 7F`) | **Build.** Caveats: Android-only, blocks spatial audio, the codec switch may briefly drop audio (test it) |
| Dual connections (multipoint) | **Yes.** [M] "Dual Connections is enabled by default… can be disabled in the soundcore app"; [KB-DUAL]; works together with LDAC [KB-FAQ] Q4 | `sc/d1202.rs:38-42, 64`; `sc/common/modules/dual_connections.rs:34` | **Build** (on/off + device list) |
| Touch controls: single / double / triple / long, per side | **Yes.** Single tap Volume −/+ [KB-VOLTOUCH]; "Double Press/Triple Press/Long Press > Voice Assistant… 'Single Press' can't be used for this function" [KB-VA]; single and triple tap off by default [KB-TOUCH]; defaults [M] CONTROLS, [KB-FAQ] Q6 | `sc/d1202.rs:57, 93-151`; single press is limited to `COMMON_ACTIONS_MINIMAL` (`sc/d1202.rs:117`, `sc/common/modules/button_configuration.rs:167`) | **Build** |
| Reset controls to defaults | Not documented | `sc/d1202.rs:58-60` | **Build** |
| Call controls (answer / hang up) | Fixed: "Controls for the answer/hang-up function cannot be customized" [KB-CALLS] | n/a | **Don't build** (not configurable) |
| Add Normal mode to the long-press cycle | **Yes.** "You can add Normal mode via the Anker soundcore app" [KB-ANCTOUCH] | Not in D1202. The `06 82` packet is in `sc/common/packet/outbound/set_ambient_sound_mode_cycle.rs:15-24`, module `sc/common/modules/ambient_sound_mode_cycle.rs:37`, used by e.g. `sc/a3959.rs:47`, `sc/a3947.rs:54`, `sc/a3954.rs:60` | **Don't build: other-model packet only** |
| Volume limit ("Safe Volume") | **Yes.** "disable the maximum volume limit by going to Safe Volume > Limit High Volume" [KB-LOWVOL] | `sc/d1202.rs:62`; 75–100 dB in 5 dB steps `sc/common/modules/limit_high_volume/setting_handler.rs:56, 84` | **Build** |
| dB-reading refresh rate | Not documented | Same module (`sc/common/structures/limit_high_volume.rs`) | **Build** as an advanced setting |
| Auto power-off | Only the fixed rule is documented: "automatically power off after 30 minutes of inactivity without a connection" [KB-POWER]. An in-app setting isn't documented. User packets show 10 min (#268) and 60 min (#311) (secondary), so it is probably changeable | `sc/d1202.rs:68-70`; durations `sc/common/modules/auto_power_off.rs:102` | **Build.** Verify on hardware |
| Touch tone | Not documented | `sc/d1202.rs:71`; `sc/common/modules/flag.rs:41-50` | **Build.** Verify on hardware |
| Low-battery voice prompt | Not documented | `sc/d1202.rs:72`; `sc/common/modules/flag.rs:118-127` | **Build.** Verify on hardware |
| Battery L/R, charging, case battery, TWS link | Case LED shows battery [M] | `sc/d1202.rs:74-82` | **Build read-only** |
| Firmware version, serial | Firmware updates run through the app [M] | `sc/d1202.rs:83` | **Build read-only** |
| Firmware update (OTA) | **Yes** [M] "FIRMWARE UPDATE" | Not in OpenSCQ30 | **Don't build: no protocol** (out of scope per protocol.md) |
| AI assistant "Anka", AI Translation | **Yes** [M] "AI ASSISTANT", "AI TRANSLATION"; [P31i]; [PR] | Not in OpenSCQ30 | **Don't build: no protocol** (phone/cloud features) |
| Find my earbuds | Not in any first-party doc found | Not in D1202. A3954 only (`sc/a3954/structures.rs:155`) | **Don't build: other-model packet only** |
| Wear detection / auto-pause | Not in first-party docs. A forum user wishes it existed (secondary: <https://community.eufy.com/t/5794905>) | Not in D1202. `sc/common/modules/flag.rs:129-138`, used by `sc/a3953.rs:116`, `sc/a3954.rs:79`, `sc/a3957.rs:63` | **Don't build: other-model packet only** |
| Sleep mode / sleep features | Not in first-party docs | Not in D1202. Sleep A30 (D1301) only (`vendor/OpenSCQ30/CHANGELOG.md:21`) | **Don't build: other-model packet only** |
| Google Fast Pair | Yes [M] | n/a (handled by the phone OS) | n/a |

Behaviors the app UI should reflect:

- **One bud worn means Normal mode.** "switching to listening from one earbud will switch the system to Normal mode" [KB-FLUCT]. The default mono long-press cycles Normal → Transparency [M] CONTROLS.
- **Default button map** (TWS): L double = next track, R double = play/pause, L/R hold 2 s = ANC ↔ Transparency [M] CONTROLS; [KB-FAQ] Q6. This matches the OpenSCQ30 fixture bytes `63 66 … 44 44` (`sc/d1202.rs:182-183`).

## Firmware / feature news

No official firmware release notes for the P31i/R60i NC were found. The support site's firmware articles ([KB-FW], [KB-DE-APP] §1–2) only describe the update procedure. The manual says updates are offered inside the app [M]. A Soundcore community user asking whether 04.89 is the latest got no answer (below). The dated entries below are everything found.

| Date | Event | Source |
|---|---|---|
| 2025-10-23 / 10-28 | P31i (D1202) product page created / published on the soundcore US store. Features: real-time adaptive ANC up to 52 dB, LDAC + Hi-Res, AI translation in 100+ languages, 6 mics with wind-noise reduction for calls | [P31i] (Shopify JSON timestamps) |
| 2025-10-24 | English user guide (shared by P31i and R60i NC) created. App features listed: "ambient sound modes, EQ settings, Spatial Audio, LDAC, AI Translation, HearID sound, firmware updates". Also covers the Anka AI assistant and the fit test | [M] (PDF CreationDate) |
| 2025-11-12 | R60i NC Malaysia launch press release: "real-time adaptive active noise cancellation (up to -52dB)", "analyzes your environment every 0.007 seconds", spatial sound "in Music Mode or Movie Mode", LDAC with Hi-Res Gold, "50ms Low Latency Game Mode", AI Translation, BT 6.1, Fast Pair | [PR] |
| 2025-12-16 | Lowyat review: 50 ms game mode, LDAC, sound "preference test" (secondary) | <https://www.lowyat.net/2025/376129/soundcore-r60i-nc-lightning-reviews/> |
| 2026-03-17 | **P31i firmware 01.83** state packet posted. This is the same serial and firmware as the OpenSCQ30 test fixture (`sc/d1202.rs:176-185`) | <https://github.com/Oppzippy/OpenSCQ30/issues/237> |
| 2026-05-08 | **R60i NC / P31i firmware 04.89** state packet: ambient Normal, manual 5, **adaptive nibble 5**, NC Adaptive, wind on, real-time adaptive on, Vocal transparency, **LDAC on / spatial off**, custom EQ, HearID data present | <https://github.com/Oppzippy/OpenSCQ30/issues/268> (decoded by us) |
| 2026-05-09 | Community user, R60i NC: "Is this the latest update? 04.89". No reply (secondary) | <https://community.eufy.com/t/5795126> |
| 2026-06-10 | Community user: with spatial audio on, the right bud is silent. Staff answer is a generic reset procedure (secondary) | <https://community.eufy.com/t/5801851> |
| 2026-06-28 | **R60i NC firmware 04.89** state packet: ANC, manual 4, **adaptive nibble 1**, NC Manual, Vocal, single tap = vol −/+, triple = ambient cycle, auto-off 60 min, volume limit 95 dB (off) | <https://github.com/Oppzippy/OpenSCQ30/issues/311> (decoded by us) |
| 2026-07-07 / 07-08 | OpenSCQ30 adds D1202, then D1202C ("It functions the same as d1202"). Released in v2.10.0 | commits `858cb14`, `9cf8b91`; `vendor/OpenSCQ30/CHANGELOG.md:99` |
| 2026-08-14 | **P31i firmware 02.89** reported. Bug: turning spatial audio ("Surround Sound") off shifts the balance left | <https://github.com/Oppzippy/OpenSCQ30/issues/356> |
| 2026-08-31 → 10-21 | Soundcore support articles for P31i/R60i NC created (2026-08-31), most republished 2026-10-21. They are the first first-party mentions of Multi-Scene ANC, Real-time Adaptive ANC, Wind Noise Reduction, Safe Volume / Limit High Volume, Spatial Audio Gaming Mode as the low-latency option, and the single-tap volume option | [KB-*] metadata (`createdAt`, `LastPublishedDate`) |
| 2026-09-02 | OpenSCQ30 fix: D1202 must resend the D1202 set-EQ packet to turn spatial audio off. Released in v2.12.0 | commit `e7bcb7b`; `vendor/OpenSCQ30/CHANGELOG.md:53` |
| 2026-11-02 | Our buds: **firmware 03.89** on both. Adaptive nibble 5, spatial on (Music), LDAC off | `docs/protocol.md` §6.1 |

Firmware ordering is unclear. Versions seen so far: P31i 01.83 (Mar), P31i 02.89 (Aug), R60i NC 04.89 (May and Jun) and ours 03.89 (Nov). The leading digits could be a version (then ours is behind 04.89) or a hardware/region variant. The trailing `.89` matches across models. No source settles this. The only first-party way to check is the Soundcore app's firmware screen.

## OpenSCQ30 upstream

As of 2026-11-02 there are **no commits after `e75a68b`**. GitHub API: `master` was last pushed 2026-10-30T00:50Z, and the commits since 2026-10-29 are only `9152feb` and `e75a68b`. GitHub Discussions is disabled on the repo (`has_discussions: false`). I searched issues and PRs for D1202, R60i, P31i, "spatial audio" and "adaptive".

**Issues**

- [#424](https://github.com/Oppzippy/OpenSCQ30/issues/424) (open, 2026-10-27). "D1202 SoundModes round-trip": byte 5 is dropped on read and always written as `0`, and the read-only wind-detected bit (bit 1) is echoed back on writes (`sc/d1202/structures.rs:31-46`, `sc/common/structures/wind_noise.rs:28-30`). The reporter found this while auditing what a client writes to an R60i NC after a mic failure. They state there is no confirmed causal link.
- [#423](https://github.com/Oppzippy/OpenSCQ30/issues/423) (open, 2026-10-27). The `sound_modes_v2` packet handler uses `==` where it should use `!=`. As a result, a device-side mode change (`06 01` push) updates state but doesn't notify watchers. It affects D1202. This is OpenSCQ30-internal, but a reminder that our push handling must fire on change.
- [#217](https://github.com/Oppzippy/OpenSCQ30/issues/217) (closed 2026-07-08). The R60i NC support request. The maintainer needed btsnoop logs of the official app connecting. Support landed in `858cb14` and `9cf8b91`.
- [#237](https://github.com/Oppzippy/OpenSCQ30/issues/237) (P31i 01.83 packet), [#268](https://github.com/Oppzippy/OpenSCQ30/issues/268) and [#311](https://github.com/Oppzippy/OpenSCQ30/issues/311) (R60i NC 04.89 packets, closed as duplicates). These are the only public D1202-family state packets apart from ours. All are 152 bytes.
- [#356](https://github.com/Oppzippy/OpenSCQ30/issues/356) (closed, fixed in v2.12.0). On P31i 02.89, turning spatial audio off shifted the balance left. The cause was the wrong disable packet. It's the reason for protocol.md §7.4.
- [#350](https://github.com/Oppzippy/OpenSCQ30/issues/350) (closed). "Error connecting" to an R60i NC from Android. It was closed with no comment or root cause.
- [#324](https://github.com/Oppzippy/OpenSCQ30/issues/324) / PR [#327](https://github.com/Oppzippy/OpenSCQ30/pull/327) (open). An Android-side automation that switches to Transparency during calls, tested on a P31i. It only uses the existing ambient-mode write. This is a possible app-level idea for us that adds no new packets.
- [#333](https://github.com/Oppzippy/OpenSCQ30/issues/333) (open). A request for a spatial audio / "preference mode" widget toggle. The device isn't stated. "Preference" matches the app's "Preferred audio quality" (LDAC) wording.
- [#325](https://github.com/Oppzippy/OpenSCQ30/issues/325) (open). A P31i discovery problem on Windows. Not related to the protocol.

**PRs**

- [#372](https://github.com/Oppzippy/OpenSCQ30/pull/372) "Add macOS support" (open, 2026-09-14). An IOBluetooth RFCOMM backend. Its notes say SDP callbacks fire only on the real main thread, and RFCOMM can fail if the device is already connected through another profile. This is directly relevant to our Mac transport.
- [#414](https://github.com/Oppzippy/OpenSCQ30/pull/414) Liberty 5 Pro D1203 (open). A different family that uses a TLV state packet. Not applicable to D1202C.

**Commits that touch D1202** (`gh api …/commits?path=lib/src/devices/soundcore/d1202`):
`858cb14` add d1202 (2026-07-07) · `9cf8b91` add d1202c (2026-07-08) · `e7bcb7b` fix spatial-audio disable packet (2026-09-02) · `f2549fe` / `434c577` refactors (2026-09-03/06) · `7cfe336` show "both earbuds must be connected" for the EQ when TWS is disconnected (2026-10-16; applies to D1202 through `sc/d1202/modules/equalizer.rs:62`).

**No R60i NC fixture upstream.** `vendor/OpenSCQ30/tools/soundcore-device-faker/devices/d1202c.toml:1-8` has an empty state response, and all four D1202 tests use `DeviceModel::SoundcoreD1202` with P31i 01.83 data (for example `sc/d1202.rs:166-238`). None uses `SoundcoreD1202C`. No upstream issue mentions the adaptive value 5, spatial audio being specific to the R60i NC, or a newer firmware changing the state packet.

## Open questions

1. **What does the adaptive nibble mean on D1202C?** We've seen `5` (ours 03.89, #268 04.89, both with real-time adaptive on), `1` (#311, manual mode) and `0` (P31i 01.83). It could be a 1–5 level, as OpenSCQ30 reads it for A3959 (`sc/a3959/modules/sound_modes/setting_handler.rs:42-45`), or something else. Not confirmed for D1202C. Keep it read-only.
2. **Is 03.89 older than 04.89, and is an update pending?** Check the firmware screen in the Soundcore app. After any update, re-capture `01 01` and diff it against `Fixtures.r60iStateFrame`.
3. **Does the app show Vocal mode?** It also needs to confirm the Multi-Scene labels (Transport/Outdoor/Indoor) and whether touch tone, low-battery prompt and auto power-off duration appear for the R60i NC. First-party docs don't say. Check the app and the screenshots in `reference/`.
4. **Does toggling LDAC drop the RFCOMM link?** The manual says "Switching audio codecs takes about 10 seconds". Test with only the Mac connected before exposing the toggle.
5. **Should writes clear the wind-detected bit and preserve byte 5 (#424)?** OpenSCQ30 currently echoes bit 1 and writes `0` to byte 5. Our rule follows OpenSCQ30, so changing either would mean departing from the documented layout. This needs a decision.
6. **Can "add Normal to the long-press cycle" be done on D1202C?** The official app offers it [KB-ANCTOUCH], but OpenSCQ30 has no D1202 encoding. The unknown state byte at `0x76` (`33` in every D1202 packet seen) is unexplained. Do not use it.
7. **Product page:** the soundcore.com R60i NC product page could not be reached (301 to `store.anker.com/ae`, or 404). The R60i NC-specific marketing claims above come from the press release [PR] and the shared support site.
8. **Find earbuds:** a web-search snippet credited a retailer listing with "Find My Device". It was not verified and is not first-party. Ignore it unless a first-party source turns up.

## Appendix: support-article references

Base URL `https://service.soundcore.com/article-description/` + urlName. "Pub" is `LastPublishedDate`.

| Tag | urlName | Article # | Pub |
|---|---|---|---|
| KB-FAQ | `soundcore-P31i-R60i-NC-FAQ` | 000030686 | 2026-10-21 |
| KB-SPATIAL | `How-do-I-use-spatial-audio-with-my-P31i-R60i-NC` | 000030756 | 2026-10-21 |
| KB-ANC | `What-should-I-do-if-soundcore-P31i-R60i-NC-s-noise-cancellation-does-not-meet-my-expectations` | 000030725 | 2026-10-21 |
| KB-WIND | `What-should-I-do-if-I-hear-wind-noise-while-using-soundcore-P31i-R60i-NC-outdoors` | 000030727 | 2026-10-21 |
| KB-LATENCY | `What-should-I-do-if-there-is-a-delay-in-playback-between-my-P31i-R60i-NC-and-the-device` | 000030735 | 2026-10-21 |
| KB-LEVEL | `What-should-I-do-if-I-experience-dizziness-and-discomfort-when-using-ANC-mode-on-P31i-R60i-NC` | 000030726 | 2026-10-21 |
| KB-BGNOISE | `What-should-I-do-if-I-hear-background-noise-while-using-ANC-mode-on-P31i-R60i-NC` | 000030728 | 2026-10-21 |
| KB-ANCTOUCH | `How-do-I-switch-between-ANC-and-Transparency-Mode-via-touch-control-on-my-P31i-R60i-NC` | 000030762 | 2026-10-21 |
| KB-VOLTOUCH | `How-do-I-adjust-the-volume-via-touch-controls-on-my-P31i-R60i-NC` | 000030741 | 2026-10-21 |
| KB-VA | `How-do-I-trigger-my-phone-s-voice-assistant-via-P31i-R60i-NC` | 000030751 | 2025-10-24 |
| KB-CALLS | `How-do-I-answer-hang-up-calls-using-my-P31i-R60i-NC` | 000030759 | 2025-10-24 |
| KB-TOUCH | `Why-is-the-touch-control-not-responsive-at-times-on-my-P31i-R60i-NC` | 000030757 | 2026-10-21 |
| KB-LOWVOL | `What-should-I-do-if-the-volume-is-low-when-my-P31i-R60i-NC-is-connected-to-my-computer-phone` | 000030745 | 2026-10-21 |
| KB-FLUCT | `What-should-I-do-if-the-volume-fluctuates-suddenly-on-my-P31i-R60i-NC` | 000030746 | 2025-10-24 |
| KB-SQ | `What-should-I-do-if-I-experience-poor-sound-quality-when-using-soundcore-P31i-R60i-NC` | 000030742 | 2026-10-21 |
| KB-BASS | `What-should-I-do-if-the-bass-quality-is-poor-on-my-P31i-R60i-NC` | 000030744 | 2026-10-21 |
| KB-HEARID | `How-do-I-set-up-HearID-for-my-P31i-R60i-NC-via-the-app` | 000030755 | 2025-10-24 |
| KB-DUAL | `How-do-I-enable-Dual-Connection-on-P31i-R60i-NC` | 000030736 | 2025-10-24 |
| KB-WEAR | `How-do-I-wear-soundcore-P31i-R60i-NC` | 000030721 | 2026-10-21 |
| KB-POWER | `How-do-I-power-P31i-R60i-NC-on-or-off` | 000030758 | 2025-10-24 |
| KB-FW | `What-should-I-be-aware-of-when-updating-the-firmware-for-my-P31i-R60i-NC` | n/a | 2025-10-24 |
| KB-DE-APP | `https://service.soundcore.com/de/article-description/So-nutzt-du-deine-soundcore-P31i-R60i-NC-optimal-mit-der-soundcore-App` (German) | 000031149 | 2026-10-21 |
