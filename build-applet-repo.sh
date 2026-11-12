#!/usr/bin/env bash
# Build a Lyrion/LMS applet repository (ZIP + extensions.xml) for SqueezePlay
# devices (Squeezebox Radio = baby, Touch = fab4, Controller = jive).
#
# Usage:
#   ./build-applet-repo.sh -s <applet_src_dir> -u <base_url> [options]
#
# Options:
#   -s DIR    Applet source dir (contains <Name>Applet.lua and <Name>Meta.lua)
#   -u URL    Public base URL where files will be served (http:// recommended)
#   -n NAME   Applet name (default: auto-detected from *Meta.lua)
#   -v VER    Version (default: VERSION file in source dir, else 1.0)
#   -o DIR    Output dir (default: ./dist). Existing XML entries are kept,
#             so you can run the script once per applet into the same dir.
#   -t LIST   Targets, comma separated (default: baby,fab4)
#   -m VER    minTarget firmware (default: 7.0)
#   -M VER    maxTarget firmware (default: *)
#   -d TEXT   Description
#   -c TEXT   Creator
#   -e TEXT   Email
#   -x GLOBS  Extra exclude patterns, comma separated (e.g. 'tests/*,*.md')
#   -S PORT   After building, serve output dir over HTTP on PORT (python3)
set -euo pipefail

SRC= BASE_URL= NAME= VERSION= OUT=./dist TARGETS=baby,fab4
MIN_T=7.0 MAX_T='*' DESC= CREATOR= EMAIL= EXCLUDES= SERVE_PORT=

die() { echo "ERROR: $*" >&2; exit 1; }
xml_esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' <<<"$1"; }

while getopts "s:u:n:v:o:t:m:M:d:c:e:x:S:h" o; do
  case $o in
    s) SRC=$OPTARG;; u) BASE_URL=${OPTARG%/};; n) NAME=$OPTARG;;
    v) VERSION=$OPTARG;; o) OUT=$OPTARG;; t) TARGETS=$OPTARG;;
    m) MIN_T=$OPTARG;; M) MAX_T=$OPTARG;; d) DESC=$OPTARG;;
    c) CREATOR=$OPTARG;; e) EMAIL=$OPTARG;; x) EXCLUDES=$OPTARG;;
    S) SERVE_PORT=$OPTARG;; h|*) sed -n '2,24p' "$0"; exit 0;;
  esac
done

[[ -n $SRC && -d $SRC ]] || die "source dir (-s) missing or not a directory"
[[ -n $BASE_URL ]] || die "base URL (-u) required"
for c in zip sha1sum; do command -v $c >/dev/null || die "'$c' not installed"; done
[[ $BASE_URL == https://* ]] && echo "WARNING: stock Radio firmware often cannot download over HTTPS; prefer http://" >&2

SRC=$(cd "$SRC" && pwd)

# Detect applet name from <Name>Meta.lua
if [[ -z $NAME ]]; then
  meta=$(find "$SRC" -maxdepth 1 -name '*Meta.lua' -printf '%f\n' | head -n1)
  [[ -n $meta ]] || die "no *Meta.lua in $SRC; pass -n NAME"
  NAME=${meta%Meta.lua}
fi
[[ -f $SRC/${NAME}Applet.lua ]] || echo "WARNING: ${NAME}Applet.lua not found in source root" >&2
[[ -f $SRC/${NAME}Meta.lua   ]] || echo "WARNING: ${NAME}Meta.lua not found in source root" >&2

if [[ -z $VERSION ]]; then
  VERSION=$( [[ -f $SRC/VERSION ]] && tr -d ' \r\n' <"$SRC/VERSION" || echo 1.0 )
fi
[[ -n $DESC ]] || DESC="$NAME applet"

mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
ZIP_NAME="$NAME-$VERSION.zip"
ZIP="$OUT/$ZIP_NAME"
rm -f "$ZIP" "$OUT"/"$NAME"-*.zip

# Zip contents at archive root (no wrapping folder), deterministic order
excl=(-x '.git/*' -x '.gitignore' -x '*.DS_Store' -x 'dist/*' -x '*.zip' -x 'VERSION')
IFS=',' read -ra extra <<<"$EXCLUDES"
for p in "${extra[@]}"; do [[ -n $p ]] && excl+=(-x "$p"); done
( cd "$SRC" && find . -type f | sed 's|^\./||' | LC_ALL=C sort | zip -X -q "$ZIP" -@ "${excl[@]}" )
[[ -s $ZIP ]] || die "zip is empty"

# Sanity check: no wrapping folder
unzip -Z1 "$ZIP" | grep -qx "${NAME}Meta.lua" || echo "WARNING: ${NAME}Meta.lua is not at zip root" >&2

SHA=$(sha1sum "$ZIP" | cut -d' ' -f1)
URL="$BASE_URL/$ZIP_NAME"

# Build applet entries for this applet
entries=""
IFS=',' read -ra tlist <<<"$TARGETS"
for t in "${tlist[@]}"; do
  entries+="    <applet name=\"$(xml_esc "$NAME")\" version=\"$(xml_esc "$VERSION")\" target=\"$t\" minTarget=\"$MIN_T\" maxTarget=\"$MAX_T\">
      <title lang=\"EN\">$(xml_esc "$NAME")</title>
      <desc lang=\"EN\">$(xml_esc "$DESC")</desc>
      <creator>$(xml_esc "$CREATOR")</creator>
      <email>$(xml_esc "$EMAIL")</email>
      <url>$(xml_esc "$URL")</url>
      <sha>$SHA</sha>
    </applet>
"
done

# Keep entries for other applets already in extensions.xml (multi-applet repo)
XML="$OUT/extensions.xml"
kept=""
if [[ -f $XML ]]; then
  kept=$(awk -v n="$NAME" '
    /<applet / { buf=$0 "\n"; inapp=1; mine = ($0 ~ "name=\"" n "\""); next }
    inapp { buf = buf $0 "\n"; if ($0 ~ /<\/applet>/) { if (!mine) printf "%s", buf; inapp=0 } }
  ' "$XML")
fi

{
  echo '<?xml version="1.0" encoding="utf-8"?>'
  echo '<extensions>'
  echo '  <details>'
  echo '    <title lang="EN">Local applet repository</title>'
  echo '  </details>'
  echo '  <applets>'
  [[ -n $kept ]] && printf '%s\n' "$kept"
  printf '%s' "$entries"
  echo '  </applets>'
  echo '</extensions>'
} >"$XML"

command -v xmllint >/dev/null && { xmllint --noout "$XML" || die "generated XML invalid"; }

cat <<EOF

Built:   $ZIP
SHA-1:   $SHA
XML:     $XML
Targets: $TARGETS (firmware $MIN_T .. $MAX_T)

Add this to LMS -> Settings -> Manage Plugins -> Additional Repositories:
  $BASE_URL/extensions.xml
Then on the Radio: Settings -> Advanced -> Applet Installer.
Test from the LMS host:  curl -I $URL
EOF

if [[ -n $SERVE_PORT ]]; then
  echo; echo "Serving $OUT on port $SERVE_PORT (Ctrl+C to stop)..."
  cd "$OUT" && exec python3 -m http.server "$SERVE_PORT"
fi
