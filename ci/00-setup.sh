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

echo "=== toolchain ==="
x86_64-w64-mingw32-gcc --version | head -1
x86_64-w64-mingw32-g++ --version | head -1
meson --version
cmake --version | head -1
