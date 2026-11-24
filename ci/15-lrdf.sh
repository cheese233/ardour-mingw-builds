#!/bin/bash
source "$(dirname "$0")/env.sh"
set -e
XPREFIX=x86_64-w64-mingw32
export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig
CF="-I$PREFIX/include -O2 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -mstackrealign"
cd "$BUILDD"; rm -rf LRDF-0.5.3-rg; mkdir LRDF-0.5.3-rg
tar xf "$SRCDIR/LRDF-0.5.3-rg.tar.gz" -C LRDF-0.5.3-rg --strip-components=1
cd LRDF-0.5.3-rg
if [ -x ./autogen.sh ]; then ./autogen.sh; else autoreconf -fi; fi
CPPFLAGS="-DRAPTOR_STATIC -I$PREFIX/include" CFLAGS="$CF" LDFLAGS="-L$PREFIX/lib" LIBS="-Wl,-Bstatic -lssp -Wl,-Bdynamic" \
  ./configure --host=$XPREFIX --build=x86_64-linux --prefix=$PREFIX --disable-shared --enable-static
make -j$(nproc) && make install
cat > "$PREFIX/lib/pkgconfig/lrdf.pc" <<EOF
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: LRDF
Description: Lightweight RDF library for LADSPA plugins
Version: 0.5.3
Libs: -L\${libdir} -llrdf -lraptor2 -lxml2 -lz -liconv -lcharset -lws2_32
Cflags: -I\${includedir}
EOF
ls -l "$PREFIX/lib/liblrdf.a" "$PREFIX/lib/pkgconfig/lrdf.pc"
echo "LRDF REBUILT"