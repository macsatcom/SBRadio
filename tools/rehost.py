#!/usr/bin/env python3
"""Re-host an applet from an upstream extensions.xml.

Downloads the ZIPs referenced for --name/--version, verifies each SHA-1,
and writes a fragment XML pointing to --base-url. Fails if upstream does not
publish exactly that version (so we never mix versions).
"""
import argparse
import hashlib
import sys
import urllib.request
import xml.etree.ElementTree as ET


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("xml")
    ap.add_argument("--name", required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    root = ET.parse(a.xml).getroot()
    applets = root.find("applets")
    found = sorted({f'{x.get("name")} {x.get("version")}' for x in root.iter("applet")})
    keep = []
    for app in list(applets):
        if app.get("name") == a.name and app.get("version") == a.version:
            keep.append(app)
        applets.remove(app)
    if not keep:
        sys.exit(f"upstream does not publish {a.name} {a.version} (has: {', '.join(found) or 'nothing'})")

    done = {}
    for app in keep:
        url = app.findtext("url")
        zip_name = url.rsplit("/", 1)[-1]
        want = app.findtext("sha").lower()
        if zip_name not in done:
            data = urllib.request.urlopen(url, timeout=300).read()
            got = hashlib.sha1(data).hexdigest()
            if got != want:
                sys.exit(f"SHA-1 mismatch for {zip_name}: {got} != {want}")
            with open(zip_name, "wb") as fh:
                fh.write(data)
            done[zip_name] = got
            print(f"verified {zip_name}")
        app.find("url").text = f"{a.base_url.rstrip('/')}/{zip_name}"
        applets.append(app)

    ET.indent(root, "  ")
    with open(a.out, "w", encoding="utf-8") as fh:
        fh.write('<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(root, encoding="unicode") + "\n")


if __name__ == "__main__":
    main()
