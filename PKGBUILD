# Maintainer: Bimbok <https://github.com/Bimbok>
pkgname=tide-island-extended
pkgver=1.1.3
pkgrel=1
pkgdesc="Dynamic Island widget and system companion for Wayland compositors (Hyprland & Niri)"
arch=('x86_64')
url="https://github.com/Bimbok/Tide-island-extended"
license=('GPL-3.0-or-later')
install=tide-island-extended.install

depends=(
  'cava'
  'cliphist'
  'libdrm'
  'libpulse'
  'mesa'
  'networkmanager'
  'pipewire'
  'polkit'
  'psmisc'
  'python'
  'qt6-5compat'
  'qt6-base'
  'qt6-declarative'
  'qt6-shadertools'
  'qt6-svg'
  'qt6-wayland'
  'quickshell'
  'systemd-libs'
  'wayland'
  'wayland-protocols'
  'wireplumber'
  'wl-clipboard'
)

optdepends=(
  'bluez: Bluetooth device management'
  'bluez-utils: Bluetooth command-line pairing support'
  'brightnessctl: Display brightness controls'
  'grim: Screen capture backend'
  'hyprland: Wayland compositor support'
  'hyprlock: Hyprland session lock integration'
  'hyprshot: Hyprland screenshot utility'
  'niri: Scrollable-tiling Wayland compositor support'
  'power-profiles-daemon: Power profile switching'
  'slurp: Screen area selector for screenshots'
  'upower: Battery monitoring support'
  'zenity: GUI file and folder picker dialog fallback'
)

makedepends=(
  'cmake'
  'ninja'
  'pkgconf'
  'qt6-base'
  'qt6-declarative'
  'qt6-5compat'
  'systemd-libs'
)

provides=('tide-island')
conflicts=('tide-island' 'tide-island-git' 'tide-island-bin' 'tide-island-extended-git')
options=(!debug)

if [[ -f "$startdir/CMakeLists.txt" ]]; then
  source=()
  sha256sums=()
else
  source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v$pkgver.tar.gz")
  sha256sums=('SKIP')
fi

build() {
  local src_root
  if [[ -f "$startdir/CMakeLists.txt" ]]; then
    src_root="$startdir"
  else
    src_root="$srcdir/Tide-island-extended-$pkgver"
  fi

  cmake -B "$srcdir/build" -S "$src_root" \
    -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DTIDE_ISLAND_WITH_NIRI=ON

  cmake --build "$srcdir/build"
}

check() {
  ctest --test-dir "$srcdir/build" --output-on-failure
}

package() {
  local src_root
  if [[ -f "$startdir/CMakeLists.txt" ]]; then
    src_root="$startdir"
  else
    src_root="$srcdir/Tide-island-extended-$pkgver"
  fi

  DESTDIR="$pkgdir" cmake --install "$srcdir/build"
  install -Dm644 "$src_root/LICENSE" "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}
