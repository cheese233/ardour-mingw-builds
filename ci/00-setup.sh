#!/bin/bash
# ci/00-setup.sh -- install the mingw-w64 cross toolchain + build tools on the runner.
set -e
export DEBIAN_FRONTEND=noninteractive

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  build-essential \
  gcc-mingw-w64-x86-64-posix g++-mingw-w64-x86-64-posix mingw-w64 \
  git autoconf automake libtool libtool-bin pkg-config \
  curl wget unzip ed yasm nasm cmake ca-certificates gperf \
  meson ninja-build python3 gettext bison flex texinfo file \
  xz-utils p7zip-full zip ccache libglib2.0-dev \
  msitools wixl wixl-data

# Ardour's prebuilt Windows JACK (jack_win3264.tar.xz) is built with GCC 10-posix
# 20210110 (Debian bullseye). Ubuntu 22.04 ships 10-posix 20220113 whose libgcc/SEH
# exception ABI is incompatible with it: the JACK backend aborts with
# EXCEPTION_INVALID_DISPOSITION. Install the matching bullseye 10.2.1 toolchain.
echo "deb [trusted=yes] http://deb.debian.org/debian bullseye main" | sudo tee /etc/apt/sources.list.d/bullseye-mingw.list >/dev/null
sudo apt-get update
sudo apt-get install -y --allow-downgrades --allow-change-held-packages \
  binutils-mingw-w64-x86-64=2.35.2-2+8.11+b3 \
  binutils-mingw-w64-i686=2.35.2-2+8.11+b3 \
  mingw-w64-common=8.0.0-1 \
  mingw-w64-x86-64-dev=8.0.0-1 \
  gcc-mingw-w64-base=10.2.1-6+24.2 \
  gcc-mingw-w64-x86-64-posix=10.2.1-6+24.2 \
  gcc-mingw-w64-x86-64-posix-runtime=10.2.1-6+24.2 \
  g++-mingw-w64-x86-64-posix=10.2.1-6+24.2

# Prefer the POSIX-threaded mingw compilers (needed for std::mutex & friends).
sudo update-alternatives --set x86_64-w64-mingw32-gcc /usr/bin/x86_64-w64-mingw32-gcc-posix 2>/dev/null || true
sudo update-alternatives --set x86_64-w64-mingw32-g++ /usr/bin/x86_64-w64-mingw32-g++-posix 2>/dev/null || true
for t in gcc g++ cpp; do
  if [ -x "/usr/bin/x86_64-w64-mingw32-$t-posix" ]; then
    sudo ln -sf "/usr/bin/x86_64-w64-mingw32-$t-posix" "/usr/local/bin/x86_64-w64-mingw32-$t"
  fi
done

# Some waf scripts use `python`.
[ -e /usr/local/bin/python ] || sudo ln -sf "$(command -v python3)" /usr/local/bin/python

# Ubuntu 22.04 ships wixl 0.101 which has no installer UI. Build msitools 0.106
# from source so we can use WixUI_InstallDir (choose install path dialog).
sudo apt-get install -y --no-install-recommends valac libgsf-1-dev libgcab-dev libxml2-dev bats python3-venv
python3 -m venv /tmp/wixlvenv
/tmp/wixlvenv/bin/pip install --quiet --upgrade "meson>=1.4"
/tmp/wixlvenv/bin/meson --version
_wixl_src="$(mktemp -d)"
git clone --depth 1 --branch v0.106 --recurse-submodules \
  https://github.com/GNOME/msitools.git "$_wixl_src/msitools"
# meson demands subprojects/bats-core/bin/bats (test runner); satisfy it
mkdir -p "$_wixl_src/msitools/subprojects/bats-core/bin"
ln -sf "$(command -v bats)" "$_wixl_src/msitools/subprojects/bats-core/bin/bats"
( cd "$_wixl_src/msitools" \
  && /tmp/wixlvenv/bin/meson setup build --prefix=/usr/local -Dintrospection=false -Dvalidate-wxi=false \
  && ninja -C build && sudo ninja -C build install )
rm -rf "$_wixl_src"
hash -r
echo "=== wixl ==="; command -v wixl; wixl --version 2>&1 | head -1

echo "=== toolchain ==="
x86_64-w64-mingw32-gcc --version | head -1
x86_64-w64-mingw32-g++ --version | head -1
meson --version
cmake --version | head -1
