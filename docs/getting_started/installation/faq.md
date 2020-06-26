# Troubleshooting

## **Q:** When I execute "virsh list" or other virsh commands I get the following error:

```
 virsh: /usr/lib/libvirt.so.0: version LIBVIRT_PRIVATE_XXX not found (required by virsh)
```

**A**: It seems that libvirt installation scripts do not manage correctly the links 
to libvirt libraries when, for example, you manually install a version of libvirt and later change it to a new one or you try to use the libvirt version distributed as package. To solve that, check the version you are using:
```bash 
libvirtd --version
```
Remove the old links:
```bash
 cd /usr/lib
 rm libvirt-qemu.so libvirt-qemu.so.0 libvirt.so libvirt.so.0
```
Recreate the links to libraries (change '0.9.8' by the version number you are using):
```bash
 ln -s libvirt-qemu.so.0.9.8 libvirt-qemu.so
 ln -s libvirt-qemu.so.0.9.8 libvirt-qemu.so.0
 ln -s libvirt.so.0.9.8 libvirt.so
 ln -s libvirt.so.0.9.8 libvirt.so.0
```
Restart libvirt:
```bash
 stop libvirt-bin
 start libvirt-bin
```

!!! note
    Do not try `restart libvirt-bin`. It does not work, at least in our case...

## **Q:** When I try to create a virtual scenario I get the following error:
```
 VNX::vmAPI_libvirt::defineVM (1172): error connecting to qemu:///system hypervisor.
 libvirt error code: 38, message: Failed to connect socket to '/var/run/libvirt/libvirt-sock': ...
```

**A**: Seems that libvirt is not running correctly. Check libvirt configuration and be sure it works before executing VNX. Try the following commands to see if you get an error message that will guide you. Further information available at [Libvirt troubleshooting](http://wiki.libvirt.org/page/Troubleshooting):
```bash
 virsh list
 virsh capabilities
```
