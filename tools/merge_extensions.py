#!/usr/bin/env python3
"""Merge several Lyrion/LMS applet repository XML files into one.

For each (applet name, target) only the entry with the highest version is kept.
"""
import argparse
import re
import sys
import xml.etree.ElementTree as ET


def vkey(v):
    return [int(p) if p.isdigit() else p for p in re.split(r"[.\-+]", v or "0")]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*")
    ap.add_argument("-o", "--output", default="-")
    ap.add_argument("--title", default="SBRadio Applet Repository")
    a = ap.parse_args()

    best = {}
    for f in a.files:
        try:
            root = ET.parse(f).getroot()
        except (ET.ParseError, OSError) as e:
            print(f"skipping {f}: {e}", file=sys.stderr)
            continue
        for app in root.iter("applet"):
            key = (app.get("name"), app.get("target"))
            if not all(key) or app.findtext("url") is None or app.findtext("sha") is None:
                print(f"skipping incomplete applet entry in {f}", file=sys.stderr)
                continue
            cur = best.get(key)
            if cur is None or vkey(app.get("version")) > vkey(cur.get("version")):
                best[key] = app

    out = ET.Element("extensions")
    details = ET.SubElement(out, "details")
    t = ET.SubElement(details, "title", lang="EN")
    t.text = a.title
    applets = ET.SubElement(out, "applets")
    for key in sorted(best):
        applets.append(best[key])
    ET.indent(out, "  ")
    data = '<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(out, encoding="unicode") + "\n"

    if a.output == "-":
        sys.stdout.write(data)
    else:
        with open(a.output, "w", encoding="utf-8") as fh:
            fh.write(data)
    print(f"{len(best)} applet entries written", file=sys.stderr)


if __name__ == "__main__":
    main()
