#!/bin/bash
# ci/40-ardour.sh -- apply patches, configure and build Ardour for Windows.
set -e
source "$(dirname "$0")/env.sh"
VERSION="${VERSION:-9.10.0}"

cd "$ARDOUR_SRC"

# --- apply source patches (idempotent) -------------------------------------
shopt -s nullglob
for p in "$CI_DIR"/patches/000[123]-*.patch; do
  if git apply --check "$p" 2>/dev/null; then
    git apply --whitespace=nowarn "$p"
    echo "applied $(basename "$p")"
  elif git apply --reverse --check "$p" 2>/dev/null; then
    echo "already applied $(basename "$p")"
  else
    echo "ERROR: cannot apply $(basename "$p") -- Ardour submodule revision changed?" >&2
    exit 1
  fi
done

# --- version: waf uses `git describe` --------------------------------------
if ! git describe HEAD >/dev/null 2>&1; then
  git -c user.email=ci@local -c user.name=ci tag -f -a "$VERSION" -m "$VERSION"
fi
echo "git describe: $(git describe HEAD)"

# --- toolchain --------------------------------------------------------------
export CC=${XPREFIX}-gcc
export CXX=${XPREFIX}-g++
export CPP=${XPREFIX}-cpp
export AR=${XPREFIX}-ar
export LD=${XPREFIX}-ld
export NM=${XPREFIX}-nm
export AS=${XPREFIX}-as
export STRIP=${XPREFIX}-strip
export WINRC=${XPREFIX}-windres
export RANLIB=${XPREFIX}-ranlib
export DLLTOOL=${XPREFIX}-dlltool

CFLAGS="-mstackrealign -O2" \
CXXFLAGS="-mstackrealign -O2" \
LDFLAGS="-L${PREFIX}/lib -Wl,--export-all-symbols -Wl,--allow-multiple-definition -liphlpapi -lssp" \
DEPSTACK_ROOT="$PREFIX" \
./waf configure \
  --keepflags \
  --dist-target=mingw \
  --internal-shared-libs \
  --ptformat \
  --with-backends=jack,portaudio,dummy \
  --optimize \
  --cxx17 \
  --also-include="${PREFIX}/include" \
  --prefix="${PREFIX}" \
  --libdir="${PREFIX}/lib"

./waf -j"$(nproc)"
./waf install

echo "=== built executables ==="
find build -maxdepth 3 \( -name 'ardour-*.exe' -o -name 'ardour9-*.exe' \) | head -20
