let
  nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-unstable";
  pkgs = import nixpkgs {
    config = { };
    overlays = [ ];
  };
in

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
    if $win; then
        # build with: win=true nix-shell
        zig build -Dtarget=x86_64-windows -Doptimize=ReleaseSmall
    else
        zig build && ./zig-out/bin/main
    fi
    exit
  '';
}
