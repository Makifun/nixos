#!/bin/sh
if [[ -n "$1" ]]; then
    nix run github:nix-community/nixos-anywhere -- --flake .#$1 --copy-host-keys $1
else
    echo "./nixos_install.sh <hostname>"
fi