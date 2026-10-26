#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
readonly PREFIX="/usr"
readonly STATE_DIR="/var/lib/tide-island"
readonly INSTALL_MANIFEST="$STATE_DIR/install-manifest.txt"
readonly QUICKSHELL_BUILD_INFO="$STATE_DIR/quickshell-source-build.txt"
readonly QUICKSHELL_INSTALL_MANIFEST="$STATE_DIR/quickshell-install-manifest.txt"
readonly INSTALLED_BUILD_DEPS="$STATE_DIR/installed-build-deps.txt"
readonly INSTALLED_RUNTIME_DEPS="$STATE_DIR/installed-runtime-deps.txt"
readonly QUICKSHELL_REPOSITORY="https://git.outfoxxed.me/quickshell/quickshell.git"
readonly QUICKSHELL_MIRROR="https://github.com/quickshell-mirror/quickshell.git"
readonly QUICKSHELL_VERSION="v0.3.0"
readonly QUICKSHELL_COMMIT="59e9c47b0eb48a9e4bcf9631fa062ee939bd2e83"

INSTALL_DEPENDENCIES=1
CHECK_DEPS=0
CLEAN_BUILD_DEPS=0
KEEP_BUILD_DEPS=0
REMOVE_DEPS=0
QUICKSHELL_MODE="auto"
QUICKSHELL_SKIP_REQUESTED=0
QUICKSHELL_FORCE_REQUESTED=0
ENABLE_SERVICE=1
UNINSTALL=0
DRY_RUN=0
ASSUME_YES=0
FORCE=0
SERVICE_WAS_ACTIVE=0

restore_service_after_error() {
  local status=$?
  trap - ERR
  if ((SERVICE_WAS_ACTIVE)) && command -v systemctl >/dev/null 2>&1; then
    systemctl --user start tide-island.service >/dev/null 2>&1 || true
  fi
  exit "$status"
}

trap restore_service_after_error ERR

log() {
  printf '\n==> %s\n' "$*"
}

warn() {
  printf 'Warning: %s\n' "$*" >&2
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

print_command() {
  printf '  +'
  printf ' %q' "$@"
  printf '\n'
}

run() {
  if ((DRY_RUN)); then
    print_command "$@"
    return 0
  fi
  "$@"
}

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options]

Build, install, check dependencies, and manage Tide Island from source to /usr.
Run this script as a regular desktop user; it requests sudo when needed.

Options:
  --check-deps            Inspect system for required and optional feature tools.
  --skip-deps             Do not install distribution packages.
  --skip-quickshell       Require an existing /usr/bin/quickshell.
  --force-build-quickshell
                          Rebuild the pinned Quickshell version from source.
  --clean-build-deps      Automatically uninstall build-only dependencies post-build.
  --keep-build-deps       Keep build-only dependencies without prompting.
  --remove-deps           With --uninstall: automatically remove installed dependencies.
  --no-service            Do not enable or start the systemd user service.
  --uninstall             Remove the source-installed Tide Island files and clean up.
  --dry-run               Print actions without changing the system.
  --force                 Allow Arch/source-package conflicts and overwrite.
  -y, --yes               Do not ask for confirmation.
  -h, --help              Show this help.

Supported dependency installers: pacman, apt, dnf, and zypper.
For other Linux distributions, install dependencies yourself and use --skip-deps.
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --check-deps)
        CHECK_DEPS=1
        ;;
      --clean-build-deps)
        CLEAN_BUILD_DEPS=1
        ;;
      --keep-build-deps)
        KEEP_BUILD_DEPS=1
        ;;
      --remove-deps)
        REMOVE_DEPS=1
        ;;
      --skip-deps)
        INSTALL_DEPENDENCIES=0
        ;;
      --skip-quickshell)
        QUICKSHELL_MODE="skip"
        QUICKSHELL_SKIP_REQUESTED=1
        ;;
      --force-build-quickshell)
        QUICKSHELL_MODE="force"
        QUICKSHELL_FORCE_REQUESTED=1
        ;;
      --no-service)
        ENABLE_SERVICE=0
        ;;
      --uninstall)
        UNINSTALL=1
        ;;
      --dry-run)
        DRY_RUN=1
        ;;
      --force)
        FORCE=1
        ;;
      -y|--yes)
        ASSUME_YES=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown option: $1"
        ;;
    esac
    shift
  done

  if ((QUICKSHELL_SKIP_REQUESTED && QUICKSHELL_FORCE_REQUESTED)); then
    die "--skip-quickshell and --force-build-quickshell cannot be used together"
  fi

}

repo_root() {
  local script_dir
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
  [[ -f "$script_dir/CMakeLists.txt" ]] || die "CMakeLists.txt was not found next to $SCRIPT_NAME"
  printf '%s\n' "$script_dir"
}

