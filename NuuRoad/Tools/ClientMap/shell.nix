# Everything Tools/ClientMap needs: nix-shell Tools/ClientMap/shell.nix --run "..."
{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  packages = [
    (pkgs.python3.withPackages (p: [ p.numpy p.pillow p.scipy ]))
    pkgs.cmake
    pkgs.gcc
    pkgs.git
    pkgs.curl
    pkgs.zlib
    pkgs.recastnavigation
    pkgs.nodejs
  ];
  RECAST = "${pkgs.recastnavigation}";
}
