#!/bin/bash
# Builds mcpelauncher-client (with the touch fixes) in a Fedora 43 podman container.
# Needs only podman on the host. Installs to ~/.local/opt/mcpelauncher-touchfix
set -e
SRC=$(cd "$(dirname "$0")/.." && pwd)
BUILD=${BUILD:-$HOME/.cache/mcpelauncher-touchfix-build}
OUT=$HOME/.local/opt/mcpelauncher-touchfix
mkdir -p "$BUILD" "$OUT"
# Paths are mounted at the same location as on the host so paths baked into the build stay valid
podman run --rm \
  -v "$SRC:$SRC:Z" -v "$BUILD:$BUILD:Z" -v "$OUT:$OUT:Z" \
  -v mcpelauncher-dnf-cache:/var/cache/libdnf5 \
  registry.fedoraproject.org/fedora:43 bash -ec "
dnf -y --setopt=keepcache=1 install cmake ninja-build clang lld git perl \
  openssl-devel libpng-devel libevdev-devel systemd-devel zlib-ng-compat-devel \
  libX11-devel libXext-devel libXi-devel libXcursor-devel libXrandr-devel libXfixes-devel libXScrnSaver-devel libXtst-devel \
  mesa-libEGL-devel mesa-libGL-devel mesa-libGLES-devel \
  wayland-devel wayland-protocols-devel libxkbcommon-devel libdecor-devel \
  pulseaudio-libs-devel pipewire-devel alsa-lib-devel dbus-devel ibus-devel libdrm-devel mesa-libgbm-devel >/dev/null
cmake -S $SRC -B $BUILD/out -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DBUILD_UI=OFF -DBUILD_WEBVIEW=OFF -DENABLE_DEV_PATHS=OFF \
  -DCMAKE_INSTALL_PREFIX=$OUT
cmake --build $BUILD/out -j\$(nproc)
cmake --install $BUILD/out
"
