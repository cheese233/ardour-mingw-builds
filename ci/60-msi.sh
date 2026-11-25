#!/bin/bash
# ci/60-msi.sh -- build a Windows .msi from the bundle with wixl (msitools).
set -e
source "$(dirname "$0")/env.sh"
VERSION="${VERSION:-9.10.0}"

MSI="$ROOT/ardour-$VERSION-x64.msi"
WXS="$ROOT/ardour.wxs"

python3 "$CI_DIR/make-wxs.py" "$BUNDLE" "$VERSION" "$WXS"
# WixUI_InstallDir shows a license page; supply a License.rtf next to the wxs
LIC="$(find /usr/local/share /usr/share -path '*ext/ui/License.rtf' 2>/dev/null | head -1)"
if [ -n "$LIC" ]; then cp -f "$LIC" "$(dirname "$BUNDLE")/License.rtf"; fi
# wixl resolves Source paths relative to its cwd; run from the bundle's parent
cd "$(dirname "$BUNDLE")"
wixl --arch x64 --ext ui -v -o "$MSI" "$WXS"

echo "=== MSI summary ==="
msiinfo suminfo "$MSI" 2>/dev/null | grep -iE "Template|Subject|Author|Title" || true
echo "=== MSI files ==="
ls -lh "$MSI"
echo "MSI DONE: $MSI"
