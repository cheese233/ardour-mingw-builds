#!/bin/bash
source "$(dirname "$0")/env.sh"
set -e
XPREFIX=x86_64-w64-mingw32
export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig
CF="-I$PREFIX/include -O2 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -mstackrealign"
CX="-I$PREFIX/include -O2 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -std=gnu++11 -mstackrealign"

prep(){ local name=$1 ext=$2; cd "$BUILDD"; rm -rf "$name"; mkdir "$name"; tar xf "$SRCDIR/$name.$ext" -C "$name" --strip-components=1; cd "$name"; }
conf(){ CPPFLAGS="-I$PREFIX/include" CFLAGS="$CF" CXXFLAGS="$CX" LDFLAGS="-L$PREFIX/lib" ./configure --host=$XPREFIX --build=x86_64-linux --prefix=$PREFIX "$@"; }
mk(){ make LDFLAGS="-L$PREFIX/lib -no-undefined" -j$(nproc) && make install LDFLAGS="-L$PREFIX/lib -no-undefined"; }

echo "########## pixman (DLL) ##########"
prep pixman-0.42.2 tar.gz; conf --disable-libpng --disable-gtk --disable-tests; mk
ls -l "$PREFIX/lib/libpixman-1.dll.a"

echo "########## libpng (DLL) ##########"
prep libpng-1.6.50 tar.xz; conf; mk
ls -l "$PREFIX/lib/libpng16.dll.a"

echo "########## fontconfig (DLL) ##########"
prep fontconfig-2.13.1 tar.bz2
sed -i 's/po-conf test/po-conf/' Makefile.in || true
PATH="$PREFIX/bin:$PATH" conf --enable-libxml2 --disable-docs; mk
ls -l "$PREFIX/lib/libfontconfig.dll.a"

echo "########## cairo (DLL) ##########"
prep cairo-1.16.0 tar.xz
sed -i 's/ test perf//' Makefile.in || true
ax_cv_c_float_words_bigendian=no conf --disable-gtk-doc-html --enable-gobject=yes --disable-valgrind --enable-interpreter=no --enable-script=no --disable-xlib --disable-xcb --enable-win32
mk
ls -l "$PREFIX/lib/libcairo.dll.a" "$PREFIX/lib/libcairo-gobject.dll.a"

echo "########## remove static archives to force DLL usage ##########"
rm -f "$PREFIX/lib/libpixman-1.a" "$PREFIX/lib/libpng.a" "$PREFIX/lib/libpng16.a" \
      "$PREFIX/lib/libfontconfig.a" "$PREFIX/lib/libcairo.a" "$PREFIX/lib/libcairo-gobject.a"
echo "=== dll.a present ==="
ls -l "$PREFIX"/lib/libpixman-1.dll.a "$PREFIX"/lib/libpng16.dll.a "$PREFIX"/lib/libfontconfig.dll.a "$PREFIX"/lib/libcairo.dll.a
echo "CAIRO DLL CHAIN DONE"