load_os_release() {
  local os_release="${TIDE_INSTALLER_OS_RELEASE:-/etc/os-release}"
  [[ -r "$os_release" ]] || die "cannot read $os_release"

  ID=""
  ID_LIKE=""
  VERSION_ID=""
  # /etc/os-release is the standard shell-compatible distribution metadata file.
  # shellcheck disable=SC1090
  source "$os_release"
  ID="${ID,,}"
  ID_LIKE=" ${ID_LIKE,,} "

  case "$ID" in
    debian|ubuntu|linuxmint|pop|elementary|zorin)
      DISTRO_FAMILY="apt"
      ;;
    fedora|rhel|centos|rocky|almalinux|ultramarine|nobara)
      DISTRO_FAMILY="dnf"
      ;;
    opensuse*|sles)
      DISTRO_FAMILY="zypper"
      ;;
    arch|endeavouros|manjaro|cachyos|garuda)
      DISTRO_FAMILY="arch"
      ;;
    *)
      if [[ "$ID_LIKE" == *" debian "* || "$ID_LIKE" == *" ubuntu "* ]]; then
        DISTRO_FAMILY="apt"
      elif [[ "$ID_LIKE" == *" fedora "* || "$ID_LIKE" == *" rhel "* ]]; then
        DISTRO_FAMILY="dnf"
      elif [[ "$ID_LIKE" == *" suse "* ]]; then
        DISTRO_FAMILY="zypper"
      elif [[ "$ID_LIKE" == *" arch "* ]]; then
        DISTRO_FAMILY="arch"
      else
        DISTRO_FAMILY="unknown"
      fi
      ;;
  esac
}

confirm() {
  ((ASSUME_YES || DRY_RUN)) && return 0
  [[ -t 0 ]] || die "confirmation requires a terminal; rerun with --yes"
  printf 'Install Tide Island to /usr on %s %s? [y/N] ' "$ID" "${VERSION_ID:-}"
  local answer
  read -r answer
  [[ "$answer" == "y" || "$answer" == "Y" ]] || die "installation canceled"
}

require_regular_user() {
  if ((EUID == 0 && !DRY_RUN)); then
    die "run this installer as your regular desktop user, not as root"
  fi
  if ((!DRY_RUN)); then
    command -v sudo >/dev/null 2>&1 || die "sudo is required for the fixed /usr installation"
  fi
}

sudo_init() {
  ((DRY_RUN)) && return 0
  sudo -v
}

package_install_conflict() {
  ((FORCE || DRY_RUN)) && return 0

  if command -v pacman >/dev/null 2>&1 && pacman -Q tide-island >/dev/null 2>&1; then
    die "the pacman/AUR tide-island package is installed; remove it first (e.g. sudo pacman -R tide-island) or use --force"
  fi
  if command -v dpkg-query >/dev/null 2>&1 \
      && dpkg-query -W -f='${Status}' tide-island 2>/dev/null | grep -q 'install ok installed'; then
    die "a dpkg-managed tide-island package is installed; remove it first (or use --force)"
  fi
  if command -v rpm >/dev/null 2>&1 && rpm -q tide-island >/dev/null 2>&1; then
    die "an RPM-managed tide-island package is installed; remove it first (or use --force)"
  fi
}

is_package_installed() {
  local package="$1"
  case "$DISTRO_FAMILY" in
    arch)
      pacman -Q "$package" >/dev/null 2>&1
      ;;
    apt)
      dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'
      ;;
    dnf|zypper)
      rpm -q "$package" >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

is_package_available() {
  local package="$1"
  case "$DISTRO_FAMILY" in
    arch)
      pacman -Si "$package" >/dev/null 2>&1
      ;;
    apt)
      apt-cache show "$package" >/dev/null 2>&1
      ;;
    dnf)
      rpm -q "$package" >/dev/null 2>&1 || dnf -q list "$package" >/dev/null 2>&1
      ;;
    zypper)
      rpm -q "$package" >/dev/null 2>&1 \
        || zypper --xmlout --non-interactive search --match-exact --type package "$package" 2>/dev/null \
          | grep -Fq "name=\"$package\""
      ;;
    *)
      return 0
      ;;
  esac
}

