#!/bin/zsh
ID=999
NAME="playma"
RAM_MIN=2048
RAM_MAX=4096
CPU=4
MAC="3E:91:5C:2D:88:7E"

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
  --numa 1 \
  --onboot 1 \
  --startup order=5 \
  --tablet 0 \
  --agent enabled=1,fstrim_cloned_disks=1 \
  --hostpci0 0000:00:02.0,mdev=i915-GVTg_V5_4,pcie=1 \
  --net0 virtio=$MAC,bridge=vmbr0,firewall=1,queues=4 \
  --scsihw virtio-scsi-single \
  --scsi0 wdblacksn850x:50,discard=on,iothread=1,ssd=1,serial=nixos,backup=0 \
  --scsi1 wdblacksn850x:100,discard=on,iothread=1,ssd=1,serial=playma \
  --scsi2 evo860:50,discard=on,iothread=1,ssd=1,serial=transcode,backup=0 \
  --scsi3 evo850:200,discard=on,iothread=1,ssd=1,serial=cache,backup=0 \
  --efidisk0 wdblacksn850x:4,efitype=4m \
  --ide2 local:iso/nixos-minimal-x86_64-linux.iso,media=cdrom \
  --boot "order=scsi0;ide2"
EOF

echo "Starting VM $NAME"
ssh proxmox "qm start $ID"

echo "Done xd"
