#!/bin/zsh
ID=777
NAME="ligma"
RAM_MIN=12288
RAM_MAX=16384
CPU=4
MAC="BC:24:11:7B:34:F2"
ORDER=3

echo "Creating VM $NAME"
ssh proxmox << EOF
qm create $ID \
  --name $NAME \
  --machine q35 \
  --bios ovmf \
  --ostype l26 \
  --memory $RAM_MAX \
  --balloon $RAM_MIN \
  --cores $CPU \
  --sockets 1 \
  --cpu host \
  --onboot 1 \
  --startup order=$ORDER \
  --tablet 0 \
  --agent enabled=1,fstrim_cloned_disks=1 \
  --net0 virtio=$MAC,bridge=vmbr0,queues=4 \
  --scsihw virtio-scsi-single \
  --scsi0 wdblacksn850x:50,discard=on,iothread=1,ssd=1,serial=nixos,backup=0 \
  --scsi1 wdblacksn850x:300,discard=on,iothread=1,ssd=1,serial=ligma \
  --efidisk0 wdblacksn850x:4,efitype=4m \
  --ide2 local:iso/nixos-minimal-x86_64-linux.iso,media=cdrom \
  --boot "order=scsi0;ide2"
EOF

echo "Starting VM $NAME"
ssh proxmox "qm start $ID"

echo "Done xd"
