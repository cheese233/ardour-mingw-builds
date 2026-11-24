#!/bin/bash
# ci/30-portaudio-wasapi.sh -- rebuild PortAudio with WASAPI (self-contained).
set -e
source "$(dirname "$0")/env.sh"

CF="-I$PREFIX/include -O2 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -mstackrealign"

# ensure `patch` exists (not part of build-essential)
command -v patch >/dev/null 2>&1 || sudo apt-get install -y patch

# --- inputs ---------------------------------------------------------------
[ -f "$SRCDIR/portaudio-svn1963.tgz" ] || \
  curl -k -L --retry 3 -o "$SRCDIR/portaudio-svn1963.tgz" http://ardour.org/files/deps/portaudio-svn1963.tgz
[ -f "$SRCDIR/pa_waves3.diff" ] || \
  curl -k -L --retry 3 -o "$SRCDIR/pa_waves3.diff" http://robin.linuxaudio.org/tmp/pa_waves3.diff
if [ ! -d "$BUILDD/soundfind/ASIOSDK2" ]; then
  ( cd "$BUILDD" && git clone --depth 1 https://github.com/danieldram/soundfind.git )
fi

cd "$BUILDD"; rm -rf portaudio-svn1963; mkdir portaudio-svn1963
tar xf "$SRCDIR/portaudio-svn1963.tgz" -C portaudio-svn1963 --strip-components=1
cd portaudio-svn1963

if patch -p1 -N --dry-run < "$SRCDIR/pa_waves3.diff" >/dev/null 2>&1; then
  patch -p1 -N < "$SRCDIR/pa_waves3.diff" || true
fi
# the tarball ships CRLF; normalize so our LF diff applies cleanly
sed -i 's/\r$//' src/hostapi/wasapi/pa_win_wasapi.c
if ! patch -p1 -N --forward < "$CI_DIR/patches/0004-portaudio-wasapi-mingw.patch"; then
  echo "ERROR: failed to apply WASAPI mingw include patch" >&2
  exit 1
fi

sed -i 's/mingw-include//' configure || true
sed -i 's/_WIN32_WINNT=0x0501/_WIN32_WINNT=0x0600/' configure || true
sed -i 's/WINVER=0x0501/WINVER=0x0600/' configure || true

CPPFLAGS="-I$PREFIX/include -D_WIN32_WINNT=0x0600 -DWINVER=0x0600" CFLAGS="$CF" LDFLAGS="-L$PREFIX/lib" \
  ./configure --host=$XPREFIX --build=x86_64-linux --prefix=$PREFIX \
    --with-asiodir="$BUILDD/soundfind/ASIOSDK2/" --with-winapi=asio,wmme,wasapi --without-jack

sed -i 's/-luuid//g' Makefile || true
make -j"$(nproc)"
make install

cp -f include/pa_asio.h "$PREFIX/include/" 2>/dev/null || true
cp -f "$BUILDD/soundfind/ASIOSDK2/common/asio.h" "$PREFIX/include/" 2>/dev/null || true

echo "=== WASAPI strings in installed dll ==="
strings -a "$PREFIX/bin/libportaudio-2.dll" | grep -i "Windows WASAPI" | head
echo "PORTAUDIO WASAPI DONE"
