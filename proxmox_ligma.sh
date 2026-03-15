#!/bin/sh

ssh proxmox 'qm create 777 --name ligma --machine q35 --bios ovmf --ostype l26 --memory 10240 --cores 4 --sockets 1 --cpu host --numa 1 --agent enabled=1 --net0 virtio=BC:24:11:7B:34:F2,bridge=vmbr0,firewall=1,queues=4 --scsihw virtio-scsi-single --scsi0 wdblacksn850x:50,discard=on,iothread=1,ssd=1,serial=nixos,backup=0 --scsi1 wdblacksn850x:200,discard=on,iothread=1,ssd=1,serial=ligma --efidisk0 wdblacksn850x:4,efitype=4m --ide2 local:iso/nixos-minimal-25.11.20260220.c217913-x86_64-linux.iso,media=cdrom --boot "order=scsi0;ide2"'
