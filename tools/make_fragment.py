#!/usr/bin/env python3
"""Write an applet repository fragment (extensions.xml) for local ZIP files.

Each --zip TARGET=FILE adds one <applet> entry for that target, with the
ZIP's SHA-1 and the URL <base-url>/<FILE>.
"""
import argparse
import hashlib
import os
import xml.etree.ElementTree as ET


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--title", required=True)
    ap.add_argument("--desc", default="")
    ap.add_argument("--creator", default="")
    ap.add_argument("--min-target", default="7.7")
    ap.add_argument("--max-target", default="*")
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--zip", action="append", required=True, metavar="TARGET=FILE")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    root = ET.Element("extensions")
    ET.SubElement(ET.SubElement(root, "details"), "title", lang="EN").text = a.title
    applets = ET.SubElement(root, "applets")
    for spec in a.zip:
        target, path = spec.split("=", 1)
        with open(path, "rb") as fh:
            sha = hashlib.sha1(fh.read()).hexdigest()
        app = ET.SubElement(applets, "applet", name=a.name, version=a.version, target=target,
                            minTarget=a.min_target, maxTarget=a.max_target)
        ET.SubElement(app, "title", lang="EN").text = a.title
        ET.SubElement(app, "desc", lang="EN").text = a.desc
        ET.SubElement(app, "creator").text = a.creator
        ET.SubElement(app, "url").text = f"{a.base_url.rstrip('/')}/{os.path.basename(path)}"
        ET.SubElement(app, "sha").text = sha
        print(f"{target}: {os.path.basename(path)} {sha}")

    ET.indent(root, "  ")
    with open(a.out, "w", encoding="utf-8") as fh:
        fh.write('<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(root, encoding="unicode") + "\n")


if __name__ == "__main__":
    main()
