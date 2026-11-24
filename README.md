# Ardour for Windows x64 → MSI → GitHub Release

Cross-compiles [Ardour](https://github.com/Ardour/ardour) for **Windows x64** with the
**mingw-w64** toolchain directly on a **single GitHub-hosted Ubuntu runner** (no Docker, no
Windows runner), builds a **Windows Installer (`.msi`)** on Linux with
[wixl](https://wiki.gnome.org/msitools), and attaches it to a **GitHub Release**.

## Layout

```
.github/workflows/msi.yml     # one ubuntu-22.04 job: build → bundle → msi → release
.gitmodules                   # Ardour is a git submodule at ./ardour
ardour/                       # Ardour source (submodule; do not copy: keeps .git valid)
ci/
  env.sh                      # all paths + toolchain env (single place)
  00-setup.sh                 # apt: mingw-w64 (posix), autotools, meson, cmake, ccache, wixl
  10-stack.sh                 # build the ~55-library mingw dependency prefix
  11-fixups.sh                # liblo / vamp / libcurl pc fixups
  13-gtkmm-dlls.sh            # glibmm as DLL
  14-cairomm-pangomm.sh       # cairomm / pangomm
  15-lrdf.sh                  # LRDF with -DRAPTOR_STATIC
  20-cairo-dllchain.sh        # pixman/libpng/fontconfig/cairo as real DLLs
  21-pango-dll.sh             # pango/pangocairo linked against cairo DLL
  30-portaudio-wasapi.sh      # PortAudio with WASAPI
  40-ardour.sh                # apply patches, configure + build Ardour, install
  50-bundle.sh                # portable bundle (config merged into share/, dev files stripped)
  60-msi.sh                   # generate .wxs and build the .msi with wixl
  make-wxs.py                 # bundle → WiX source generator
  patches/0001-ptformat-static-libs.patch
  patches/0002-engine-dialog-utf8.patch
  patches/0003-portaudio-safe-utf8.patch
  patches/0004-portaudio-wasapi-mingw.patch
README.md
```

## One-time setup

```bash
git init
git add .
git commit -m "Ardour Windows MSI CI"

# Ardour as a submodule (pinned commit = the version you build)
git submodule add https://github.com/Ardour/ardour.git ardour
git add .gitmodules ardour
git commit -m "add Ardour submodule"

git remote add origin git@github.com:<you>/<repo>.git
git push -u origin main
```

No secrets are required: the workflow uses the automatic `GITHUB_TOKEN`
(`permissions: contents: write` to create the release).

## Running

* **Actions → ardour-win64-msi → Run workflow**
  * `version` – version used for the MSI and release tag (`v<version>`)
  * `publish` – create/update the GitHub Release (default `true`)
* Or push a tag `v9.10.0` → builds and publishes automatically.

Outputs: the `.msi` is uploaded as the `ardour-msi` artifact **and** attached to the release.

## MSI details

* Installs per-machine to `C:\Program Files\Ardour` (64-bit package, `Template: x64`).
* Adds a **Start Menu** shortcut (`Programs\Ardour\Ardour`); uninstall via *Apps & Features*.
* **No environment variables are needed**: `etc/ardour9` is merged into `share/ardour9`, which
  Ardour's config search path already contains, and all runtime DLLs sit next to
  `lib\ardour9\ardour-<version>.exe`.
* `wixl` 0.101 (Ubuntu 22.04) cannot set environment variables, which is why the layout above
  avoids them.
* Cosmetic only: without `GTK_PATH` the GTK theme engine `clearlooks` is not found and GTK
  falls back to its default theme (harmless warning in the log).

## Caches / performance

* `win-stack-w64` + `winsrc` – compiled dependency prefix (per-library `.stamp` markers let
  `10-stack.sh` skip everything already built) and source tarballs.
* `ccache` – shared object cache (`/mnt/ci/ccache`, capped at 2 GB).
* `ardour/build` – waf build tree, keyed by the **Ardour submodule commit**.

All keys also include a hash of `ci/**`, so editing the scripts invalidates the caches.
First run is roughly **2.5–4 hours** on a 4-core runner; later runs are much faster.

## Notes

* Runner is pinned to **`ubuntu-22.04`** because it ships mingw-w64 **GCC 10** (POSIX threads),
  the toolchain these older dependency versions were verified with. Newer GCC breaks several
  old libraries.
* Heavy build trees live under **`/mnt`**; the Ardour source stays in the workspace as a
  submodule so `git describe` / `git apply` keep working.
* Source modifications are plain **`.patch`** files in `ci/patches/`, applied with `git apply`
  (Ardour) or `patch -p1` (PortAudio).
* Ardour is GPL-2.0-or-later; the MSI bundles the corresponding runtime libraries.
