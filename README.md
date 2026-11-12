# SBRadio – automated Lyrion applet repository

Builds the Squeezebox Radio/Touch applets from

- [ssbrandsma/SBStandalone](https://github.com/ssbrandsma/SBStandalone) → `StandaloneRadio`
- [ssbrandsma/squeezebox-radio-spotify-connect](https://github.com/ssbrandsma/squeezebox-radio-spotify-connect) → `SpotifyConnect`

and publishes them as GitHub Releases plus a combined `extensions.xml`.

## How it works

```
upstream VERSION changes ──► GitHub Action (daily / manual)
                               ├─ upstream packaging script builds ZIP
                               ├─ GitHub Release  <Name>-v<version>  (ZIP + XML fragment)
                               └─ extensions.xml committed to this repo (HTTPS release URLs)
                                              │
LAN mirror (mirror/sbradio_mirror.py) ◄───────┘  pulls XML + ZIPs, verifies SHA-1,
   serves http://<lan-ip>:8099/extensions.xml     rewrites URLs to plain HTTP
                                              │
LMS "Additional Repositories" ◄───────────────┘ ──► Radio Applet Installer
```

**Why a mirror?** The SqueezePlay Applet Installer downloads ZIPs with a plain
TCP HTTP client (`SetupAppletInstallerApplet.lua` → `SocketHttp`), on every
firmware including the community 8.x builds. It cannot use HTTPS, and GitHub
only serves HTTPS. LMS passes the URL through unchanged, so the Radio needs a
plain HTTP copy.

## GitHub setup

1. Push this repo to GitHub.
2. Settings → Actions → General → Workflow permissions: **Read and write**.
3. Actions → *Build applets* → **Run workflow** for the first build.

After that it runs daily at 04:17 UTC. A version is built only if no release
`<Name>-v<version>` exists yet. Tick **force** to rebuild an existing version.

Notes:
- The Spotify Connect ARM binaries (librespot, ogg-http-bridge,
  spotify-metadata, spotify-supervisor) are taken from the upstream ZIP of the
  **same version** (`http://49.12.198.91/sbspotifyconnect/`, falling back to the
  upstream GitHub release). If that ZIP doesn't exist, the build fails instead
  of mixing versions.
- Only versions present in the upstream GitHub `VERSION` file are built. The
  author's own HTTP server is sometimes ahead of GitHub.

## LAN mirror (on the LMS box or any always-on Linux host)

Quick test:

```bash
python3 mirror/sbradio_mirror.py --repo macsatcom/SBRadio \
  --dir ~/sbradio-mirror --public-base http://192.168.1.20:8099 --serve 8099
```

As a service: see the header of `mirror/sbradio-mirror.service`. Set `REPO`
and `PUBLIC_BASE` (the IP/port **as the Radio sees it**). It re-syncs hourly.
If a download fails or its SHA-1 doesn't match, the previous `extensions.xml`
is kept.

Then in LMS: **Settings → Manage Plugins → Additional Repositories** add
`http://192.168.1.20:8099/extensions.xml` and restart LMS. On the Radio:
**Settings → Advanced → Applet Installer**.

## Other files

- `tools/merge_extensions.py`: merges XML fragments, keeping the newest
  version per applet and target.
- `build-applet-repo.sh`: manual builder for any local applet folder.
