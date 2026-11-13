# SBRadio – Squeezebox Radio applets via Lyrion Music Server

An LMS plugin, **SB Radio Applets**, that lets you install these community
applets on a Logitech **Squeezebox Radio** or **Squeezebox Touch** through the
Radio's built-in **Applet Installer**:

| Applet | What it does | Upstream project |
|---|---|---|
| **Standalone Base** | Required base for the others: HTTPS proxy, Now Playing, web interface, Extended Storage. Install first | [ssbrandsma/SBStandaloneBase](https://github.com/ssbrandsma/SBStandaloneBase) |
| **Standalone Radio** | Internet radio on the Radio without a running music server | [ssbrandsma/SBStandalone](https://github.com/ssbrandsma/SBStandalone) |
| **Spotify Connect** | Makes the Radio a Spotify Connect speaker | [ssbrandsma/squeezebox-radio-spotify-connect](https://github.com/ssbrandsma/squeezebox-radio-spotify-connect) |

New upstream versions are built automatically every day and published under
[Releases](https://github.com/macsatcom/SBRadio/releases).

---

## Contents

1. [How it works](#1-how-it-works)
2. [What you need](#2-what-you-need)
3. [Install the plugin in LMS](#3-install-the-plugin-in-lms)
4. [Install the applets on the Radio](#4-install-the-applets-on-the-radio)
5. [Updates](#5-updates)
6. [Troubleshooting](#6-troubleshooting)
7. [Uninstall](#7-uninstall)
8. [Alternative: standalone mirror without the plugin](#8-alternative-standalone-mirror-without-the-plugin)

---

## 1. How it works

The Squeezebox Radio can only download applets over plain **HTTP**. It cannot
use HTTPS on any firmware, and GitHub only serves HTTPS. So the Radio cannot
download the applets from GitHub itself.

The plugin solves this the same way LMS handles Radio firmware updates:

1. LMS downloads the applets from GitHub over HTTPS into its cache folder.
2. LMS checks each file against its SHA-1 checksum.
3. LMS offers the applets in the Radio's Applet Installer.
4. The Radio downloads them from LMS on its normal web port (9000), over HTTP.

```
GitHub (HTTPS) ──► LMS + SB Radio Applets plugin ──(HTTP :9000)──► Squeezebox Radio
```

No extra software, ports or IP addresses to configure. The plugin checks
GitHub for new versions every 6 hours. If a download fails or a checksum
doesn't match, the last good version stays available.

## 2. What you need

- A **Squeezebox Radio** (or Touch) with firmware **7.7 or newer**.
  Check it on the Radio under **Settings → Advanced → Software Update**.
- **Lyrion Music Server** (LMS, formerly Logitech Media Server) version
  **7.9 or newer**, on any platform: Linux, Windows, macOS, NAS, Docker,
  Raspberry Pi.
- Internet access for LMS.

LMS is only needed to install the applets. Standalone Radio and Spotify
Connect play without it afterwards.

## 3. Install the plugin in LMS

1. Open the LMS web interface in a browser, usually
   `http://<your-lms-address>:9000`.
2. Go to **Settings → Manage Plugins** (in the Material skin:
   **Settings → Server → Plugins**; older versions: **Settings → Plugins**).
3. Scroll to the bottom. In the **Additional Repositories** field, paste:
   ```
   https://raw.githubusercontent.com/macsatcom/SBRadio/main/repo.xml
   ```
   This address can be HTTPS: LMS reads it, not the Radio.
4. Click **Apply**. The page reloads.
5. In the plugin list, find **SB Radio Applets** (under *3rd party plugins*)
   and tick its checkbox.
6. Click **Apply**, then **Restart LMS** when asked.
7. Wait one to two minutes after the restart. The plugin downloads the
   applets in the background.

**Check that it worked:** open the server log (**Settings → Information**,
link to the server log, or `server.log` in the LMS log folder). You should see
lines like:

```
Plugins::SBRadio::Plugin ... verified StandaloneRadio-0.9.18.zip
Plugins::SBRadio::Plugin ... offering 4 applet entries
```

## 4. Install the applets on the Radio

1. Make sure the Radio is connected to **this** LMS. On the Radio go to
   **Home → Settings → Advanced → Networking → Remote Libraries** (on some
   firmware: **Home → Choose Library / Switch Library**) and select your LMS.
2. On the Radio, go to **Home → Settings → Advanced → Applet Installer**.
3. Install **Standalone Base first**: select it, choose **Install** and
   confirm. The Radio downloads it from LMS and restarts. After the restart it
   shows "Standalone" at the top of the screen.
4. Open the **Applet Installer** again and install **Standalone Radio**
   and, if you want it, **Spotify Connect** the same way.
5. After the restart the applets are in the Home menu (or under My Apps /
   Extras, depending on firmware).

**Why Standalone Base?** It is the local infrastructure the other applets run
on: an HTTPS proxy (so the Radio can play modern HTTPS streams), the Now
Playing screen integration, artwork, the station web interface and Extended
Storage support. Since Standalone Radio 0.9.8 it is required.

**Spotify Connect** is large (4 MB+). The author recommends enabling
**Extended Storage** in Standalone Base before installing it.

**Spotify Connect:** after installing, open the applet on the Radio and follow
the pairing instructions there. The Radio then shows up as a speaker in the
Spotify app on devices on the same network.

## 5. Updates

**Applets:** every day this repository checks for new upstream versions and
builds them. The plugin picks them up within 6 hours. To install an update on
the Radio, open **Settings → Advanced → Applet Installer** again; updated
applets are offered there.

To fetch new versions right away, restart LMS.

**The plugin itself:** LMS shows plugin updates in **Settings → Manage
Plugins** like any other plugin.

## 6. Troubleshooting

**SB Radio Applets is not in the plugin list**
- Check the repository URL is exactly
  `https://raw.githubusercontent.com/macsatcom/SBRadio/main/repo.xml`, with no
  extra spaces.
- Restart LMS and look again.
- Check that LMS has internet access.

**The applets don't appear in the Applet Installer**
- Check the Radio is connected to the LMS where the plugin is installed.
- Check the server log for `Plugins::SBRadio` lines. `offering 0 applet
  entries` or `cannot fetch` means LMS couldn't reach GitHub; restart LMS when
  the internet connection works.
- Check the Radio firmware is 7.7 or newer. Older firmware is not offered
  these applets.
- More detail: **Settings → Advanced → Logging**, set `plugin.sbradio` to
  **Debug**.

**The Radio reports an error while downloading**
- Test the download from a computer on the same network (replace the address
  and version with what the log shows):
  ```
  curl -I http://<your-lms-address>:9000/sbradio/applets/StandaloneRadio-0.9.18.zip
  ```
  It should return `200 OK`.
- If LMS has **password protection** enabled
  (**Settings → Advanced → Security**), try disabling it while installing.

**Where are the files?** In the LMS cache folder, sub-folder `SBRadio`
(for example `/var/lib/squeezeboxserver/cache/SBRadio` on Debian/Ubuntu,
`/config/cache/SBRadio` in Docker).

## 7. Uninstall

**Applets on the Radio:** **Settings → Advanced → Applet Installer**, select
the applet, choose **Remove**.

**Plugin:** in LMS, **Settings → Manage Plugins**, untick **SB Radio
Applets**, apply and restart. To remove it completely, also delete the
repository URL from **Additional Repositories**, and the `SBRadio` folder in
the LMS cache folder.

## 8. Alternative: standalone mirror without the plugin

If you can't or don't want to install a plugin, `mirror/sbradio_mirror.py`
does the same job as a separate program on any always-on Linux computer
with Python 3. It serves the applets on its own port (8099).

```bash
sudo curl -o /usr/local/bin/sbradio_mirror.py \
  https://raw.githubusercontent.com/macsatcom/SBRadio/main/mirror/sbradio_mirror.py
sudo chmod 755 /usr/local/bin/sbradio_mirror.py
sudo curl -o /etc/systemd/system/sbradio-mirror.service \
  https://raw.githubusercontent.com/macsatcom/SBRadio/main/mirror/sbradio-mirror.service
# replace 192.168.1.20 with this computer's LAN IP:
sudo sed -i 's#^Environment=PUBLIC_BASE=.*#Environment=PUBLIC_BASE=http://192.168.1.20:8099#' \
  /etc/systemd/system/sbradio-mirror.service
sudo systemctl daemon-reload && sudo systemctl enable --now sbradio-mirror
```

Then add `http://192.168.1.20:8099/extensions.xml` (HTTP, not HTTPS) under
**Additional Repositories** in LMS and restart LMS. Don't use the mirror and
the plugin at the same time.

---

## Credits

The applets are written by Sjoerd Brandsma
([ssbrandsma](https://github.com/ssbrandsma)). This repository only builds and
repackages them; report applet bugs to the upstream projects. The Spotify
Connect ARM programs (librespot etc.) and the Standalone Base packages are
taken unchanged from the author's own builds, and only for the version
published in his GitHub repository.
