#!/bin/sh
echo "Building minimaliso"
nix build .#nixosConfigurations.minimaliso.config.system.build.isoImage
echo "Copying to proxmox"
scp result/iso/nixos-minimal-x86_64-linux.iso proxmox:/var/lib/vz/template/iso/nixos-minimal-x86_64-linux.iso
echo "Done xd"