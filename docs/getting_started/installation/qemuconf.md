# QEMUCONF Script

If you have just installed libvirt, the parameters to be modified should be commented in the configuration file. So, you just can copy/paste this commands to modify it:

```bash
 cat << EOF >> /etc/libvirt/qemu.conf
 security_driver = "none"
 user = "root"
 group = "root"
 cgroup_device_acl = [
    "/dev/null", "/dev/full", "/dev/zero",
    "/dev/random", "/dev/urandom",
    "/dev/ptmx", "/dev/kvm", "/dev/kqemu",
    "/dev/rtc", "/dev/hpet", "/dev/vfio/vfio", "/dev/net/tun"
 ]
 EOF
```