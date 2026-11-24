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
    ./configure --host=$XPREFIX --build=x86_64-linux --prefix=$PREFIX --disable-documentation
  sed -i 's/^allow_undefined_flag=.*/allow_undefined_flag=""/' libtool
  make -j$(nproc)
  make install
  echo "=== $name .libs ==="; ls .libs/*.a .libs/*.dll* 2>/dev/null || find . -name '*.dll.a' | head
}

build cairomm-1.13.1 tar.gz
build pangomm-2.42.0 tar.xz
echo "=== prefix ==="
ls -l "$PREFIX"/lib/libcairomm* "$PREFIX"/lib/libpangomm* 2>/dev/null
echo "CAIROMM/PANGOMM DONE"