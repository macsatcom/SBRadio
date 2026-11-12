#!/usr/bin/env python3
"""LAN mirror for an applet repository published on GitHub.

Squeezebox Radio/Touch firmware downloads applet ZIPs with plain HTTP only
(no TLS), so GitHub release assets cannot be used directly. This script:

  1. fetches extensions.xml from the GitHub repo (HTTPS),
  2. downloads every referenced ZIP and verifies its SHA-1,
  3. writes a local extensions.xml whose URLs point at this mirror (HTTP).

Serve the output directory with any HTTP server (see --serve or the systemd
units next to this script) and add <public-base>/extensions.xml to LMS.
"""
import argparse
import hashlib
import http.server
import os
import sys
import tempfile
import time
import urllib.request
import xml.etree.ElementTree as ET
from functools import partial

UA = {"User-Agent": "sbradio-mirror"}


def fetch(url, timeout=60):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as r:
        return r.read()


def sha1(data):
    return hashlib.sha1(data).hexdigest()


def atomic_write(path, data):
    d = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".tmp-")
    with os.fdopen(fd, "wb") as fh:
        fh.write(data)
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)


def sync(a):
    os.makedirs(a.dir, exist_ok=True)
    src = a.xml_url or f"https://raw.githubusercontent.com/{a.repo}/{a.branch}/extensions.xml"
    root = ET.fromstring(fetch(src))
    base = a.public_base.rstrip("/")
    wanted, failed, errors = set(), set(), 0

    for app in root.iter("applet"):
        url, want = app.findtext("url"), (app.findtext("sha") or "").lower()
        name = url.rsplit("/", 1)[-1]
        path = os.path.join(a.dir, name)
        if name in failed:
            continue
        wanted.add(name)
        if os.path.exists(path) and sha1(open(path, "rb").read()) == want:
            pass
        else:
            print(f"downloading {url}")
            data = fetch(url, timeout=300)
            got = sha1(data)
            if got != want:
                print(f"ERROR sha1 mismatch for {name}: expected {want}, got {got}", file=sys.stderr)
                errors += 1
                failed.add(name)
                continue
            atomic_write(path, data)
        app.find("url").text = f"{base}/{name}"

    if errors:
        # keep previous extensions.xml so the Radio never sees a broken entry
        raise SystemExit(f"{errors} download(s) failed; extensions.xml not updated")

    ET.indent(root, "  ")
    xml = '<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(root, encoding="unicode") + "\n"
    atomic_write(os.path.join(a.dir, "extensions.xml"), xml.encode())

    if a.prune:
        for f in os.listdir(a.dir):
            if f.endswith(".zip") and f not in wanted:
                os.remove(os.path.join(a.dir, f))
                print(f"pruned {f}")
    print(f"ok: {len(wanted)} file(s); LMS repository URL: {base}/extensions.xml")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", help="GitHub owner/repo holding extensions.xml")
    ap.add_argument("--branch", default="main")
    ap.add_argument("--xml-url", help="override source extensions.xml URL")
    ap.add_argument("--dir", required=True, help="output directory to serve")
    ap.add_argument("--public-base", required=True, help="http://<lan-ip>:<port> as seen by the Radio")
    ap.add_argument("--prune", action="store_true", help="delete ZIPs no longer referenced")
    ap.add_argument("--serve", type=int, metavar="PORT", help="also serve --dir over HTTP")
    ap.add_argument("--interval", type=int, default=3600, help="re-sync seconds when serving")
    a = ap.parse_args()
    if not (a.repo or a.xml_url):
        ap.error("--repo or --xml-url required")
    if a.public_base.startswith("https://"):
        print("WARNING: the Radio cannot download over HTTPS; use http://", file=sys.stderr)

    if not a.serve:
        sync(a)
        return

    import threading

    def loop():
        while True:
            try:
                sync(a)
            except Exception as e:  # keep serving last good state
                print(f"sync failed: {e}", file=sys.stderr)
            time.sleep(a.interval)

    threading.Thread(target=loop, daemon=True).start()
    handler = partial(http.server.SimpleHTTPRequestHandler, directory=a.dir)
    print(f"serving {a.dir} on :{a.serve}")
    http.server.ThreadingHTTPServer(("", a.serve), handler).serve_forever()


if __name__ == "__main__":
    main()
