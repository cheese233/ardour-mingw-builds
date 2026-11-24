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

# pangomm: build only the library subdir (skip the X11-linked docs helper)
cd "$BUILDD"; rm -rf pangomm-2.42.0; mkdir pangomm-2.42.0
tar xf "$SRCDIR/pangomm-2.42.0.tar.xz" -C pangomm-2.42.0 --strip-components=1
cd pangomm-2.42.0
CPPFLAGS="-I$PREFIX/include" CFLAGS="$CF" CXXFLAGS="$CX" LDFLAGS="-L$PREFIX/lib" \
  ./configure --host=$XPREFIX --build=x86_64-linux --prefix=$PREFIX --disable-static --disable-documentation
sed -i 's/^allow_undefined_flag=.*/allow_undefined_flag=""/' libtool
printf 'all:\ninstall:\nclean:\n' > tools/Makefile
make -C pango/pangomm LDFLAGS="-L$PREFIX/lib -no-undefined" -j$(nproc)
make -C pango/pangomm install LDFLAGS="-L$PREFIX/lib -no-undefined"
mkdir -p "$PREFIX/lib/pkgconfig"; cp -f pango/pangomm-1.4.pc "$PREFIX/lib/pkgconfig/" 2>/dev/null || true

# remove stale static archives so the linker prefers the import libs
rm -f "$PREFIX"/lib/libglibmm-2.4.a "$PREFIX"/lib/libcairomm-1.0.a "$PREFIX"/lib/libpangomm-1.4.a
echo "=== final ==="
ls -l "$PREFIX"/lib/libglibmm* "$PREFIX"/lib/libcairomm* "$PREFIX"/lib/libpangomm* 2>/dev/null
echo "GTKMM DLLS DONE"