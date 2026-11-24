#!/bin/bash
source "$(dirname "$0")/env.sh"
set -e
XPREFIX=x86_64-w64-mingw32
export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig
CF="-I$PREFIX/include -O2 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -mstackrealign"
CX="-I$PREFIX/include -O2 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -std=gnu++11 -mstackrealign"
LD="-L$PREFIX/lib"

echo "================ LIBLO ================"
cd "$BUILDD"; rm -rf liblo-0.28; mkdir liblo-0.28
tar xf "$SRCDIR/liblo-0.28.tar.gz" -C liblo-0.28 --strip-components=1
cd liblo-0.28
sed -i 's/-Werror//g' configure || true
CPPFLAGS="-D_WIN32_WINNT=0x0600" LIBS="-lws2_32" CFLAGS="$CF" CXXFLAGS="$CX" LDFLAGS="$LD" \
  ./configure --host=$XPREFIX --build=x86_64-linux --prefix=$PREFIX \
  --disable-shared --enable-static --disable-examples --disable-tools
make -C src -j$(nproc) liblo.la
mkdir -p "$PREFIX/lib" "$PREFIX/include/lo" "$PREFIX/lib/pkgconfig"
cp -f src/.libs/liblo.a "$PREFIX/lib/"
cp -f lo/*.h "$PREFIX/include/lo/"
cat > "$PREFIX/lib/pkgconfig/liblo.pc" <<EOF
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: liblo
Version: 0.28
Description: Lightweight OSC implementation
Libs: -L\${libdir} -llo -lws2_32 -liphlpapi
Cflags: -I\${includedir}
EOF
ls -l "$PREFIX/lib/liblo.a" "$PREFIX/lib/pkgconfig/liblo.pc" || true

echo "================ VAMP ================"
cd "$BUILDD"; rm -rf vamp-plugin-sdk-2.9.0; mkdir vamp-plugin-sdk-2.9.0
tar xf "$SRCDIR/vamp-plugin-sdk-2.9.0.tar.gz" -C vamp-plugin-sdk-2.9.0 --strip-components=1
cd vamp-plugin-sdk-2.9.0
{ echo '#ifndef M_PI'; echo '# define M_PI 3.14159265358979323846'; echo '#endif'; cat src/vamp-hostsdk/Window.h; } > /tmp/wh && mv /tmp/wh src/vamp-hostsdk/Window.h
CPPFLAGS="-I$PREFIX/include" CFLAGS="$CF" CXXFLAGS="$CX" LDFLAGS="$LD" LIBS="-Wl,-Bstatic -lssp -Wl,-Bdynamic" \
  ./configure --host=$XPREFIX --build=x86_64-linux --prefix=$PREFIX
ln -sf vamp-simple-host.exe host/vamp-simple-host
ln -sf vamp-rdf-template-generator.exe rdf/generator/vamp-rdf-template-generator
make install INSTALL_PREFIX=$PREFIX -j$(nproc)
sed -i 's/ -ldl//' "$PREFIX/lib/pkgconfig/vamp-hostsdk.pc" 2>/dev/null || true
sed -i 's/ -ldl//' "$PREFIX/lib/pkgconfig/vamp-sdk.pc" 2>/dev/null || true
ls -l "$PREFIX"/lib/libvamp* "$PREFIX"/lib/pkgconfig/vamp* 2>/dev/null || true

echo "================ CURL PC ================"
cp -f "$BUILDD/curl-7.66.0/libcurl.pc" "$PREFIX/lib/pkgconfig/" 2>/dev/null || true
ls -l "$PREFIX/lib/pkgconfig/libcurl.pc" "$PREFIX/lib/libcurl.a" 2>/dev/null || true

echo "================ VERIFY ================"
export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig
for m in liblo vamp-sdk vamp-hostsdk libcurl; do printf "%-14s " $m; pkg-config --exists $m && pkg-config --modversion $m || echo MISSING; done
echo "FIXUPS DONE"