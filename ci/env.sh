#!/bin/bash
# ci/env.sh -- common environment for every build step.
set -e
_CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- paths (single place) -------------------------------------------------
REPO_ROOT="${REPO_ROOT:-${GITHUB_WORKSPACE:-$(cd "$_CI_DIR/.." && pwd)}}"
# Heavy build trees (deps + tarball cache) go on the roomy disk.
ROOT="${ROOT:-/mnt/ci}"
PREFIX="${PREFIX:-$ROOT/win-stack-w64}"
BUILDD="${BUILDD:-$ROOT/win-build-w64}"
SRCDIR="${SRCDIR:-$ROOT/winsrc}"
# Ardour source = git submodule inside this repo (do NOT copy: .git must stay valid)
ARDOUR_SRC="${ARDOUR_SRC:-$REPO_ROOT/ardour}"
BUNDLE="${BUNDLE:-$ROOT/ardour-win64}"
export REPO_ROOT ROOT PREFIX BUILDD SRCDIR ARDOUR_SRC BUNDLE
export CI_DIR="$_CI_DIR"

# ---- toolchain ------------------------------------------------------------
export XPREFIX=x86_64-w64-mingw32
export HPREFIX=x86_64
export PKG_CONFIG=/usr/bin/pkg-config
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export PATH="/usr/lib/ccache:$PATH"
MINGW_GCCDIR="${MINGW_GCCDIR:-$(dirname "$(x86_64-w64-mingw32-gcc -print-file-name=libstdc++-6.dll)")}"
export MINGW_GCCDIR

# ccache: shared across the dependency stack and Ardour builds
export CCACHE_DIR="${CCACHE_DIR:-$ROOT/ccache}"
export CCACHE_BASEDIR="$REPO_ROOT"
mkdir -p "$CCACHE_DIR"

mkdir -p "$ROOT" "$PREFIX/bin" "$PREFIX/lib" "$PREFIX/include" "$PREFIX/.stamp" "$SRCDIR" "$BUILDD"
