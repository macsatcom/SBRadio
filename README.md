# SBRadio – Applet repository for Squeezebox Radio and Touch

Install these community applets on a Logitech Squeezebox Radio or Squeezebox
Touch through the built-in **Applet Installer**:

| Applet | What it does | Upstream project |
|---|---|---|
| **Standalone Radio** | Internet radio on the Radio without a running music server | [ssbrandsma/SBStandalone](https://github.com/ssbrandsma/SBStandalone) |
| **Spotify Connect** | Makes the Radio a Spotify Connect speaker | [ssbrandsma/squeezebox-radio-spotify-connect](https://github.com/ssbrandsma/squeezebox-radio-spotify-connect) |

New upstream versions are built automatically every day and published under
[Releases](https://github.com/macsatcom/SBRadio/releases).

---

## Contents

1. [Why you need a small "mirror"](#1-why-you-need-a-small-mirror)
2. [What you need](#2-what-you-need)
3. [Install the mirror](#3-install-the-mirror)
4. [Add the repository to Lyrion Music Server](#4-add-the-repository-to-lyrion-music-server)
5. [Install the applets on the Radio](#5-install-the-applets-on-the-radio)
6. [Updates](#6-updates)
7. [Troubleshooting](#7-troubleshooting)
8. [Uninstall](#8-uninstall)

---

## 1. Why you need a small "mirror"

The Squeezebox Radio downloads applets itself, and only over plain **HTTP**.
It cannot use HTTPS on any firmware, including the community firmware.
GitHub only serves HTTPS, so the Radio cannot download straight from GitHub.

The mirror is a small Python program that runs on a computer in your home
network. Every hour it:

1. downloads the applet list and ZIP files from this GitHub repository,
2. checks that each ZIP matches its SHA-1 checksum,
3. serves them on your network over plain HTTP so the Radio can fetch them.

If a download fails or a file doesn't match its checksum, the mirror keeps
the last good version, so the Radio never gets a broken file.

```
GitHub (HTTPS) ──► mirror on your network (HTTP) ──► LMS ──► Squeezebox Radio
```

## 2. What you need

- A **Squeezebox Radio** (or Touch) with firmware 7.7 or newer.
- **Lyrion Music Server (LMS)**, formerly Logitech Media Server, running on
  your network. LMS is only needed to install the applets. Standalone Radio
  and Spotify Connect play without it afterwards.
- An always-on **Linux computer** for the mirror, with **Python 3.8 or newer**.
  It can be the same machine as LMS (recommended), a Raspberry Pi or a NAS.
  The steps below are for Linux with systemd (Debian, Ubuntu, Raspberry Pi
  OS, piCorePlayer excluded).
- The computer's **local IP address**, for example `192.168.1.20`. Find it
  with:
  ```bash
  hostname -I
  ```
  Give this computer a fixed IP (DHCP reservation in your router), otherwise
  the address in LMS will stop working when it changes.

Throughout this guide, replace `192.168.1.20` with your own IP address.

## 3. Install the mirror

### 3.1 Quick test (optional, nothing is installed)

```bash
curl -O https://raw.githubusercontent.com/macsatcom/SBRadio/main/mirror/sbradio_mirror.py
python3 sbradio_mirror.py --repo macsatcom/SBRadio \
  --dir ~/sbradio-mirror --public-base http://192.168.1.20:8099 --serve 8099
```

Leave it running and open `http://192.168.1.20:8099/extensions.xml` in a
browser on another device. You should see an XML list where every `<url>`
starts with `http://192.168.1.20:8099/`. Stop it with **Ctrl+C**.

### 3.2 Install as a permanent service

Run these commands on the mirror computer:

```bash
# 1. Download the program and the service file
sudo curl -o /usr/local/bin/sbradio_mirror.py \
  https://raw.githubusercontent.com/macsatcom/SBRadio/main/mirror/sbradio_mirror.py
sudo chmod 755 /usr/local/bin/sbradio_mirror.py
sudo curl -o /etc/systemd/system/sbradio-mirror.service \
  https://raw.githubusercontent.com/macsatcom/SBRadio/main/mirror/sbradio-mirror.service

# 2. Set your own IP address (replace 192.168.1.20)
sudo sed -i 's#^Environment=PUBLIC_BASE=.*#Environment=PUBLIC_BASE=http://192.168.1.20:8099#' \
  /etc/systemd/system/sbradio-mirror.service

# 3. Start it now and at every boot
sudo systemctl daemon-reload
sudo systemctl enable --now sbradio-mirror
```

### 3.3 Check that it works

```bash
systemctl status sbradio-mirror          # should say "active (running)"
journalctl -u sbradio-mirror -n 20       # should end with "ok: N file(s) ..."
curl http://192.168.1.20:8099/extensions.xml
```

The last command must show `<url>http://192.168.1.20:8099/...zip</url>` lines.
If you see `https://github.com/...` URLs, the first sync hasn't finished yet;
wait a minute and try again.

**Firewall:** if the computer runs a firewall, allow port 8099, e.g.
`sudo ufw allow 8099/tcp`.

**Different port:** port 8099 is set in two places in the service file: in
`PUBLIC_BASE` and after `--serve`. Change both, then run
`sudo systemctl daemon-reload && sudo systemctl restart sbradio-mirror`.

## 4. Add the repository to Lyrion Music Server

1. Open the LMS web interface, usually `http://<lms-ip>:9000`.
2. Go to **Settings → Manage Plugins**.
3. Scroll to the bottom. In the **Additional Repositories** field, enter:
   ```
   http://192.168.1.20:8099/extensions.xml
   ```
4. Click **Apply**.
5. Restart LMS (Settings → Information → Restart, or
   `sudo systemctl restart lyrionmusicserver`; the service may be named
   `logitechmediaserver` on older installs).

Use `http://`, not `https://`.

## 5. Install the applets on the Radio

1. Make sure the Radio is connected to **this** LMS: on the Radio go to
   **Home → Settings → Advanced → Networking → Remote Libraries** (or
   **Choose Music Source / Switch Library**, depending on firmware) and select
   your LMS.
2. On the Radio, go to **Home → Settings → Advanced → Applet Installer**.
3. You will see **Standalone Radio** and **Spotify Connect**. Select an applet
   and choose **Install**.
4. Confirm. The Radio downloads the applet and restarts.
5. After the restart the applet is in the Home menu (or under My Apps /
   Extras, depending on firmware).

**Extended Storage users:** according to the Standalone Radio author, if
**Extended Storage** is enabled on your Radio you must first install
**Standalone Base 0.5.7 or later** before Standalone Radio 0.9.9 or newer.
Standalone Base is not included in this repository; see the
[SBStandalone README](https://github.com/ssbrandsma/SBStandalone).

**Spotify Connect:** after installing, open the applet on the Radio and follow
the pairing instructions there. The Radio then shows up as a speaker in the
Spotify app on devices on the same network.

## 6. Updates

Updates happen automatically:

1. Every day, this repository checks for new upstream versions and builds them.
2. Every hour, your mirror fetches the latest versions.
3. To install an update on the Radio, open
   **Settings → Advanced → Applet Installer** again. Updated applets are offered
   there. Select the applet and install it.

LMS caches the applet list. If an update doesn't appear, restart LMS.

To fetch the latest version on the mirror right away:
```bash
sudo systemctl restart sbradio-mirror
```

## 7. Troubleshooting

**The applets don't appear in the Applet Installer**
- Check that `http://192.168.1.20:8099/extensions.xml` opens from another
  device. If it doesn't: mirror not running, wrong IP, or firewall.
- Check that the Radio is connected to the LMS where you added the repository.
- Restart LMS after adding or changing the repository URL.
- Check that the Radio firmware is 7.7 or newer (**Settings → Advanced →
  Software Update** shows the version). Older firmware hides these applets.
- Look in the LMS log (Settings → Information → log files) for errors that
  mention `extensions.xml`.

**The download fails on the Radio, or it reports an error during install**
- The `<url>` lines in `extensions.xml` must start with `http://`, not
  `https://`, and must use an IP the **Radio** can reach (not `localhost` or
  `127.0.0.1`).
- Test a ZIP from another device:
  `curl -I http://192.168.1.20:8099/StandaloneRadio-<version>.zip` should
  return `200 OK`.

**The mirror log shows "sha1 mismatch" or "download failed"**
- Usually a temporary network problem. The mirror keeps serving the last good
  files and retries every hour. Restart it to retry now:
  `sudo systemctl restart sbradio-mirror`.

**Running LMS in Docker**
- The mirror can run on the host. Use the host's LAN IP in `PUBLIC_BASE`, not
  a Docker-internal address.

**Mirror commands at a glance**
```bash
systemctl status sbradio-mirror       # running?
journalctl -u sbradio-mirror -f       # live log
sudo systemctl restart sbradio-mirror # sync now
```

## 8. Uninstall

**Applets on the Radio:** **Settings → Advanced → Applet Installer**, select
the applet, choose **Remove**.

**Repository in LMS:** delete the URL under **Settings → Manage Plugins →
Additional Repositories**, then restart LMS.

**Mirror:**
```bash
sudo systemctl disable --now sbradio-mirror
sudo rm /etc/systemd/system/sbradio-mirror.service /usr/local/bin/sbradio_mirror.py
sudo systemctl daemon-reload
```

---

## Credits

The applets are written by Sjoerd Brandsma
([ssbrandsma](https://github.com/ssbrandsma)). This repository only builds and
repackages them; report applet bugs to the upstream projects. The Spotify
Connect ARM programs (librespot etc.) are taken unchanged from the author's own
release of the same version.
