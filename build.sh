#!/bin/sh
# Build an Arch package (pacman -U) from the committed HEAD into dist/.
#   ./build.sh                 build dist/grab-recorder-<version>-1-any.pkg.tar.zst
#   ./build.sh --install       build and install it with sudo pacman -U
set -eu
cd "$(dirname "$0")"

if [ -n "$(git status --porcelain)" ]; then
    echo "note: uncommitted changes are not included (building HEAD $(git rev-parse --short HEAD))" >&2
fi
base=0.1
pkgver="$base.r$(git rev-list --count HEAD).g$(git rev-parse --short HEAD)"

build=dist/build
rm -rf "$build"
mkdir -p "$build"
git archive --format=tar.gz --prefix="grab-$pkgver/" -o "$build/grab-$pkgver.tar.gz" HEAD
sha=$(sha256sum "$build/grab-$pkgver.tar.gz" | cut -d' ' -f1)
sed -e "s/@PKGVER@/$pkgver/" -e "s/@SHA256@/$sha/" packaging/arch/PKGBUILD.in > "$build/PKGBUILD"
cp packaging/arch/grab-recorder.install "$build/"

# --nodeps: an arch=any package needs no build dependencies; pacman checks the
# runtime ones when installing.
(cd "$build" && PKGDEST="$(cd ../ && pwd)" makepkg --force --nodeps --clean)
pkg="dist/grab-recorder-$pkgver-1-any.pkg.tar.zst"
echo "built: $pkg"

if [ "${1:-}" = "--install" ]; then
    sudo pacman -U "$pkg"
else
    echo "install with: sudo pacman -U $pkg"
fi