record_installed_packages() {
  local type="$1"
  shift
  local packages=("$@")
  ((${#packages[@]} > 0)) || return 0
  ((DRY_RUN)) && return 0

  local target_file
  if [[ "$type" == "build" ]]; then
    target_file="$INSTALLED_BUILD_DEPS"
  else
    target_file="$INSTALLED_RUNTIME_DEPS"
  fi

  local existing=()
  if [[ -r "$target_file" ]]; then
    mapfile -t existing < "$target_file"
  fi

  local to_write=()
  local pkg
  for pkg in "${existing[@]}" "${packages[@]}"; do
    [[ -n "$pkg" ]] || continue
    local dup=0
    for w in "${to_write[@]}"; do
      if [[ "$w" == "$pkg" ]]; then
        dup=1
        break
      fi
    done
    ((dup)) || to_write+=("$pkg")
  done

  local tmp_file
  tmp_file="$(mktemp)"
  printf '%s\n' "${to_write[@]}" > "$tmp_file"
  sudo install -d -m 0755 "$STATE_DIR"
  sudo install -m 0644 "$tmp_file" "$target_file"
  rm -f "$tmp_file"
}

remove_distribution_packages() {
  local pkgs=("$@")
  ((${#pkgs[@]} > 0)) || return 0

  case "$DISTRO_FAMILY" in
    arch)
      if ((DRY_RUN)); then
        print_command sudo pacman -R --noconfirm "${pkgs[@]}"
      else
        sudo pacman -R --noconfirm "${pkgs[@]}" || warn "Failed to remove some packages: ${pkgs[*]}"
      fi
      ;;
    apt)
      if ((DRY_RUN)); then
        print_command sudo env DEBIAN_FRONTEND=noninteractive apt-get remove -y "${pkgs[@]}"
      else
        sudo env DEBIAN_FRONTEND=noninteractive apt-get remove -y "${pkgs[@]}" || warn "Failed to remove some packages: ${pkgs[*]}"
      fi
      ;;
    dnf)
      if ((DRY_RUN)); then
        print_command sudo dnf remove -y "${pkgs[@]}"
      else
        sudo dnf remove -y "${pkgs[@]}" || warn "Failed to remove some packages: ${pkgs[*]}"
      fi
      ;;
    zypper)
      if ((DRY_RUN)); then
        print_command sudo zypper --non-interactive remove "${pkgs[@]}"
      else
        sudo zypper --non-interactive remove "${pkgs[@]}" || warn "Failed to remove some packages: ${pkgs[*]}"
      fi
      ;;
    *)
      warn "Unknown distro family '$DISTRO_FAMILY'; please remove packages manually: ${pkgs[*]}"
      ;;
  esac
}

clean_build_dependencies() {
  ((DRY_RUN)) && return 0
  [[ -r "$INSTALLED_BUILD_DEPS" ]] || return 0
  local build_pkgs=()
  mapfile -t build_pkgs < "$INSTALLED_BUILD_DEPS"
  ((${#build_pkgs[@]} > 0)) || return 0

  log "Build-time dependencies were installed purely for compilation: ${build_pkgs[*]}"
  local remove=0
  if ((CLEAN_BUILD_DEPS)); then
    remove=1
  elif ((KEEP_BUILD_DEPS)); then
    remove=0
  elif ((ASSUME_YES)); then
    remove=1
  elif [[ -t 0 ]]; then
    printf 'Remove build-only packages that are no longer needed? [y/N] '
    local answer
    read -r answer
    [[ "$answer" == "y" || "$answer" == "Y" ]] && remove=1
  fi

  if ((remove)); then
    log "Uninstalling build-only dependencies"
    remove_distribution_packages "${build_pkgs[@]}"
    run sudo rm -f -- "$INSTALLED_BUILD_DEPS"
  else
    log "Keeping build-only dependencies (tracked in $INSTALLED_BUILD_DEPS for future cleanup)"
  fi
}

pacman_install_dependencies() {
  local build_packages=(
    git base-devel cmake ninja pkgconf
    vulkan-headers jemalloc cli11 spirv-tools
  )
  local runtime_packages=(
    qt6-base qt6-declarative qt6-5compat qt6-wayland
    qt6-shadertools qt6-svg
    libdrm wayland wayland-protocols mesa
    wireplumber pipewire libpulse
    brightnessctl upower bluez bluez-utils
    polkit zenity networkmanager wl-clipboard cliphist power-profiles-daemon
    python psmisc cava
  )
  local packages=("${build_packages[@]}" "${runtime_packages[@]}")

  log "Installing Arch Linux build and runtime dependencies"
  if ((DRY_RUN)); then
    run sudo pacman -S --needed --noconfirm "${packages[@]}"
    return
  fi

  local available=()
  local missing=()
  local new_build=()
  local new_runtime=()
  local package

  for package in "${build_packages[@]}"; do
    if is_package_available "$package"; then
      available+=("$package")
      if ! is_package_installed "$package"; then
        new_build+=("$package")
      fi
    else
      missing+=("$package")
    fi
  done

  for package in "${runtime_packages[@]}"; do
    if is_package_available "$package"; then
      available+=("$package")
      if ! is_package_installed "$package"; then
        new_runtime+=("$package")
      fi
    else
      missing+=("$package")
    fi
  done

  if ((${#available[@]} > 0)); then
    sudo pacman -S --needed --noconfirm "${available[@]}"
    ((${#new_build[@]} > 0)) && record_installed_packages "build" "${new_build[@]}"
    ((${#new_runtime[@]} > 0)) && record_installed_packages "runtime" "${new_runtime[@]}"
  fi

  ((${#missing[@]} == 0)) \
    || warn "packages unavailable in enabled pacman repositories: ${missing[*]}"
}

apt_install_dependencies() {
  local build_packages=(
    git build-essential cmake ninja-build pkg-config
    qt6-base-dev qt6-base-private-dev
    qt6-declarative-dev qt6-declarative-private-dev
    qt6-wayland qt6-wayland-dev qt6-wayland-private-dev
    qt6-shadertools-dev libqt6svg6 libqt6svg6-dev
    libudev-dev libdrm-dev libwayland-dev wayland-protocols
    libgbm-dev vulkan-headers libjemalloc-dev libcli11-dev spirv-tools
  )
  local runtime_packages=(
    qml6-module-qt5compat-graphicaleffects
    qml6-module-qtquick-controls qml6-module-qtquick-dialogs
    qt6-wayland libqt6svg6
    wireplumber pipewire pulseaudio-utils brightnessctl dbus upower bluez
    policykit-1 zenity network-manager wl-clipboard cliphist power-profiles-daemon
    python3 psmisc cava
  )
  local packages=("${build_packages[@]}" "${runtime_packages[@]}")

  log "Installing Debian/Ubuntu build and runtime dependencies"
  run sudo apt-get update
  if ((DRY_RUN)); then
    run sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
    return
  fi

  local available=()
  local missing=()
  local new_build=()
  local new_runtime=()
  local package

  for package in "${build_packages[@]}"; do
    if is_package_available "$package"; then
      available+=("$package")
      if ! is_package_installed "$package"; then
        new_build+=("$package")
      fi
    else
      missing+=("$package")
    fi
  done

  for package in "${runtime_packages[@]}"; do
    if is_package_available "$package"; then
      available+=("$package")
      if ! is_package_installed "$package"; then
        new_runtime+=("$package")
      fi
    else
      missing+=("$package")
    fi
  done

  if ((${#available[@]} > 0)); then
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${available[@]}"
    ((${#new_build[@]} > 0)) && record_installed_packages "build" "${new_build[@]}"
    ((${#new_runtime[@]} > 0)) && record_installed_packages "runtime" "${new_runtime[@]}"
  fi

  ((${#missing[@]} == 0)) \
    || warn "packages unavailable in enabled apt repositories: ${missing[*]}"
}

dnf_install_dependencies() {
  local build_packages=(
    git gcc-c++ cmake ninja-build pkgconf-pkg-config
    qt6-qtbase-devel qt6-qtbase-private-devel
    qt6-qtdeclarative-devel qt6-qtwayland-devel
    qt6-qtshadertools-devel qt6-qtsvg-devel
    systemd-devel libdrm-devel wayland-devel wayland-protocols-devel
    mesa-libgbm-devel vulkan-headers jemalloc-devel cli11-devel spirv-tools-devel
  )
  local runtime_packages=(
    qt6-qt5compat
    wireplumber pipewire pulseaudio-utils brightnessctl dbus-daemon upower bluez bluez-tools
    polkit zenity NetworkManager wl-clipboard cliphist power-profiles-daemon
    python3 psmisc cava
  )
  local packages=("${build_packages[@]}" "${runtime_packages[@]}")

  log "Installing Fedora/RHEL build and runtime dependencies"
  if ((DRY_RUN)); then
    run sudo dnf install -y "${packages[@]}"
    return
  fi

  local available=()
  local missing=()
  local new_build=()
  local new_runtime=()
  local package

  for package in "${build_packages[@]}"; do
    if is_package_available "$package"; then
      available+=("$package")
      if ! is_package_installed "$package"; then
        new_build+=("$package")
      fi
    else
      missing+=("$package")
    fi
  done

  for package in "${runtime_packages[@]}"; do
    if is_package_available "$package"; then
      available+=("$package")
      if ! is_package_installed "$package"; then
        new_runtime+=("$package")
      fi
    else
      missing+=("$package")
    fi
  done

  if ((${#available[@]} > 0)); then
    sudo dnf install -y "${available[@]}"
    ((${#new_build[@]} > 0)) && record_installed_packages "build" "${new_build[@]}"
    ((${#new_runtime[@]} > 0)) && record_installed_packages "runtime" "${new_runtime[@]}"
  fi

  ((${#missing[@]} == 0)) \
    || warn "packages unavailable in enabled dnf repositories: ${missing[*]}"
}

zypper_install_dependencies() {
  local build_packages=(
    git gcc-c++ cmake ninja pkg-config
    qt6-base-devel qt6-declarative-devel qt6-wayland-devel
    qt6-shadertools-devel qt6-svg-devel
    systemd-devel libdrm-devel wayland-devel wayland-protocols-devel
    Mesa-libgbm-devel vulkan-headers libjemalloc-devel cli11-devel spirv-tools-devel
  )
  local runtime_packages=(
    qt6-qt5compat-imports
    wireplumber pipewire pulseaudio-utils brightnessctl dbus-1 upower bluez
    polkit zenity NetworkManager wl-clipboard cliphist power-profiles-daemon
    python3 psmisc cava
  )
  local packages=("${build_packages[@]}" "${runtime_packages[@]}")

  log "Installing openSUSE build and runtime dependencies"
  if ((DRY_RUN)); then
    run sudo zypper --non-interactive install --no-recommends "${packages[@]}"
    return
  fi

  local available=()
  local missing=()
  local new_build=()
  local new_runtime=()
  local package

  for package in "${build_packages[@]}"; do
    if is_package_available "$package"; then
      available+=("$package")
      if ! is_package_installed "$package"; then
        new_build+=("$package")
      fi
    else
      missing+=("$package")
    fi
  done

  for package in "${runtime_packages[@]}"; do
    if is_package_available "$package"; then
      available+=("$package")
      if ! is_package_installed "$package"; then
        new_runtime+=("$package")
      fi
    else
      missing+=("$package")
    fi
  done

  if ((${#available[@]} > 0)); then
    sudo zypper --non-interactive install --no-recommends "${available[@]}"
    ((${#new_build[@]} > 0)) && record_installed_packages "build" "${new_build[@]}"
    ((${#new_runtime[@]} > 0)) && record_installed_packages "runtime" "${new_runtime[@]}"
  fi

  ((${#missing[@]} == 0)) \
    || warn "packages unavailable in enabled zypper repositories: ${missing[*]}"
}

install_dependencies() {
  ((INSTALL_DEPENDENCIES)) || {
    log "Skipping distribution dependency installation"
    return
  }

  case "$DISTRO_FAMILY" in
    apt)
      apt_install_dependencies
      ;;
    dnf)
      dnf_install_dependencies
      ;;
    zypper)
      zypper_install_dependencies
      ;;
    arch)
      pacman_install_dependencies
      ;;
    *)
      die "unsupported distribution '$ID'; install dependencies manually and rerun with --skip-deps"
      ;;
  esac
}

qt_version() {
  local version=""
  if [[ -n "${TIDE_INSTALLER_QT_VERSION:-}" ]]; then
    printf '%s\n' "$TIDE_INSTALLER_QT_VERSION"
    return
  fi
  if command -v pkg-config >/dev/null 2>&1; then
    version="$(pkg-config --modversion Qt6Core 2>/dev/null || true)"
  fi
  if [[ -z "$version" ]] && command -v qtpaths6 >/dev/null 2>&1; then
    version="$(qtpaths6 --qt-version 2>/dev/null || true)"
  fi
  if [[ -z "$version" && -x /usr/lib/qt6/bin/qtpaths6 ]]; then
    version="$(/usr/lib/qt6/bin/qtpaths6 --qt-version 2>/dev/null || true)"
  fi
  printf '%s\n' "$version"
}

version_at_least() {
  local current="$1"
  local minimum="$2"
  [[ "$(printf '%s\n%s\n' "$minimum" "$current" | sort -V | head -n1)" == "$minimum" ]]
}

verify_build_tools() {
  local missing=()
  local command
  for command in cmake ninja git pkg-config; do
    command -v "$command" >/dev/null 2>&1 || missing+=("$command")
  done
  ((${#missing[@]} == 0)) || die "missing build tools: ${missing[*]}"

  local version
  version="$(qt_version)"
  [[ -n "$version" ]] || die "Qt 6 development files were not detected"
  version_at_least "$version" "6.6.0" \
    || die "Qt $version is too old; Tide Island's pinned Quickshell requires Qt 6.6 or newer"
  log "Detected Qt $version"
}

installer_cache_dir() {
  printf '%s/tide-island-installer\n' "${XDG_CACHE_HOME:-$HOME/.cache}"
}

prepare_quickshell_source() {
  local source_dir="$1"
  if [[ -d "$source_dir/.git" ]]; then
    if ! run git -C "$source_dir" fetch --depth 1 origin "$QUICKSHELL_COMMIT"; then
      warn "cached Quickshell remote failed; switching to the official mirror"
      run git -C "$source_dir" remote set-url origin "$QUICKSHELL_MIRROR"
      run git -C "$source_dir" fetch --depth 1 origin "$QUICKSHELL_COMMIT"
    fi
  elif [[ -e "$source_dir" ]]; then
    die "$source_dir exists but is not a Quickshell git checkout"
  else
    mkdir -p "$(dirname "$source_dir")"
    run git init -q "$source_dir"
    run git -C "$source_dir" remote add origin "$QUICKSHELL_REPOSITORY"
    if ! run git -C "$source_dir" fetch --depth 1 origin "$QUICKSHELL_COMMIT"; then
      warn "primary Quickshell repository failed; trying the official mirror"
      run git -C "$source_dir" remote set-url origin "$QUICKSHELL_MIRROR"
      run git -C "$source_dir" fetch --depth 1 origin "$QUICKSHELL_COMMIT"
    fi
  fi
  run git -C "$source_dir" checkout --detach "$QUICKSHELL_COMMIT"

  if ((!DRY_RUN)); then
    local actual_commit
    actual_commit="$(git -C "$source_dir" rev-parse HEAD)"
    [[ "$actual_commit" == "$QUICKSHELL_COMMIT" ]] \
      || die "Quickshell checkout verification failed"
  fi
}

build_quickshell() {
  if [[ "$QUICKSHELL_MODE" == "skip" ]]; then
    [[ -x /usr/bin/quickshell || $DRY_RUN -eq 1 ]] \
      || die "--skip-quickshell requires /usr/bin/quickshell"
    log "Using the existing /usr/bin/quickshell"
    return
  fi

  if [[ -x /usr/bin/quickshell && "$QUICKSHELL_MODE" != "force" ]]; then
    local current_qt recorded_qt
    current_qt="$(qt_version)"
    recorded_qt=""
    if [[ -r "$QUICKSHELL_BUILD_INFO" ]]; then
      recorded_qt="$(sed -n 's/^qt=//p' "$QUICKSHELL_BUILD_INFO" | head -n1)"
    fi
    if [[ -z "$recorded_qt" || "$recorded_qt" == "$current_qt" ]]; then
      log "Using the existing /usr/bin/quickshell"
      /usr/bin/quickshell --version 2>/dev/null || true
      return
    fi
    warn "Qt changed from $recorded_qt to $current_qt; rebuilding the source-installed Quickshell"
  fi

  local cache_dir source_dir build_dir
  cache_dir="$(installer_cache_dir)"
  source_dir="$cache_dir/quickshell-$QUICKSHELL_VERSION"
  build_dir="$source_dir/build-tide-island"

  log "Preparing pinned Quickshell $QUICKSHELL_VERSION ($QUICKSHELL_COMMIT)"
  if ((DRY_RUN)); then
    print_command git clone "$QUICKSHELL_REPOSITORY" "$source_dir"
  else
    prepare_quickshell_source "$source_dir"
  fi

  log "Building Quickshell"
  run cmake -GNinja -S "$source_dir" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DDISTRIBUTOR="Tide Island source installer" \
    -DCRASH_HANDLER=OFF \
    -DX11=OFF \
    -DSERVICE_PIPEWIRE=OFF \
    -DSERVICE_PAM=OFF \
    -DSERVICE_POLKIT=OFF
  run cmake --build "$build_dir" --parallel
  run sudo cmake --install "$build_dir"
  if ((!DRY_RUN)); then
    local build_info
    build_info="$(mktemp)"
    printf 'version=%s\ncommit=%s\nqt=%s\n' \
      "$QUICKSHELL_VERSION" "$QUICKSHELL_COMMIT" "$(qt_version)" > "$build_info"
    sudo install -d -m 0755 "$STATE_DIR"
    sudo install -m 0644 "$build_info" "$QUICKSHELL_BUILD_INFO"
    rm -f "$build_info"
    if [[ -f "$build_dir/install_manifest.txt" ]]; then
      sudo install -m 0644 "$build_dir/install_manifest.txt" "$QUICKSHELL_INSTALL_MANIFEST"
    fi
  else
    print_command sudo install -m 0644 quickshell-source-build.txt "$QUICKSHELL_BUILD_INFO"
  fi

  [[ -x /usr/bin/quickshell || $DRY_RUN -eq 1 ]] \
    || die "Quickshell installation did not create /usr/bin/quickshell"
}

remove_manifest_files() {
  [[ -f "$INSTALL_MANIFEST" ]] || return 0

  log "Removing files from the previous source installation"
  local paths=()
  mapfile -t paths < "$INSTALL_MANIFEST"
  local index path
  for ((index=${#paths[@]} - 1; index >= 0; --index)); do
    path="${paths[index]}"
    [[ "$path" == /usr/* ]] || die "unsafe path in $INSTALL_MANIFEST: $path"
    run sudo rm -f -- "$path"
  done
}

remove_obsolete_manifest_files() {
  local previous_manifest="$1"
  local next_manifest="$2"
  [[ -f "$previous_manifest" ]] || return 0

  log "Removing obsolete files from the previous Tide Island version"
  local path
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    [[ "$path" == /usr/* ]] || die "unsafe path in previous install manifest: $path"
    grep -Fqx -- "$path" "$next_manifest" || run sudo rm -f -- "$path"
  done < "$previous_manifest"
}

build_tide_island() {
  local root cache_dir build_dir
  root="$(repo_root)"
  cache_dir="$(installer_cache_dir)"
  build_dir="$root/build-release-installer"
  mkdir -p "$cache_dir"

  log "Configuring Tide Island"
  run cmake -U CMAKE_INSTALL_LIBDIR -GNinja -S "$root" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX"
  run cmake --build "$build_dir" --parallel
  run ctest --test-dir "$build_dir" --output-on-failure

  if systemctl --user is-active --quiet tide-island.service 2>/dev/null; then
    SERVICE_WAS_ACTIVE=1
    run systemctl --user stop tide-island.service
  fi

  local previous_manifest="$cache_dir/previous-install-manifest.txt"
  if [[ -r "$INSTALL_MANIFEST" ]]; then
    cp "$INSTALL_MANIFEST" "$previous_manifest"
  else
    : > "$previous_manifest"
  fi

  log "Installing Tide Island to /usr"
  run sudo cmake --install "$build_dir"
  if ((!DRY_RUN)); then
    remove_obsolete_manifest_files "$previous_manifest" "$build_dir/install_manifest.txt"
  fi
  run sudo install -d -m 0755 "$STATE_DIR"
  run sudo install -m 0644 "$build_dir/install_manifest.txt" "$INSTALL_MANIFEST"
  if command -v systemd-tmpfiles >/dev/null 2>&1; then
    run sudo systemd-tmpfiles --create /usr/lib/tmpfiles.d/tide-island-battery.conf 2>/dev/null || true
  fi
}

configure_service() {
  if ((ENABLE_SERVICE == 0)); then
    log "Skipping systemd user service setup"
    if ((SERVICE_WAS_ACTIVE)); then
      run systemctl --user start tide-island.service
      SERVICE_WAS_ACTIVE=0
    fi
    return
  fi

  if ! command -v systemctl >/dev/null 2>&1; then
    warn "systemctl was not found; start Tide Island manually with /usr/bin/tide-island"
    return
  fi
  if ! systemctl --user show-environment >/dev/null 2>&1; then
    warn "a systemd user session is not available; start Tide Island manually with /usr/bin/tide-island"
    return
  fi

  log "Enabling and starting the Tide Island user service"
  run systemctl --user daemon-reload
  run systemctl --user enable --now tide-island.service
  SERVICE_WAS_ACTIVE=0
}

check_tool() {
  local cmd="$1"
  local pkg="$2"
  local desc="$3"
  local mandatory="${4:-0}"

  if command -v "$cmd" >/dev/null 2>&1; then
    printf '  [✓] %-22s - %s\n' "$cmd" "$desc"
  else
    if ((mandatory)); then
      printf '  [✗] %-22s - %s (MISSING - Required! Install: %s)\n' "$cmd" "$desc" "$pkg"
    else
      printf '  [ ] %-22s - %s (Optional, package: %s)\n' "$cmd" "$desc" "$pkg"
    fi
  fi
}

check_feature() {
  local cmd="$1"
  local pkg="$2"
  local desc="$3"

  if command -v "$cmd" >/dev/null 2>&1; then
    printf '  [✓] %-22s - %s\n' "$cmd" "$desc"
  else
    printf '  [ ] %-22s - %s (Optional, package: %s)\n' "$cmd" "$desc" "$pkg"
    missing_optional+=("$pkg")
  fi
}

check_night_light() {
  if command -v hyprsunset >/dev/null 2>&1; then
    printf '  [✓] %-22s - %s\n' "hyprsunset" "Night Light temperature filter (Hyprland)"
  elif command -v gammastep >/dev/null 2>&1; then
    printf '  [✓] %-22s - %s\n' "gammastep" "Night Light temperature filter (Wayland)"
  else
    local pkg="gammastep"
    [[ "$DISTRO_FAMILY" == "arch" ]] && pkg="hyprsunset (or gammastep)"
    printf '  [ ] %-22s - %s (Optional, package: %s)\n' "hyprsunset/gammastep" "Night Light temperature filter" "$pkg"
    if [[ "$DISTRO_FAMILY" == "arch" ]]; then
      missing_optional+=("hyprsunset")
    else
      missing_optional+=("gammastep")
    fi
  fi
}

check_wallpaper_backend() {
  local found=""
  local b
  for b in awww swww hyprpaper mpvpaper; do
    if command -v "$b" >/dev/null 2>&1; then
      found="$b"
      break
    fi
  done
  if [[ -n "$found" ]]; then
    printf '  [✓] %-22s - %s (%s)\n' "wallpaper engine" "Wallpaper transition daemon" "$found"
  else
    local pkg="swww"
    [[ "$DISTRO_FAMILY" == "arch" ]] && pkg="awww"
    printf '  [ ] %-22s - %s (Optional, package: %s)\n' "wallpaper engine" "Wallpaper transition daemon" "$pkg"
    missing_optional+=("$pkg")
  fi
}

check_power_profile() {
  if command -v powerprofilesctl >/dev/null 2>&1; then
    printf '  [✓] %-22s - %s\n' "powerprofilesctl" "Power profile management & battery conservation"
  elif command -v tlp >/dev/null 2>&1; then
    printf '  [✓] %-22s - %s\n' "tlp" "Power profile management & battery conservation"
  else
    printf '  [ ] %-22s - %s (Optional, package: power-profiles-daemon)\n' "powerprofilesctl" "Power profile management"
    missing_optional+=("power-profiles-daemon")
  fi
}

check_dependencies() {
  log "Tide Island Dependency Status"

  local missing_optional=()

  printf '\nCore Runtime Dependencies (Mandatory):\n'
  check_tool "quickshell" "quickshell" "Wayland desktop shell runtime host" 1
  check_tool "dbus-monitor" "dbus" "D-Bus lock & idle event monitoring" 1
  check_tool "wpctl" "wireplumber" "PipeWire session manager & audio device control" 1
  check_tool "pactl" "libpulse / pulseaudio-utils" "PulseAudio / PipeWire event subscriber & volume mixer" 1
  check_tool "wl-copy" "wl-clipboard" "Wayland clipboard copy command" 1
  check_tool "wl-paste" "wl-clipboard" "Wayland clipboard paste command" 1
  check_tool "cliphist" "cliphist" "Clipboard history manager daemon" 1
  check_tool "python3" "python3" "Wallpaper color & palette extraction script runner" 1

  printf '\nFeature-Specific Dependencies (Optional):\n'
  check_feature "cava" "cava" "8-bar audio spectrum visualizer (Player & Lockscreen)"
  check_feature "fuser" "psmisc" "Camera & video device privacy tracking (/dev/video*)"
  check_feature "gpu-screen-recorder" "gpu-screen-recorder" "Hardware accelerated screen & replay recorder"
  check_night_light
  check_wallpaper_backend
  check_feature "brightnessctl" "brightnessctl" "Backlight brightness adjustment"
  check_power_profile
  check_feature "bluetoothctl" "bluez" "Bluetooth device pairing & control"
  check_feature "nmcli" "networkmanager" "Wi-Fi scanning & connection manager"
  check_feature "pkexec" "polkit" "Privileged elevation (faillock reset, battery limit)"
  check_feature "zenity" "zenity" "GUI dialog fallback prompt"

  if ((${#missing_optional[@]} > 0)); then
    printf '\nOptional packages can be installed to unlock full features:\n'
    case "$DISTRO_FAMILY" in
      arch)
        printf '  sudo pacman -S --needed %s\n' "${missing_optional[*]}"
        ;;
      apt)
        printf '  sudo apt-get install -y %s\n' "${missing_optional[*]}"
        ;;
      dnf)
        printf '  sudo dnf install -y %s\n' "${missing_optional[*]}"
        ;;
      zypper)
        printf '  sudo zypper install %s\n' "${missing_optional[*]}"
        ;;
      *)
        printf '  Packages: %s\n' "${missing_optional[*]}"
        ;;
    esac
  else
    printf '\nAll core and optional dependencies are satisfied! Tide Island is fully featured.\n'
  fi
}

clean_installer_directories() {
  local cache_dir
  cache_dir="$(installer_cache_dir)"
  if [[ -d "$cache_dir" ]]; then
    log "Removing installer cache ($cache_dir)"
    run rm -rf -- "$cache_dir"
  fi

  local root
  root="$(repo_root)"
  if [[ -d "$root/build-release-installer" ]]; then
    log "Removing build directory ($root/build-release-installer)"
    run rm -rf -- "$root/build-release-installer"
  fi

  local app_cache="${XDG_CACHE_HOME:-$HOME/.cache}/tide-island"
  if [[ -d "$app_cache" ]]; then
    log "Removing runtime cache ($app_cache)"
    run rm -rf -- "$app_cache"
  fi
}

uninstall_tide_island() {
  require_regular_user
  sudo_init
  [[ -f "$INSTALL_MANIFEST" || $DRY_RUN -eq 1 ]] \
    || die "no source installation manifest was found at $INSTALL_MANIFEST"

  if command -v systemctl >/dev/null 2>&1; then
    log "Stopping and disabling Tide Island user service"
    run systemctl --user disable --now tide-island.service || true
  fi
  remove_manifest_files
  run sudo rm -f -- "$INSTALL_MANIFEST"
  run sudo rm -f -- "/usr/bin/tide-island-lock"

  if [[ -f "$QUICKSHELL_INSTALL_MANIFEST" ]]; then
    local remove_qs=0
    if ((REMOVE_DEPS)); then
      remove_qs=1
    elif [[ -t 0 && ASSUME_YES -eq 0 ]]; then
      printf 'Quickshell was built and installed from source by Tide Island. Uninstall Quickshell? [y/N] '
      local answer
      read -r answer
      [[ "$answer" == "y" || "$answer" == "Y" ]] && remove_qs=1
    fi
    if ((remove_qs)); then
      log "Uninstalling source-built Quickshell"
      local qs_paths=()
      mapfile -t qs_paths < "$QUICKSHELL_INSTALL_MANIFEST"
      local i
      for ((i=${#qs_paths[@]} - 1; i >= 0; --i)); do
        local p="${qs_paths[i]}"
        [[ "$p" == /usr/* ]] && run sudo rm -f -- "$p"
      done
      run sudo rm -f -- "$QUICKSHELL_INSTALL_MANIFEST" "$QUICKSHELL_BUILD_INFO"
    fi
  fi

  if [[ -f "$INSTALLED_BUILD_DEPS" ]]; then
    local build_pkgs=()
    mapfile -t build_pkgs < "$INSTALLED_BUILD_DEPS"
    if ((${#build_pkgs[@]} > 0)); then
      local remove_b=0
      if ((REMOVE_DEPS || ASSUME_YES)); then
        remove_b=1
      elif [[ -t 0 ]]; then
        printf 'Uninstall build dependencies installed by Tide Island (%s)? [y/N] ' "${build_pkgs[*]}"
        local answer
        read -r answer
        [[ "$answer" == "y" || "$answer" == "Y" ]] && remove_b=1
      fi
      if ((remove_b)); then
        log "Uninstalling build dependencies"
        remove_distribution_packages "${build_pkgs[@]}"
        run sudo rm -f -- "$INSTALLED_BUILD_DEPS"
      fi
    fi
  fi

  if [[ -f "$INSTALLED_RUNTIME_DEPS" ]]; then
    local runtime_pkgs=()
    mapfile -t runtime_pkgs < "$INSTALLED_RUNTIME_DEPS"
    if ((${#runtime_pkgs[@]} > 0)); then
      local remove_r=0
      if ((REMOVE_DEPS)); then
        remove_r=1
      elif [[ -t 0 && ASSUME_YES -eq 0 ]]; then
        printf 'Do you want to uninstall core runtime dependencies that were installed by Tide Island (%s)? [y/N] ' "${runtime_pkgs[*]}"
        local answer
        read -r answer
        [[ "$answer" == "y" || "$answer" == "Y" ]] && remove_r=1
      fi
      if ((remove_r)); then
        log "Uninstalling core runtime dependencies"
        remove_distribution_packages "${runtime_pkgs[@]}"
        run sudo rm -f -- "$INSTALLED_RUNTIME_DEPS"
      else
        log "Leaving runtime dependencies installed"
      fi
    fi
  fi

  clean_installer_directories

  run sudo rm -f -- "$QUICKSHELL_BUILD_INFO" "$STATE_DIR"/*.txt 2>/dev/null || true
  run sudo rmdir --ignore-fail-on-non-empty "$STATE_DIR" 2>/dev/null || true
  command -v systemctl >/dev/null 2>&1 && run systemctl --user daemon-reload || true
  log "Tide Island uninstallation complete."
  printf 'Note: Your user configuration in %s has been preserved.\n' "${XDG_CONFIG_HOME:-$HOME/.config}/tide-island"
}

main() {
  parse_args "$@"
  load_os_release

  if ((CHECK_DEPS)); then
    check_dependencies
    return 0
  fi

  if ((UNINSTALL)); then
    uninstall_tide_island
    return
  fi

  require_regular_user
  package_install_conflict
  confirm
  sudo_init
  install_dependencies
  verify_build_tools
  build_quickshell
  build_tide_island
  configure_service
  clean_build_dependencies
  check_dependencies
  SERVICE_WAS_ACTIVE=0

  log "Tide Island installation completed"
  printf '  Config app: /usr/bin/tide-island-config-app\n'
  printf '  Logs:       journalctl --user -u tide-island -f\n'
  printf '  Uninstall:  ./%s --uninstall\n' "$SCRIPT_NAME"
}

main "$@"
