{ pkgs ? import <nixpkgs> {} }:

let
  # Pin to nixpkgs-unstable for latest kubeseal
  unstable = import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/nixpkgs-unstable.tar.gz") {};
in
pkgs.mkShell {
  buildInputs = [
    pkgs.talosctl
    pkgs.fluxcd
    # Use kubeseal from unstable to get v0.32.2
    unstable.kubeseal
  ];
}