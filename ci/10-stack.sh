#!/bin/bash
source "$(dirname "$0")/env.sh"
# 10-stack.sh : build mingw-w64 win-stack for Ardour (x86_64) on Debian bullseye
# Adapted from ardour-build-tools/x-mingw.sh, versions follow nightly info.txt.
set -e
export XARCH=x86_64
XPREFIX=x86_64-w64-mingw32
HPREFIX=x86_64
WARCH=w64
STACKCFLAGS="-O2 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0"
MAKEFLAGS="-j$(nproc)"
mkdir -p "$BUILDD" "$PREFIX/bin" "$PREFIX/lib" "$PREFIX/include" "$PREFIX/.stamp" "$SRCDIR"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export PKG_CONFIG=/usr/bin/pkg-config
export PATH=/usr/lib/ccache:$PATH
# ccache wrappers for mingw
if [ -d /usr/lib/ccache ]; then
  for t in gcc g++ cpp ar ld nm as strip ranlib dlltool windres; do
    ln -sf ../../bin/ccache /usr/lib/ccache/${XPREFIX}-$t 2>/dev/null || true
  done
fi

need(){ test -f "$PREFIX/.stamp/$1"; }
mark(){ touch "$PREFIX/.stamp/$1"; echo "##### DONE $1 $(date +%H:%M:%S)"; }
download(){ local f=$1 url=$2; if [ ! -s "$SRCDIR/$f" ]; then echo "--- download $f"; rm -f "$SRCDIR/$f"; curl -fSLsS --retry 8 --retry-delay 3 --retry-all-errors --connect-timeout 30 -o "$SRCDIR/$f" "$url" || { echo "ERROR downloading $url"; rm -f "$SRCDIR/$f"; return 1; }; fi }
src(){ local name=$1 ext=$2 url=$3; download "$name.$ext" "$url"; rm -rf "$BUILDD/$name"; mkdir -p "$BUILDD/$name"; tar xf "$SRCDIR/$name.$ext" -C "$BUILDD/$name" --strip-components=1; cd "$BUILDD/$name"; }

aconf(){
  echo "=== configure $(pwd) ==="
  CPPFLAGS="-I$PREFIX/include $CPPFLAGS" \
  CFLAGS="-I$PREFIX/include $STACKCFLAGS -mstackrealign $CFLAGS" \
  CXXFLAGS="-I$PREFIX/include $STACKCFLAGS -std=gnu++11 -mstackrealign $CXXFLAGS" \
  LDFLAGS="-L$PREFIX/lib $LDFLAGS" \
  ./configure --host=$XPREFIX --build=${HPREFIX}-linux --prefix=$PREFIX "$@"
  make $MAKEFLAGS && make install
}
wafbuild(){
  echo "=== waf $(pwd) ==="
  CC=${XPREFIX}-gcc CXX=${XPREFIX}-g++ CPP=${XPREFIX}-cpp AR=${XPREFIX}-ar LD=${XPREFIX}-ld \
  NM=${XPREFIX}-nm AS=${XPREFIX}-as STRIP=${XPREFIX}-strip RANLIB=${XPREFIX}-ranlib DLLTOOL=${XPREFIX}-dlltool \
  CPPFLAGS="-I$PREFIX/include $CPPFLAGS" \
  CFLAGS="-I$PREFIX/include $STACKCFLAGS -mstackrealign $CFLAGS" \
  CXXFLAGS="-I$PREFIX/include $STACKCFLAGS -std=gnu++11 -mstackrealign $CXXFLAGS" \
  LDFLAGS="-L$PREFIX/lib $LDFLAGS" \
  ./waf configure --prefix=$PREFIX "$@" && ./waf -j$(nproc) && ./waf install
}
mesonbuild(){
  echo "=== meson $(pwd) ==="
  rm -rf build
  meson setup build --cross-file "$BUILDD/meson-cross.txt" --prefix=$PREFIX --libdir=lib --buildtype=release "$@"
  ninja -C build && ninja -C build install
}

