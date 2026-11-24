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
  if [ "$name" = "pangomm-2.42.0" ]; then
    # skip the X11-linked docs helper; only the library is needed
    printf 'all:\ninstall:\nclean:\n' > tools/Makefile
  fi
  make -j$(nproc)
  make install
  echo "=== $name .libs ==="; ls .libs/*.a .libs/*.dll* 2>/dev/null || find . -name '*.dll.a' | head
}

build cairomm-1.13.1 tar.gz

# pangomm: build only the library subdir (skip the X11-linked docs helper)
cd "$BUILDD"; rm -rf pangomm-2.42.0; mkdir pangomm-2.42.0
tar xf "$SRCDIR/pangomm-2.42.0.tar.xz" -C pangomm-2.42.0 --strip-components=1
cd pangomm-2.42.0
CPPFLAGS="-I$PREFIX/include" CFLAGS="$CF" CXXFLAGS="$CX" LDFLAGS="-L$PREFIX/lib" \
  ./configure --host=$XPREFIX --build=x86_64-linux --prefix=$PREFIX --disable-documentation
sed -i 's/^allow_undefined_flag=.*/allow_undefined_flag=""/' libtool
printf 'all:\ninstall:\nclean:\n' > tools/Makefile
make -C pango/pangomm -j$(nproc)
make -C pango/pangomm install
mkdir -p "$PREFIX/lib/pkgconfig"; cp -f pango/pangomm-1.4.pc "$PREFIX/lib/pkgconfig/" 2>/dev/null || true
echo "=== prefix ==="
ls -l "$PREFIX"/lib/libcairomm* "$PREFIX"/lib/libpangomm* 2>/dev/null
echo "CAIROMM/PANGOMM DONE"