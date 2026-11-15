# Proposal: AirPlay receiver applet for Squeezebox Radio / Touch

Status: **idea / proposal**, not started. This document is meant as a
starting point for a discussion with the author of Standalone Base and
Spotify Connect (Sjoerd Brandsma, [ssbrandsma](https://github.com/ssbrandsma)),
or anyone who wants to pick it up.

## Goal

An applet, working name **AirPlay Receiver**, that makes a Squeezebox Radio or
Touch appear as an AirPlay speaker on iPhone, iPad and Mac, and plays
directly on the device without LMS, just like Spotify Connect.

Scope for a first version: **AirPlay 1 (RAOP)**, single speaker.
AirPlay 2 is discussed at the end as a possible later step.

## Why it is feasible

| | ESP32 (where AirPlay already works) | Squeezebox Radio |
|---|---|---|
| CPU | 240 MHz Xtensa, 2 cores | 532 MHz ARM1136, 1 core |
| RAM | 520 KB (+ PSRAM) | 64 MB |
| OS | FreeRTOS | Linux 2.6.26 (SqueezeOS) |

[squeezelite-esp32](https://github.com/sle118/squeezelite-esp32) already runs
an AirPlay 1 receiver on an ESP32. The work per second of audio is AES
decryption plus ALAC decoding of a 44.1 kHz / 16-bit stereo stream, which is
light for the Radio's CPU.

The difficult parts are not CPU. They are the old kernel, the old userland and
getting audio into SqueezePlay's player. **Spotify Connect has already solved
all three.**

## Learn from Spotify Connect

Repository: <https://github.com/ssbrandsma/squeezebox-radio-spotify-connect>

| Concern | How Spotify Connect solves it | Reuse for AirPlay |
|---|---|---|
| Building for the Radio | `build/build-native.sh`: Rust/C cross-compiled to `armv5te-unknown-linux-musleabi`, `-mfloat-abi=soft`, `target-cpu=arm926ej-s`, fully static (`+crt-static`, `-no-pie`) | Same toolchain and flags for the AirPlay daemon (C, so plain `arm-linux-gnueabi-gcc` + musl) |
| Linux 2.6 kernel | `native/linux26-compat/linux26-compat.c`, linked with `--wrap=epoll_create1,eventfd,socket,accept4`: fallbacks for syscalls missing on 2.6.26 | Link the same shim |
| Service discovery | librespot built `with-libmdns`: announces itself over mDNS (`_spotify-connect._tcp`) | AirPlay needs `_raop._tcp` (and `_airplay._tcp`) over the same mDNS approach |
| Process lifecycle | `native/supervisor/main.rs`: small supervisor that starts, restarts and stops librespot, owned by the applet | Same pattern: supervisor starts the AirPlay daemon |
| Audio into SqueezePlay | `native/bridge/bridge.rs`: single-client local HTTP server; `applet/SpotifyPlayback.lua` points SqueezePlay's own player at it (`playback.header = "GET ..."`, `decode:start(...)`, `playback:_streamConnect(host, port)`) | Same: a loopback HTTP stream that SqueezePlay plays (see below) |
| Metadata / Now Playing | `native/metadata`, `spotify-metadata-event`, `SpotifyNativeNowPlaying.lua`, publishing via Standalone Base's Now Playing API | AirPlay sends title/artist/album (DAAP) and artwork: publish through the same Standalone Base interface |
| Who owns playback | `SpotifyOwnership.lua`: hands playback back and forth with Standalone Radio and LMS | Same module/pattern so AirPlay, Spotify and Radio don't fight |
| Volume | `setRemoteVolume` in `SpotifyPlayback.lua` | Map AirPlay volume (-30..0 dB, -144 = mute) to the same call |
| Packaging | Applet ZIP with Lua + static binaries at archive root, `chmod 755` by the applet, nothing written outside `applets/` | Identical |

Standalone Base also matters: it provides the device-local infrastructure
(Now Playing, ownership, storage). AirPlay 1 itself does not need TLS, so the
HTTPS proxy is not involved.

## Existing AirPlay code to build on

Pick **one** receiver implementation:

1. **philippe44's RAOP receiver** (as used in squeezelite-esp32 and in
   philippe44's LMS bridges). Small, portable C designed for constrained
   targets. It has its own minimal mDNS responder (`mdnssvc`) and ALAC decoder.
   This is probably the best fit for a static ARMv5 build.
   - <https://github.com/philippe44/libraop>
   - <https://github.com/sle118/squeezelite-esp32> (`components/raop`)
2. **shairport-sync** in classic (AirPlay 1) mode. Most complete and widely
   used, but pulls in more dependencies (avahi or tinysvcmdns, popt, libconfig,
   OpenSSL/mbedTLS, ALAC). Heavier to build statically.
   - <https://github.com/mikebrady/shairport-sync>

Recommendation: start with philippe44's code. It is smallest and already
proven on hardware weaker than the Radio.

## Proposed architecture

```
iPhone/Mac ──RAOP (RTSP + RTP, AES, ALAC)──► airplay-receiver (static ARM binary)
                                               │ decoded PCM
                                               ▼
                                        loopback HTTP :<port>  (like ogg-http-bridge)
                                               │
                         SqueezePlay player ◄──┘  (AirPlayPlayback.lua, like SpotifyPlayback.lua)
                                               │
                                          Radio speaker / line out

airplay-supervisor ── starts/stops receiver (like spotify-supervisor)
metadata events ──► Standalone Base Now Playing (like spotify-metadata)
```

### Audio route into SqueezePlay

Spotify Connect streams **Ogg Vorbis** (librespot passthrough) and starts
SqueezePlay's decoder with mode `'o'`. AirPlay delivers ALAC, which the receiver
decodes anyway, so the simplest route is:

- the receiver writes **raw PCM** (16-bit, 44.1 kHz, stereo) to the loopback
  HTTP stream, and
- the Lua side starts SqueezePlay's **PCM decoder** (`'p'`) with the matching
  format parameters, instead of `'o'`.

Alternative: encode to FLAC (`'f'`) to reduce loopback bandwidth. That isn't
needed locally, and costs CPU.

### Latency and timing

AirPlay tells the receiver *when* to play each packet. SqueezePlay adds its own
buffering (stream buffer and output buffer). For AirPlay 1:

- the receiver reports a latency (classic RAOP uses about 2 s, ~88200 frames),
  which leaves room for SqueezePlay's buffer;
- the receiver should **drop or pad** samples to keep the stream on time,
  instead of relying on SqueezePlay to sync;
- lip-sync with video on a Mac/iPhone will be approximate. Music is fine.

Synchronising with *other* AirPlay speakers is not a goal for v1.

## Milestones

1. **Proof of concept on the device**: cross-compile philippe44's receiver
   statically for `armv5te-unknown-linux-musleabi` with the linux26-compat shim.
   Run it by hand over SSH, write PCM to a file, check that the iPhone sees
   the speaker and the file plays correctly.
2. **Playback**: add the loopback HTTP output (or reuse Spotify's bridge
   pattern), plus `AirPlayPlayback.lua` modelled on `SpotifyPlayback.lua`
   using decoder `'p'`.
3. **Applet**: Meta/Applet Lua, supervisor, start/stop from the Home menu,
   speaker name = device name, volume mapping.
4. **Integration**: ownership hand-over with Spotify Connect, Standalone Radio
   and LMS; Now Playing title/artist/artwork through Standalone Base.
5. **Packaging**: same layout as Spotify Connect; target `baby` and `fab4`;
   add to this repository's build like Spotify Connect.

## Risks and open questions

- **Static build of the receiver** against musl with the 2.6 shim may need
  small patches (e.g. `epoll`, `eventfd`, `accept4` usage). The shim covers
  the same calls librespot needed.
- **Two mDNS responders** (librespot's and the AirPlay one) on the same device:
  check they coexist on port 5353 (SO_REUSEPORT behaviour on 2.6.26), or share
  one responder.
- **Memory** with Spotify Connect installed too: both daemons are small, but
  measure RSS on the device.
- **Storage**: like Spotify Connect, likely recommend Extended Storage.
- **Licensing**: philippe44's code and shairport-sync are open source (check
  each licence for redistribution of static binaries alongside the applet).

## AirPlay 2 (later, maybe)

AirPlay 2 adds multi-room and is what newer iOS features expect. It requires:

- shairport-sync in AirPlay 2 mode,
- **nqptp** (PTP timing daemon, needs privileged ports 319/320 and precise
  timing),
- FFmpeg / libplist / libsodium / libgcrypt and more.

On a 2.6.26 kernel with soft-float userland this is a significantly bigger
project, and the timing precision through SqueezePlay's buffers is doubtful.
Recommendation: get AirPlay 1 solid first; most users only want "play from my
phone to this speaker".