# Promote Requires.private/Libs.private into public for static-only libs so that
# downstream shared-DLL links resolve their symbols. Only touches named .pc files.
fixpc(){
python3 - "$PREFIX/lib/pkgconfig" "$@" <<'PYEOF'
import sys,os
d=sys.argv[1]
for name in sys.argv[2:]:
    f=os.path.join(d,name+'.pc')
    if not os.path.exists(f): continue
    lines=open(f,encoding='utf-8',errors='replace').read().splitlines()
    req=[];libs=[];rest=[]
    for ln in lines:
        s=ln.strip(); low=s.lower()
        if low.startswith('requires.private:'): req.append(s.split(':',1)[1].strip()); continue
        if low.startswith('requires:'): req.insert(0,s.split(':',1)[1].strip()); continue
        if low.startswith('libs.private:'): libs.append(s.split(':',1)[1].strip()); continue
        if low.startswith('libs:'): libs.insert(0,s.split(':',1)[1].strip()); continue
        rest.append(ln)
    reqline=' '.join(x for x in req if x)
    libline=' '.join(x for x in libs if x)
    out=[]; inserted=False
    for ln in rest:
        if ln.strip().lower().startswith(('requires:','libs:')): continue
        out.append(ln)
        if ln.strip().lower().startswith('version:'):
            if reqline: out.append('Requires: '+reqline)
            if libline: out.append('Libs: '+libline)
            inserted=True
    if not inserted:
        if reqline: out.append('Requires: '+reqline)
        if libline: out.append('Libs: '+libline)
    open(f,'w').write('\n'.join(out)+'\n')
PYEOF
  # Delete .la of static-only libs so libtool links the .a directly instead of
  # dropping the -l flag when a .la advertises a DLL that was never built.
  for la in "$PREFIX"/lib/*.la; do
    [ -e "$la" ] || continue
    b=$(basename "$la" .la)
    if [ -f "$PREFIX/lib/$b.a" ] && [ ! -f "$PREFIX/lib/$b.dll.a" ]; then rm -f "$la"; fi
  done
}

STATICPC="cairo cairo-gobject fontconfig libpng16 libpng16-config libpng flac sndfile libarchive pixman-1 samplerate libcurl"

cat > "$BUILDD/meson-cross.txt" <<EOF
[binaries]
c = '/usr/bin/${XPREFIX}-gcc'
cpp = '/usr/bin/${XPREFIX}-g++'
ld = '/usr/bin/${XPREFIX}-ld'
ar = '/usr/bin/${XPREFIX}-ar'
strip = '/usr/bin/${XPREFIX}-strip'
windres = '/usr/bin/${XPREFIX}-windres'
pkgconfig = '/usr/bin/pkg-config'
[properties]
c_args = ['-I$PREFIX/include', '-O2', '-mstackrealign', '-U_FORTIFY_SOURCE', '-D_FORTIFY_SOURCE=0']
cpp_args = ['-I$PREFIX/include', '-O2', '-mstackrealign', '-U_FORTIFY_SOURCE', '-D_FORTIFY_SOURCE=0', '-std=gnu++11']
c_link_args = ['-L$PREFIX/lib', '-Wl,-Bstatic', '-lssp', '-Wl,-Bdynamic']
cpp_link_args = ['-L$PREFIX/lib', '-Wl,-Bstatic', '-lssp', '-Wl,-Bdynamic']
[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF

##########################################################################
echo "========== BUILD STARTS $(date) =========="
fixpc $STATICPC

if ! need xz; then
  src xz-5.2.2 tar.bz2 https://tukaani.org/xz/xz-5.2.2.tar.bz2
  # static-only: avoids xz's Windows liblzma.def/.def.in generation, which races
  # and is broken with newer libtool. libarchive links liblzma statically.
  MAKEFLAGS="-j1" aconf --disable-shared --enable-static --disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo --disable-scripts --disable-nls
  mark xz
fi

if ! need zlib; then
  download zlib-1.3.2.tar.gz https://zlib.net/fossils/zlib-1.3.2.tar.gz
  rm -rf "$BUILDD/zlib"; mkdir -p "$BUILDD/zlib"; cd "$BUILDD/zlib"
  tar xf "$SRCDIR/zlib-1.3.2.tar.gz" --strip-components=1
  make -fwin32/Makefile.gcc PREFIX=${XPREFIX}- $MAKEFLAGS
  make -fwin32/Makefile.gcc PREFIX=${XPREFIX}- SHARED_MODE=1 \
    INCLUDE_PATH=$PREFIX/include LIBRARY_PATH=$PREFIX/lib BINARY_PATH=$PREFIX/bin install
  mark zlib
fi

if ! need libffi; then
  src libffi-3.5.2 tar.gz https://github.com/libffi/libffi/releases/download/v3.5.2/libffi-3.5.2.tar.gz
  aconf --disable-docs
  mark libffi
fi

if ! need libiconv; then
  src libiconv-1.16 tar.gz https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.16.tar.gz
  aconf --with-included-gettext --enable-static --enable-shared
  mark libiconv
fi

if ! need gettext; then
  src gettext-0.22.4 tar.gz https://ftp.gnu.org/pub/gnu/gettext/gettext-0.22.4.tar.gz
  CPPFLAGS="-I$PREFIX/include" CFLAGS="-I$PREFIX/include $STACKCFLAGS -mstackrealign" \
  CXXFLAGS="-I$PREFIX/include $STACKCFLAGS -mstackrealign" LDFLAGS="-L$PREFIX/lib" \
  ./configure --host=$XPREFIX --build=${HPREFIX}-linux --prefix=$PREFIX \
    --disable-java --disable-native-java --disable-csharp --disable-openmp --without-emacs --disable-rpath
  make $MAKEFLAGS && make install
  mark gettext
fi

if ! need expat; then
  src expat-2.8.4 tar.xz https://github.com/libexpat/libexpat/releases/download/R_2_8_4/expat-2.8.4.tar.xz
  aconf --without-docbook --without-xmlwf --without-examples --disable-static
  mark expat
fi

if ! need libxml2; then
  src libxml2-2.9.14 tar.xz https://download.gnome.org/sources/libxml2/2.9/libxml2-2.9.14.tar.xz
  aconf --without-python --with-threads=no --with-zlib=$PREFIX --with-iconv=$PREFIX --disable-static --without-lzma
  mark libxml2
fi

if ! need jpeg; then
  download jpegsrc.v9a.tar.gz https://www.ijg.org/files/jpegsrc.v9a.tar.gz
  rm -rf "$BUILDD/jpeg-9a"; mkdir -p "$BUILDD/jpeg-9a"; cd "$BUILDD/jpeg-9a"
  tar xzf "$SRCDIR/jpegsrc.v9a.tar.gz" --strip-components=1
  aconf --disable-static
  mark jpeg
fi

if ! need tiff; then
  src tiff-4.0.3 tar.gz https://download.osgeo.org/libtiff/old/tiff-4.0.3.tar.gz
  aconf --disable-cxx --disable-static --disable-lzma --without-x
  mark tiff
fi

if ! need libogg; then
  src libogg-1.3.2 tar.gz https://downloads.xiph.org/releases/ogg/libogg-1.3.2.tar.gz
  aconf --disable-static
  mark libogg
fi

if ! need opus; then
  src opus-1.3.1 tar.gz https://downloads.xiph.org/releases/opus/opus-1.3.1.tar.gz
  aconf --disable-static --disable-doc --disable-extra-programs --disable-hardening
  mark opus
fi

if ! need libvorbis; then
  src libvorbis-1.3.4 tar.gz https://downloads.xiph.org/releases/vorbis/libvorbis-1.3.4.tar.gz
  aconf --disable-examples --with-ogg=$PREFIX --disable-static
  mark libvorbis
fi

if ! need flac; then
  src flac-1.3.2 tar.xz https://downloads.xiph.org/releases/flac/flac-1.3.2.tar.xz
  # flac forces -D_FORTIFY_SOURCE=2 which produces __*_chk refs needing libssp;
  # strip it so no ssp dependency leaks into the static archive.
  sed -i 's/-D_FORTIFY_SOURCE=2//g' configure || true
  aconf --disable-examples --disable-docs --disable-oggtest --disable-static --without-xmms --disable-cpplibs
  mark flac
fi

if ! need libsndfile; then
  src libsndfile-1.1.0 tar.xz http://ardour.org/files/deps/libsndfile-1.1.0-41-gd8503a66.tar.xz
  aconf --disable-static --disable-sqlite
  mark libsndfile
fi

if ! need libsamplerate; then
  src libsamplerate-0.1.9 tar.gz http://www.mega-nerd.com/SRC/libsamplerate-0.1.9.tar.gz
  aconf --disable-static --disable-sndfile --disable-fftw
  mark libsamplerate
fi

if ! need termcap; then
  src termcap-1.3.1 tar.gz https://ftp.gnu.org/gnu/termcap/termcap-1.3.1.tar.gz
  ./configure --host=$XPREFIX --build=${HPREFIX}-linux --prefix=$PREFIX
  make $MAKEFLAGS install CC=${XPREFIX}-gcc AR=${XPREFIX}-ar RANLIB=${XPREFIX}-ranlib
  mark termcap
fi

# readline intentionally skipped: only needed for Ardour's optional Lua CLI tool
# and readline 8.2 has mingw-header issues. HAVE_READLINE stays undefined.

if ! need libpng; then
  src libpng-1.6.50 tar.xz https://downloads.sourceforge.net/project/libpng/libpng16/1.6.50/libpng-1.6.50.tar.xz
  aconf --disable-static --enable-png-config
  mark libpng
fi

if ! need freetype; then
  src freetype-2.13.3 tar.xz https://download.savannah.gnu.org/releases/freetype/freetype-2.13.3.tar.xz
  aconf --with-harfbuzz=no --with-bzip2=no --with-brotli=no --disable-static --without-png
  mark freetype
fi

if ! need glib; then
  src glib-2.64.6 tar.xz https://download.gnome.org/sources/glib/2.64/glib-2.64.6.tar.xz
  mesonbuild -Dinternal_pcre=true -Dselinux=disabled -Dlibmount=disabled -Dman=false -Dgtk_doc=false
  mark glib
fi

if ! need harfbuzz; then
  src harfbuzz-2.6.7 tar.xz https://www.freedesktop.org/software/harfbuzz/release/harfbuzz-2.6.7.tar.xz
  aconf --with-glib --with-freetype --without-icu --without-cairo --disable-static --with-uniscribe
  mark harfbuzz
fi

if ! need fribidi; then
  src fribidi-1.0.9 tar.xz https://github.com/fribidi/fribidi/releases/download/v1.0.9/fribidi-1.0.9.tar.xz
  mesonbuild -Ddocs=false
  mark fribidi
fi

if ! need fontconfig; then
  src fontconfig-2.13.1 tar.bz2 https://www.freedesktop.org/software/fontconfig/release/fontconfig-2.13.1.tar.bz2
  sed -i 's/po-conf test/po-conf/' Makefile.in || true
  CPPFLAGS="-I$PREFIX/include" CFLAGS="-I$PREFIX/include $STACKCFLAGS -mstackrealign" \
  CXXFLAGS="-I$PREFIX/include $STACKCFLAGS -mstackrealign" LDFLAGS="-L$PREFIX/lib" \
  ./configure --host=$XPREFIX --build=${HPREFIX}-linux --prefix=$PREFIX --enable-libxml2 --disable-docs
  make $MAKEFLAGS
  make install || true
  mkdir -p $PREFIX/lib/pkgconfig
  cat > $PREFIX/lib/pkgconfig/fontconfig.pc <<EOF
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: Fontconfig
Description: Font configuration and customization library
Version: 2.13.1
Requires: freetype2, libxml-2.0
Libs: -L\${libdir} -lfontconfig
Cflags: -I\${includedir}
EOF
  mark fontconfig
fi

if ! need pixman; then
  src pixman-0.42.2 tar.gz https://www.cairographics.org/releases/pixman-0.42.2.tar.gz
  aconf --disable-static --disable-gtk --disable-libpng --disable-tests
  mark pixman
fi

if ! need cairo; then
  src cairo-1.16.0 tar.xz https://www.cairographics.org/releases/cairo-1.16.0.tar.xz
  sed -i 's/ test perf//' Makefile.in || true
  ax_cv_c_float_words_bigendian=no aconf --disable-gtk-doc-html --enable-gobject=yes \
    --disable-valgrind --enable-interpreter=no --enable-script=no --disable-static --disable-xlib --disable-xcb --enable-win32
  mark cairo
fi

if ! need libarchive; then
  src libarchive-3.6.1 tar.gz https://www.libarchive.org/downloads/libarchive-3.6.1.tar.gz
  aconf --disable-bsdtar --disable-bsdcat --disable-bsdcpio --without-openssl --without-xml2 --without-expat --disable-shared --enable-static
  mark libarchive
fi

if ! need pango; then
  fixpc $STATICPC
  src pango-1.42.4 tar.xz https://download.gnome.org/sources/pango/1.42/pango-1.42.4.tar.xz
  mesonbuild -Denable_docs=false -Dgir=false
  mark pango
fi

if ! need libsigcxx; then
  src libsigc++-2.10.2 tar.xz https://download.gnome.org/sources/libsigc++/2.10/libsigc++-2.10.2.tar.xz
  aconf --disable-static --disable-documentation
  mark libsigcxx
fi

if ! need glibmm; then
  src glibmm-2.62.0 tar.xz https://download.gnome.org/sources/glibmm/2.62/glibmm-2.62.0.tar.xz
  aconf --disable-static --disable-documentation
  mark glibmm
fi

if ! need cairomm; then
  src cairomm-1.13.1 tar.gz https://www.cairographics.org/releases/cairomm-1.13.1.tar.gz
  aconf --disable-static --disable-documentation
  mark cairomm
fi

if ! need pangomm; then
  src pangomm-2.42.0 tar.xz https://download.gnome.org/sources/pangomm/2.42/pangomm-2.42.0.tar.xz
  aconf --disable-static --disable-documentation
  mark pangomm
fi

if ! need fftw; then
  src fftw-3.3.8 tar.gz https://fftw.org/fftw-3.3.8.tar.gz
  aconf --enable-single --enable-float --enable-sse --with-our-malloc --enable-avx --disable-mpi \
        --enable-threads --with-combined-threads --disable-static --enable-shared --disable-fortran
  make clean
  aconf --enable-type-prefix --with-our-malloc --enable-avx --disable-mpi --enable-threads \
        --with-combined-threads --disable-static --enable-shared --disable-fortran
  mark fftw
fi

if ! need taglib; then
  src taglib-1.9.1 tar.gz https://github.com/taglib/taglib/releases/download/v1.9.1/taglib-1.9.1.tar.gz
  sed -i 's/~ListPrivate/virtual ~ListPrivate/' taglib/toolkit/tlist.tcc || true
  rm -rf build && mkdir build && cd build
  cmake -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_C_COMPILER=${XPREFIX}-gcc -DCMAKE_CXX_COMPILER=${XPREFIX}-g++ \
        -DCMAKE_RC_COMPILER=${XPREFIX}-windres -DZLIB_ROOT=$PREFIX -DBUILD_SHARED_LIBS=ON ..
  make $MAKEFLAGS && make install
  mkdir -p $PREFIX/lib/pkgconfig
  cat > $PREFIX/lib/pkgconfig/taglib.pc <<EOF
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include
Name: TagLib
Description: Audio meta-data library
Requires:
Version: 1.9.1
Libs: -L\${libdir} -ltag
Cflags: -I\${includedir}/taglib
EOF
  mark taglib
fi

if ! need liblo; then
  src liblo-0.28 tar.gz https://downloads.sourceforge.net/liblo/liblo-0.28.tar.gz
  sed -i 's/-Werror//g' configure || true
  CPPFLAGS="-D_WIN32_WINNT=0x0600" LIBS="-lws2_32" \
  CFLAGS="-I$PREFIX/include $STACKCFLAGS -mstackrealign" \
  CXXFLAGS="-I$PREFIX/include $STACKCFLAGS -std=gnu++11 -mstackrealign" LDFLAGS="-L$PREFIX/lib" \
  ./configure --host=$XPREFIX --build=${HPREFIX}-linux --prefix=$PREFIX --enable-shared --disable-static --disable-examples --disable-tools
  sed -i '/^noinst_PROGRAMS *=/d; /^check_PROGRAMS *=/d; /^bin_PROGRAMS *=/d' src/Makefile || true
  make $MAKEFLAGS && make install
  mark liblo
fi

if ! need boost; then
  src boost_1_68_0 tar.bz2 https://archives.boost.io/release/1.68.0/source/boost_1_68_0.tar.bz2
  ./bootstrap.sh --prefix=$PREFIX
  echo "using gcc : 10 : ${XPREFIX}-g++ : ${XPREFIX}-windres ${XPREFIX}-ar ;" > user-config.jam
  ./b2 --prefix=$PREFIX toolset=gcc target-os=windows architecture=x86 address-model=64 \
       variant=release threading=multi threadapi=win32 link=shared runtime-link=shared cxxstd=11 \
       --with-exception --with-regex --with-atomic --layout=tagged --user-config=user-config.jam \
       -j$(nproc) install
  mark boost
fi

if ! need ladspa; then
  download ladspa.h https://community.ardour.org/files/ladspa.h
  cp "$SRCDIR/ladspa.h" "$PREFIX/include/ladspa.h"
  mark ladspa
fi

if ! need vamp; then
  src vamp-plugin-sdk-2.9.0 tar.gz http://ardour.org/files/deps/vamp-plugin-sdk-2.9.0.tar.gz
  { echo '#ifndef M_PI'; echo '# define M_PI 3.14159265358979323846'; echo '#endif'; cat src/vamp-hostsdk/Window.h; } > /tmp/wh && mv /tmp/wh src/vamp-hostsdk/Window.h
  sed -i "s/^AR \?= ar/AR = ${XPREFIX}-ar/" Makefile.in || true
  sed -i "s/^RANLIB \?= ranlib/RANLIB = ${XPREFIX}-ranlib/" Makefile.in || true
  MAKEFLAGS="install -j$(nproc)" aconf
  sed -i 's/ -ldl//' $PREFIX/lib/pkgconfig/vamp-hostsdk.pc 2>/dev/null || true
  sed -i 's/ -ldl//' $PREFIX/lib/pkgconfig/vamp-sdk.pc 2>/dev/null || true
  mark vamp
fi

if ! need rubberband; then
  src rubberband-3.3.0 tar.bz2 https://breakfastquay.com/files/releases/rubberband-3.3.0.tar.bz2
  mesonbuild -Dfft=fftw -Dresampler=builtin -Dladspa=disabled -Dlv2=disabled -Dvamp=disabled -Dcmdline=disabled -Dtests=disabled -Djni=disabled
  mark rubberband
fi

if ! need libgnurx; then
  src mingw-libgnurx-2.5.1 tar.gz https://sourceforge.net/projects/mingw/files/Other/UserContributed/regex/mingw-regex-2.5.1/mingw-libgnurx-2.5.1-src.tar.gz/download
  aconf --disable-static
  mark libgnurx
fi

if ! need aubio; then
  src aubio-0.3.2 tar.gz https://aubio.org/pub/aubio-0.3.2.tar.gz
  sed -i 's/examples / /' Makefile.in || true
  aconf --enable-fftw3
  sed -i 's/ -laubio/ -laubio -lfftw3f/' $PREFIX/lib/pkgconfig/aubio.pc 2>/dev/null || true
  mark aubio
fi

if ! need libwebsockets; then
  src libwebsockets-4.3.0-13 tar.gz http://ardour.org/files/deps/libwebsockets-4.3.0-13.tar.gz
  rm -rf build && mkdir build && cd build
  cmake -DLWS_WITH_SSL=OFF -DLWS_WITH_EXTERNAL_POLL=ON -DMINGW=ON \
        -DLWS_WITHOUT_TEST_SERVER=ON -DLWS_WITHOUT_TESTAPPS=ON -DDISABLE_WERROR=ON -DLWS_WITH_EVLIB_PLUGINS=OFF \
        -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_C_COMPILER=${XPREFIX}-gcc -DCMAKE_CXX_COMPILER=${XPREFIX}-g++ \
        -DCMAKE_RC_COMPILER=${XPREFIX}-windres -DCMAKE_C_FLAGS="-isystem $PREFIX/include $STACKCFLAGS -mstackrealign" \
        -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_BUILD_TYPE=Release ..
  make $MAKEFLAGS && make install
  mark libwebsockets
fi

if ! need libusb; then
  src libusb-1.0.27 tar.bz2 https://github.com/libusb/libusb/releases/download/v1.0.27/libusb-1.0.27.tar.bz2
  aconf --disable-static --disable-udev --disable-tests
  mark libusb
fi

if ! need raptor2; then
  src raptor2-2.0.14 tar.gz https://download.librdf.org/source/raptor2-2.0.14.tar.gz
  PATH="$PREFIX/bin:$PATH" aconf --disable-static --with-xml2-config=$PREFIX/bin/xml2-config --with-www=none --disable-gtk-doc
  mark raptor2
fi

if ! need LRDF; then
  src LRDF-0.5.3-rg tar.gz https://github.com/x42/LRDF/archive/0.5.3-rg.tar.gz
  if [ -x ./autogen.sh ]; then ./autogen.sh; else autoreconf -fi; fi
  aconf --disable-shared --enable-static
  mark LRDF
fi

if ! need lv2; then
  src lv2-1.18.2 tar.bz2 http://ardour.org/files/deps/lv2-1.18.2-g611759d.tar.bz2
  wafbuild --no-plugins --copy-headers --lv2dir=$PREFIX/lib/lv2
  mark lv2
fi

if ! need serd; then
  src serd-0.30.11 tar.bz2 http://ardour.org/files/deps/serd-0.30.11-g36f1cecc.tar.bz2
  wafbuild
  mark serd
fi

if ! need sord; then
  src sord-0.16.9 tar.bz2 http://ardour.org/files/deps/sord-0.16.9-gd2efdb2.tar.bz2
  wafbuild --no-utils
  mark sord
fi

if ! need sratom; then
  src sratom-0.6.8 tar.bz2 http://ardour.org/files/deps/sratom-0.6.8-gc46452c.tar.bz2
  wafbuild
  mark sratom
fi

if ! need lilv; then
  src lilv-0.24.13 tar.bz2 http://ardour.org/files/deps/lilv-0.24.13-g71a2ff5.tar.bz2
  wafbuild --no-utils
  mark lilv
fi

if ! need suil; then
  src suil-0.10.8 tar.bz2 http://ardour.org/files/deps/suil-0.10.8-g05c2afb.tar.bz2
  wafbuild
  mark suil
fi

if ! need curl; then
  src curl-7.66.0 tar.gz https://curl.se/download/curl-7.66.0.tar.gz
  CPPFLAGS="-I$PREFIX/include" CFLAGS="-I$PREFIX/include $STACKCFLAGS -mstackrealign" \
  CXXFLAGS="-I$PREFIX/include $STACKCFLAGS -std=gnu++11 -mstackrealign" LDFLAGS="-L$PREFIX/lib" \
  ./configure --host=$XPREFIX --build=${HPREFIX}-linux --prefix=$PREFIX \
    --with-winssl --disable-ldap --disable-shared --enable-static \
    --without-libidn2 --without-nghttp2 --without-librtmp --without-libssh2 --without-zstd --without-brotli
  make -C include install
  make -C lib $MAKEFLAGS && make -C lib install
  mark curl
fi

if false; then  # PortAudio is built separately by ci/30-portaudio-wasapi.sh
  # ASIO SDK via soundfind mirror
  if [ ! -d "$BUILDD/soundfind" ]; then
    cd "$BUILDD"; git clone --depth 1 https://github.com/danieldram/soundfind.git || true
  fi
  download pa_waves3.diff http://robin.linuxaudio.org/tmp/pa_waves3.diff
  src portaudio-svn1963 tgz http://ardour.org/files/deps/portaudio-svn1963.tgz
  patch -p1 < "$SRCDIR/pa_waves3.diff" || true
  # build xp variant
  ./configure --host=$XPREFIX --build=${HPREFIX}-linux --prefix=$PREFIX \
    --with-asiodir=$BUILDD/soundfind/ASIOSDK2/ --with-winapi=asio,wmme --without-jack \
    CPPFLAGS="-I$PREFIX/include" CFLAGS="-I$PREFIX/include $STACKCFLAGS -mstackrealign" LDFLAGS="-L$PREFIX/lib"
  sed -i 's/-luuid//g' Makefile || true
  make $MAKEFLAGS && make install
  make clean
  # vista+ wasapi variant
  sed -i 's/mingw-include//' configure || true
  sed -i 's/_WIN32_WINNT=0x0501/_WIN32_WINNT=0x0600/' configure || true
  sed -i 's/WINVER=0x0501/WINVER=0x0600/' configure || true
  ./configure --host=$XPREFIX --build=${HPREFIX}-linux --prefix=$PREFIX \
    --with-asiodir=$BUILDD/soundfind/ASIOSDK2/ --with-winapi=asio,wmme,wasapi --without-jack \
    CPPFLAGS="-I$PREFIX/include" CFLAGS="-I$PREFIX/include $STACKCFLAGS -mstackrealign" LDFLAGS="-L$PREFIX/lib"
  sed -i 's/-luuid//g' Makefile || true
  make $MAKEFLAGS && make install
  cp include/pa_asio.h $PREFIX/include/ 2>/dev/null || true
  cp $BUILDD/soundfind/ASIOSDK2/common/asio.h $PREFIX/include/ 2>/dev/null || true
  mark portaudio
fi

if ! need cppunit; then
  src cppunit-1.13.2 tar.gz https://dev-www.libreoffice.org/src/cppunit-1.13.2.tar.gz
  aconf --disable-doxygen --disable-static
  mark cppunit
fi

if ! need jack; then
  download jack_win3264.tar.xz http://ardour.org/files/deps/jack_win3264.tar.xz
  cd "$PREFIX"
  tar xf "$SRCDIR/jack_win3264.tar.xz"
  bash "$PREFIX/update_pc_prefix.sh" "$WARCH" || true
  mark jack
fi

if ! need drmingw; then
  download drmingw.tar.xz http://ardour.org/files/deps/drmingw.tar.xz
  rm -rf "$BUILDD/drmingw"; mkdir -p "$BUILDD/drmingw"; cd "$BUILDD/drmingw"
  tar xf "$SRCDIR/drmingw.tar.xz" --strip-components=1
  cp -av $WARCH/* "$PREFIX"/ || true
  mark drmingw
fi

fixpc $STATICPC
echo "********** STACK COMPLETE $(date) **********"
ls $PREFIX/lib/pkgconfig | tr '\n' ' '; echo