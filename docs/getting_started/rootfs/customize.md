# Customize Root Filesystem

This document describes how to make permanent changes to a VNX root filesystem. The recomended way is to use VNX to start a virtual machine that mounts the rootfs in direct mode and make the desired changes from the VM console. Alternatevily, modifications can be made manually by mounting the rootfs in the host or manually starting a virtual machine. Both ways are described below.

## Using VNX tools

You can modify a KVM or LXC root filesystem by using the `--modify-rootfs` option, for example:
```bash
 vnx --modify-rootfs vnx_rootfs_kvm_debian-7.0.0-v025.qcow
 vnx --modify-rootfs vnx_rootfs_lxc_ubuntu-14.04-v025
```

This command starts new VM that mounts the root filesystem specified in direct mode. Therefore, any change made in the VM will persist after stopping it. Besides, the VM is started with Internet connectivity, by means of a network interface connected to libvirt virbr0 or LXC lxcbr0 bridges. 

Several aditional parameters can be used with `--modify-rootfs` option:

- `--arch` to select processor architecture: `i686` for 32 bits and `x86_64` for 64 bits
- `--vcpu` to select the number of procesor cores to assign to the VM.
- `--rootfs-type` to specify the rootfs type (libvirt-kvm or lxc). If not specified, VNX tries to guess the type. Default value is libvirt-kvm.
- `--mem` to specify the memory to assign to the VM (ignored for LXC). 
- `--update-aced` to try to automatically update the VNX autoconfiguration daemon (not applicable for LXC).

For example:
```bash
 vnx --modify-rootfs vnx_rootfs_kvm_debian64.qcow2 --mem 512M --vcpu 4 --arch x86_64 --update-aced
```

Root filesystem modifications should be finished by executing `vnx_halt` command, that clears some system log files and caches (bash history, packages caches, etc) and optionally allows to write a one-line message describing the changes made that is stored in `/etc/vnx_rootfs_version` file. 

!!! attention
    `vnx_halt` command is not available yet for LXC.

## Manually

### Manually modifying a KVM root filesystem

In order to update or modify a KVM VNX root filesystem, you can mount it in the host and make the modifications directly without starting a virtual machine. To do that:

Create a ndb device with the filesystem:
```bash
 modprobe nbd
 qemu-nbd -c /dev/nbd0 <rootfs_name>
```
being `<rootfs_name>` the rootfs filename.

Consult the rootfs partitions with:
```bash
 fdisk -l /dev/ndb0
```

Mount the desired partition with:
```bash
 mount /dev/nbd0p1 /mnt
```
Do the modifications desired directly accesing files. You can chroot the the mount directory in order to install software.
At the end, unmount the particition and release nbd device:
```bash
 umount /mnt
 qemu-nbd -d /dev/nbd0
```

Examples:

- Ubuntu rootfs
```bash
$ modprobe nbd
$ qemu-nbd -c /dev/nbd0 vnx_rootfs_kvm_ubuntu-12.04-v024.qcow2 
$ fdisk -l /dev/nbd0

Disco /dev/nbd0: 8589 MB, 8589934592 bytes
255 cabezas, 63 sectores/pista, 1044 cilindros, 16777216 sectores en total
Unidades = sectores de 1 * 512 = 512 bytes
Tamaño de sector (lógico / físico): 512 bytes / 512 bytes
Tamaño E/S (mínimo/óptimo): 512 bytes / 512 bytes
Identificador del disco: 0x0000e82c

Dispositivo Inicio    Comienzo      Fin      Bloques  Id  Sistema
/dev/nbd0p1   *        2048    15728639     7863296   83  Linux
/dev/nbd0p2        15730686    16775167      522241    5  Extendida
/dev/nbd0p5        15730688    16775167      522240   82  Linux swap / Solaris
$ mount /dev/nbd0p1 /mnt/
...
$ umount /mnt 
$ qemu-nbd -d /dev/nbd0
/dev/nbd0 disconnected
```

- FreeBSD rootfs:
```bash
$ modprobe nbd
$ qemu-nbd -c /dev/nbd0 vnx_rootfs_kvm_freebsd64-9.1-v025m2.qcow2
$ fdisk -l /dev/nbd0

AVISO: GPT (Tabla de partición GUID) detectado en '/dev/nbd0'! La utilidad fdisk no soporta GPT. Use GNU Parted.


Disco /dev/nbd0: 12.9 GB, 12884901888 bytes
256 cabezas, 63 sectores/pista, 1560 cilindros, 25165824 sectores en total
Unidades = sectores de 1 * 512 = 512 bytes
Tamaño de sector (lógico / físico): 512 bytes / 512 bytes
Tamaño E/S (mínimo/óptimo): 512 bytes / 512 bytes
Identificador del disco: 0x00000000

Dispositivo Inicio    Comienzo      Fin      Bloques  Id  Sistema
/dev/nbd0p1   *           1    25165823    12582911+  ee  GPT
$ parted /dev/nbd0 print
Modelo: Desconocida (unknown)
Disco /dev/nbd0: 12,9GB
Tamaño de sector (lógico/físico): 512B/512B
Tabla de particiones. gpt

Numero  Inicio  Fin     Tamaño  Sistema de archivos  Nombre  Banderas
 1      17,4kB  82,9kB  65,5kB
 2      82,9kB  11,8GB  11,8GB  freebsd-ufs
 3      11,8GB  12,5GB  644MB

$ mount -r -t ufs -o ufstype=ufs2 /dev/nbd0p2 /mnt/
$ ls /mnt/
bin  boot  COPYRIGHT  dev  etc  lib  libexec  media  mnt  proc  rescue  root  sbin  sys  tmp  usr  var
$ umount /mnt 
$ qemu-nbd -d /dev/nbd0
/dev/nbd0 disconnected
```

#### Updating VNXACE daemon

If you have a rootfs with the autoconfiguration and command execution daemon (ACE) already installed, you can use the autoupdate functionality to update the daemon to a newer version. Just follow this procedure:

- Linux and FreeBSD

Start the virtual machine with the following command line options:
```bash
 vnx --modify-rootfs <rootfs_name> --update-aced -y
```
being `<rootfs_name>` the rootfs filename. This command will try to update the VNXACE daemon to the latest version automatically (-y option).
If everything goes well, a message informing the new version installed will be shown in the virtual machine console before halting it.
If the daemon is not updated automatically, you can do it manually from inside the virtual machine:

Mounting the update disk:
```bash
 mount /dev/sdb /mnt               # For Linux
 mount -t msdosfs /dev/ad1 /mnt    # For FreeBSD
```
Installing VNXACED:
```bash
 perl /mnt/vnxaced-lf/install_vnxaced
```

- Windows: to be completed
- Olive: to be completed

### Manually modifying a LXC root filesystem

To manually install additional software or modify a LXC rootfs follow the next steps:
- Modify directly the files of the rootfs from the host, because LXC rootfs is just a directory on the host where all the files of the VM image can be directly modified. Beware that user and groud ids are different in host and VM.
Start a LXC virtual machine with:
```bash
lxc-start -n vnx_rootfs_lxc_ubuntu -f /usr/share/vnx/filesystems/vnx_rootfs_lxc_ubuntu/config
```

Once the VM is started, check that the network is working. If not, start the network with:
```bash
dhclient eth0
```
After installing or modifying the rootfs, stop the VM with `halt`.

!!! attention
    `vnx_halt` command is not available yet for LXC.

