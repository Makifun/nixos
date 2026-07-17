#!/bin/zsh
echo "Creating VM bofa"
ssh proxmox 'qm create 888 \
  --name bofa \
  --machine q35 \
  --bios ovmf \
  --ostype l26 \
  --memory 8192 \
  --balloon 0 \
  --cores 4 \
  --sockets 1 \
  --cpu host \
  --numa 1 \
  --agent enabled=1 \
  --net0 virtio=2E:7A:45:73:8C:64,bridge=vmbr0,firewall=1,queues=4 \
  --scsihw virtio-scsi-single \
  --scsi0 wdblacksn850x:50,discard=on,iothread=1,ssd=1,serial=nixos,backup=0 \
  --scsi1 wdblacksn850x:100,discard=on,iothread=1,ssd=1,serial=bofa \
  --efidisk0 wdblacksn850x:4,efitype=4m \
  --ide2 local:iso/nixos-minimal-x86_64-linux.iso,media=cdrom \
  --boot "order=scsi0;ide2"'

echo "Starting VM bofa"
ssh proxmox 'qm start 888'

echo "Done xd"
