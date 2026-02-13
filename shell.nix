{ pkgs ? import <nixpkgs> {}, win ? false }:
pkgs.mkShellNoCC {
  packages = with pkgs; [
    zig
    glibc
    libGL
    vulkan-loader
    wayland
    libxkbcommon
    libdecor
    xorg.libX11
    xorg.libXcursor
    xorg.libXrandr
    xorg.libXi
    pkgs.xdg-desktop-portal
    pkgs.xdg-desktop-portal-gtk
    pkgs.xdg-desktop-portal-hyprland
    pkgs.xdg-desktop-portal-gnome
    pkgs.zenity
  ];
  shellHook = ''
      export LD_LIBRARY_PATH=${
        pkgs.lib.makeLibraryPath [
          pkgs.glibc
          pkgs.libGL
          pkgs.vulkan-loader
          pkgs.wayland
          pkgs.libxkbcommon
          pkgs.libdecor
          pkgs.xorg.libX11
          pkgs.xorg.libXcursor
          pkgs.xorg.libXrandr
          pkgs.xorg.libXi
          pkgs.xdg-desktop-portal
          pkgs.xdg-desktop-portal-gtk
          pkgs.xdg-desktop-portal-hyprland
          pkgs.xdg-desktop-portal-gnome
          pkgs.zenity
        ]
      }

      zig fetch --save git+https://codeberg.org/7Games/zig-sdl3#v0.1.6
      zig build ${if win then "-Dtarget=x86_64-windows -Doptimize=Debug && wine_workaround=true wine ./zig-out/bin/rocket-slime-sprite-viewer.exe" else "&& ./zig-out/bin/rocket-slime-sprite-viewer"}

  '';
}
