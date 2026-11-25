#!/bin/bash
# ci/60-msi.sh -- build a Windows .msi from the bundle with wixl (msitools).
set -e
source "$(dirname "$0")/env.sh"
VERSION="${VERSION:-9.10.0}"

MSI="$ROOT/ardour-$VERSION-x64.msi"
WXS="$ROOT/ardour.wxs"

python3 "$CI_DIR/make-wxs.py" "$BUNDLE" "$VERSION" "$WXS"
# Ensure a wixl that supports WixUI_InstallDir (msitools master; v0.106 only has Minimal)
if ! ls /usr/local/share/wixl-*/ext/ui/WixUI_InstallDir.wxs >/dev/null 2>&1; then
  src=/tmp/wixl-master
  [ -d "$src" ] || git clone --depth 1 --recurse-submodules https://github.com/GNOME/msitools.git "$src"
  mkdir -p "$src/subprojects/bats-core/bin"
  ln -sf "$(command -v bats)" "$src/subprojects/bats-core/bin/bats"
  # Vala 0.56's HashSet.add() returns void; master assumes bool. Drop the checks.
  sed -i 's/if (!file_ids.add (file.Id))/file_ids.add (file.Id); if (false)/' "$src/tools/wixl/builder.vala"
  sed -i 's/if (!service_config_ids.add (id))/service_config_ids.add (id); if (false)/' "$src/tools/wixl/builder.vala"
  sed -i 's/if (!firewall_ids.add (ex.Id))/firewall_ids.add (ex.Id); if (false)/' "$src/tools/wixl/builder.vala"
  sed -i 's/if (!environment_ids.add (id))/environment_ids.add (id); if (false)/' "$src/tools/wixl/builder.vala"
  ( cd "$src" && PKG_CONFIG_PATH=/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/share/pkgconfig \
      PKG_CONFIG_LIBDIR=/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/share/pkgconfig \
      /tmp/wixlvenv/bin/meson setup build --prefix=/usr/local -Dintrospection=true -Dvalidate-wxi=false \
      && ninja -C build && sudo ninja -C build install )
  echo /usr/local/lib/x86_64-linux-gnu | sudo tee /etc/ld.so.conf.d/local-multiarch.conf >/dev/null
  sudo ldconfig
fi
# overlay vendored master UI extension files into wixl's data dir
for d in /usr/local/share/wixl-*; do
  [ -d "$d" ] || continue
  sudo mkdir -p "$d/ext/ui"
  sudo cp -a "$CI_DIR/wixl-ext/ui/." "$d/ext/ui/"
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
