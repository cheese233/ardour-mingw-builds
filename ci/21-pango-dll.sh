#!/bin/bash
source "$(dirname "$0")/env.sh"
set -e
export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig
cd "$BUILDD"; rm -rf pango-1.42.4; mkdir pango-1.42.4
tar xf "$SRCDIR/pango-1.42.4.tar.xz" -C pango-1.42.4 --strip-components=1
cd pango-1.42.4
rm -rf build
meson setup build --cross-file "$BUILDD/meson-cross.txt" --prefix=$PREFIX --libdir=lib --buildtype=release -Dgir=false -Duse_fontconfig=true
ninja -C build
ninja -C build install
echo "=== pangocairo imports cairo dll? ==="
x86_64-w64-mingw32-objdump -p "$PREFIX/bin/libpangocairo-1.0-0.dll" 2>/dev/null | grep -i "cairo"
echo "PANGO DLL REBUILD DONE"