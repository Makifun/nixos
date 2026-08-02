#!/bin/zsh
ID=666
NAME="arrma"
RAM_MIN=5120
RAM_MAX=8192
CPU=2
MAC="26:8e:1e:50:9e:d1"
ORDER=6

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
  --net0 virtio=$MAC,bridge=vmbr0,queues=2 \
  --scsihw virtio-scsi-single \
  --scsi0 wdblacksn850x:50,discard=on,iothread=1,ssd=1,serial=nixos,backup=0 \
  --scsi1 wdblacksn850x:50,discard=on,iothread=1,ssd=1,serial=arrma \
  --scsi2 evo850:200,discard=on,iothread=1,ssd=1,serial=nicememe,backup=0 \
  --scsi3 wdc7HKDX5JF8tb:1000,iothread=1,serial=slowmeme,backup=0 \
  --efidisk0 wdblacksn850x:4,efitype=4m \
  --ide2 local:iso/nixos-minimal-x86_64-linux.iso,media=cdrom \
  --boot "order=scsi0;ide2"
EOF

echo "Starting VM $NAME"
ssh proxmox "qm start $ID"

echo "Done xd"
