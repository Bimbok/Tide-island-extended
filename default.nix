{ lib
, stdenv
, cmake
, ninja
, pkg-config
, makeWrapper
, kdePackages
, systemd ? null
, udev ? systemd
, wayland
, wayland-protocols
, libdrm
, mesa
, python3
, quickshell ? null
, wl-clipboard ? null
, cliphist ? null
, wireplumber ? null
, pipewire ? null
, pulseaudio ? null
, cava ? null
, psmisc ? null
, brightnessctl ? null
, power-profiles-daemon ? null
, bluez ? null
, networkmanager ? null
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "tide-island";
  version = "1.1.3";

  src = lib.cleanSourceWith {
    src = ./.;
    filter = path: type:
      let base = baseNameOf path; in
      !(lib.hasPrefix "." base)
      && !(lib.hasPrefix "build" base)
      && base != "result";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    makeWrapper
    kdePackages.wrapQtAppsHook
  ];

  buildInputs = [
    kdePackages.qtbase
    kdePackages.qtdeclarative
    kdePackages.qt5compat
    kdePackages.qtwayland
    kdePackages.qtshadertools
    kdePackages.qtsvg
    udev
    wayland
    wayland-protocols
    libdrm
    mesa
    python3
  ];

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DTIDE_ISLAND_WITH_NIRI=ON"
  ];

  qtWrapperArgs = [
    "--prefix PATH : ${lib.makeBinPath (lib.filter (p: p != null) [
      quickshell
      wl-clipboard
      cliphist
      wireplumber
      pipewire
      pulseaudio
      cava
      psmisc
      brightnessctl
      power-profiles-daemon
      bluez
      networkmanager
      python3
    ])}"
  ];

  postInstall = let
    runtimeDeps = lib.makeBinPath (lib.filter (p: p != null) [
      quickshell
      wl-clipboard
      cliphist
      wireplumber
      pipewire
      pulseaudio
      cava
      psmisc
      brightnessctl
      power-profiles-daemon
      bluez
      networkmanager
      python3
    ]);
    qmlImportPaths = "$out/lib/qt6/qml:${kdePackages.qtdeclarative}/lib/qt-6/qml:${kdePackages.qt5compat}/lib/qt-6/qml";
  in ''
    # Wrap launcher script with runtime dependencies and Qt environment
    wrapProgram $out/bin/tide-island \
      --prefix PATH : "${runtimeDeps}" \
      --prefix QML_IMPORT_PATH : "${qmlImportPaths}" \
      --prefix QML2_IMPORT_PATH : "${qmlImportPaths}"
  '';

  meta = with lib; {
    description = "Dynamic Island desktop shell for Wayland compositors (Hyprland & niri)";
    homepage = "https://github.com/Bimbok/Tide-island-extended";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "tide-island";
  };
})
