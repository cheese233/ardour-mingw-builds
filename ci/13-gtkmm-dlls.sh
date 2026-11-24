#!/bin/bash
source "$(dirname "$0")/env.sh"
set -e
XPREFIX=x86_64-w64-mingw32
export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig
CF="-I$PREFIX/include -O2 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -mstackrealign"
CX="-I$PREFIX/include -O2 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -std=gnu++11 -mstackrealign"

build(){
  name=$1; ext=$2
  cd "$BUILDD"; rm -rf "$name"; mkdir "$name"
  tar xf "$SRCDIR/$name.$ext" -C "$name" --strip-components=1
  cd "$name"
  CPPFLAGS="-I$PREFIX/include" CFLAGS="$CF" CXXFLAGS="$CX" LDFLAGS="-L$PREFIX/lib" \
    ./configure --host=$XPREFIX --build=x86_64-linux --prefix=$PREFIX --disable-static --disable-documentation
  make LDFLAGS="-L$PREFIX/lib -no-undefined" -j$(nproc)
  make install LDFLAGS="-L$PREFIX/lib -no-undefined"
  echo "=== $name dll check ==="; ls -l "$PREFIX"/lib/lib${name%%-*}*.dll.a 2>/dev/null || true
}

build glibmm-2.62.0 tar.xz
build cairomm-1.13.1 tar.gz
build pangomm-2.42.0 tar.xz

# remove stale static archives so the linker prefers the import libs
rm -f "$PREFIX"/lib/libglibmm-2.4.a "$PREFIX"/lib/libcairomm-1.0.a "$PREFIX"/lib/libpangomm-1.4.a
echo "=== final ==="
ls -l "$PREFIX"/lib/libglibmm* "$PREFIX"/lib/libcairomm* "$PREFIX"/lib/libpangomm* 2>/dev/null
echo "GTKMM DLLS DONE"