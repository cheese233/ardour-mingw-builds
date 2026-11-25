#!/bin/bash
# ci/50-bundle.sh -- assemble a portable Windows bundle and tar it.
set -e
source "$(dirname "$0")/env.sh"
P="$PREFIX"
B="$BUNDLE"

rm -rf "$B"; mkdir -p "$B/lib" "$B/share"
cp -a "$P/lib/ardour9" "$B/lib/ardour9"

# dependency DLLs (win-stack installs shared libs to bin/, some to lib/)
cp -f "$P"/bin/*.dll "$B/lib/ardour9/" 2>/dev/null || true
cp -f "$P"/lib/*.dll "$B/lib/ardour9/" 2>/dev/null || true

# mingw runtime DLLs (path discovered via the compiler)
for d in libstdc++-6.dll libgcc_s_seh-1.dll libwinpthread-1.dll; do
  src="$(x86_64-w64-mingw32-gcc -print-file-name="$d")"
  [ -f "$src" ] || src="$MINGW_GCCDIR/$d"
  [ -f "$src" ] && cp -f "$src" "$B/lib/ardour9/" || true
done

# session utilities
for f in ardour9-export.exe ardour9-new_session.exe ardour9-new_empty_session.exe; do
  [ -f "$P/bin/$f" ] && cp -f "$P/bin/$f" "$B/lib/ardour9/" || true
done

# VST scanners must live in <dll_dir>/fst
mkdir -p "$B/lib/ardour9/fst"
for f in ardour-vst-scanner.exe ardour-vst3-scanner.exe; do
  [ -f "$B/lib/ardour9/$f" ] && cp -f "$B/lib/ardour9/$f" "$B/lib/ardour9/fst/" || true
done

# data + system config; merge etc/ardour9 into share/ardour9 so that Ardour's
# config search path (which includes share/ardour9) finds default_ui_config etc.
# This avoids needing ARDOUR_CONFIG_PATH (wixl 0.101 cannot set env vars).
cp -a "$P/share/ardour9" "$B/share/ardour9"
if [ -d "$P/etc/ardour9" ]; then
  cp -a "$P/etc/ardour9/." "$B/share/ardour9/"
fi

# drop development artifacts that are useless at runtime
find "$B/lib/ardour9" -maxdepth 2 -type f \
  \( -name '*.dll.a' -o -name '*.la' -o -name '*.a' -o -name '*.def' \) -delete

# VST scanners are only searched for in <dll_dir>/fst
rm -f "$B/lib/ardour9/ardour-vst-scanner.exe" "$B/lib/ardour9/ardour-vst3-scanner.exe"

tar czf "$B.tar.gz" -C "$(dirname "$B")" "$(basename "$B")"
echo "=== bundle ==="; du -sh "$B" "$B.tar.gz"
ls -l "$B/lib/ardour9/libcairo-2.dll" "$B/share/ardour9/default_ui_config"
echo "BUNDLE DONE"
