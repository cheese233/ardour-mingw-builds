#!/bin/bash
# ci/60-msi.sh -- build a Windows .msi from the bundle with wixl (msitools).
set -e
source "$(dirname "$0")/env.sh"
VERSION="${VERSION:-9.10.0}"

MSI="$ROOT/ardour-$VERSION-x64.msi"
WXS="$ROOT/ardour.wxs"

python3 "$CI_DIR/make-wxs.py" "$BUNDLE" "$VERSION" "$WXS"
# install the WiX UI extension files (data/ext/ui) that meson didn't install
for d in /usr/local/share/wixl-*; do
  [ -d "$d" ] || continue
  mkdir -p "$d/ext"
  rm -rf "$d/ext/ui"
  cp -a "$CI_DIR/wixl-ext/ui" "$d/ext/ui"
done
cp -f "$CI_DIR/wixl-ext/ui/License.rtf" "$(dirname "$BUNDLE")/License.rtf" 2>/dev/null || true
# wixl resolves Source paths relative to its cwd; run from the bundle's parent
cd "$(dirname "$BUNDLE")"
wixl --arch x64 --ext ui -v -o "$MSI" "$WXS"

echo "=== MSI summary ==="
msiinfo suminfo "$MSI" 2>/dev/null | grep -iE "Template|Subject|Author|Title" || true
echo "=== MSI files ==="
ls -lh "$MSI"
echo "MSI DONE: $MSI"
