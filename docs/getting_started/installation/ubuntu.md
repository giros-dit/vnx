# VNX Installation on Ubuntu

This section describes the procedure for manually installing VNX on Ubuntu 13.*, 14.*, 15.*, 16.*, 17.*, and 18.*. Open a root shell window and follow bellow steps:

Install all packages required (basic development, virtualization, perl libraries and auxiliar packages). In case of Ubuntu 18.10 change `libvirt-bin` by `libvirt-clients`:
```bash
 sudo apt-get update
 sudo apt-get install \
   bash-completion bridge-utils curl eog expect genisoimage gnome-terminal \
   graphviz libappconfig-perl libdbi-perl liberror-perl libexception-class-perl \
   libfile-homedir-perl libio-pty-perl libmath-round-perl libnetaddr-ip-perl \
   libnet-ip-perl libnet-ipv6addr-perl libnet-pcap-perl libnet-telnet-perl \
   libreadonly-perl libswitch-perl libsys-virt-perl libterm-readline-perl-perl \
   libvirt-bin libxml-checker-perl libxml-dom-perl libxml-libxml-perl \
   libxml-parser-perl libxml-tidy-perl lxc lxc-templates net-tools \
   openvswitch-switch picocom pv qemu-kvm screen tree uml-utilities virt-manager \
   virt-viewer vlan w3m wmctrl xdotool xfce4-terminal xterm lsof
```

Tune libvirt configuration to work with VNX. In particular, edit `/etc/libvirt/qemu.conf` file and set the following parameters (see this simple [script](qemuconf.md) to do it):
```
 security_driver = "none"
 user = "root"
 group = "root"
 cgroup_device_acl = [
    "/dev/null", "/dev/full", "/dev/zero",
    "/dev/random", "/dev/urandom",
    "/dev/ptmx", "/dev/kvm", "/dev/kqemu",
    "/dev/rtc", "/dev/hpet", "/dev/vfio/vfio", "/dev/net/tun"
 ]
```

(you have to add `/dev/net/tun`) and restart libvirtd for the changes to take effect:
```bash
 sudo restart libvirt-bin                # for ubuntu 14.10 or older
 sudo systemctl restart libvirt-bin      # for ubuntu 15.04 or later
```
Check that libvirt is running correctly, for example, executing:
```bash
 sudo virsh list
 sudo virsh capabilities
```

!!! attention 
    Have a look at [Vnx-install-trobleshooting|this document]] in case you get an error similar to this one: 
    `virsh: /usr/lib/libvirt.so.0: version LIBVIRT_PRIVATE-XXX not found (required by virsh)`

Install VNX:
```bash
 mkdir /tmp/vnx-update
 cd /tmp/vnx-update
 rm -rf /tmp/vnx-update/vnx-*
 wget http://vnx.dit.upm.es/vnx/vnx-latest.tgz
 tar xfvz vnx-latest.tgz
 cd vnx-*-*
 sudo ./install_vnx
```

Restart apparmor:
```bash
 service apparmor restart       # for Ubuntu 14.10 or older
 systemctl restart apparmor     # for Ubuntu 15.04 or later 
```

Create the VNX config file (/etc/vnx.conf). You just can move the sample config file:
```bash
 sudo mv /usr/share/vnx/etc/vnx.conf.sample /etc/vnx.conf
```

For Ubuntu 15.04 or newer: change parameter `overlayfs_workdir_option` in vnx.conf to 'yes'
```
 [lxc]
 ...
 overlayfs_workdir_option = 'yes'
 ...
```

For Ubuntu 16.04 or later: change the LXC union_type to 'overlayfs'
 [lxc]
 ...
 union_type='overlayfs'
 ...

Download root file systems from http://vnx.dit.upm.es/vnx/filesystems and install them following these [[Vnx-install-root_fs|instructions]]

Optionally, enable bash-completion in your system to allow using VNX bash completion capabilities. For example, to enable it for all users in your system, just edit '/etc/bash.bashrc' and uncomment the following lines:

```bash
# enable bash completion in interactive shells
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi
```



### Additional install steps for Dynamips support

* Install Dynamips and Dynagen:
```bash
 apt-get install dynamips dynagen
```

* Create a file /etc/init.d/dynamips (taken from http://7200emu.hacki.at/viewtopic.php?t=2198):

```bash
#!/bin/sh
# Start/stop the dynamips program as a daemon.
#
### BEGIN INIT INFO
# Provides:          dynamips
# Required-Start:
# Required-Stop:
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Cisco hardware emulator daemon
### END INIT INFO

DAEMON=/usr/bin/dynamips
NAME=dynamips
PORT=7200
PIDFILE=/var/run/$NAME.pid 
LOGFILE=/var/log/$NAME.log
DESC="Cisco Emulator"
SCRIPTNAME=/etc/init.d/$NAME

test -f $DAEMON || exit 0

. /lib/lsb/init-functions


case "$1" in
start)  log_daemon_msg "Starting $DESC " "$NAME"
        start-stop-daemon --start --chdir /tmp --background --make-pidfile --pidfile $PIDFILE --name $NAME --startas $DAEMON -- -H $PORT -l $LOGFILE
        log_end_msg $?
        ;;
stop)   log_daemon_msg "Stopping $DESC " "$NAME"
        start-stop-daemon --stop --quiet --pidfile $PIDFILE --name $NAME
        log_end_msg $?
        ;;
restart) log_daemon_msg "Restarting $DESC " "$NAME"
        start-stop-daemon --stop --retry 5 --quiet --pidfile $PIDFILE --name $NAME
        start-stop-daemon --start --chdir /tmp --background --make-pidfile --pidfile $PIDFILE --name $NAME --startas $DAEMON -- -H $PORT -l $LOGFILE
        log_end_msg $?
        ;;
status)
        status_of_proc -p $PIDFILE $DAEMON $NAME && exit 0 || exit $? 
        #status $NAME
        #RETVAL=$?
        ;; 
*)      log_action_msg "Usage: $SCRIPTNAME {start|stop|restart|status}"
        exit 2
        ;;
esac
exit 0
```

* Set execution permissions for the script and add it to system start-up:
```bash
 chmod +x /etc/init.d/dynamips
 update-rc.d dynamips defaults
 /etc/init.d/dynamips start
```

* Download and install cisco IOS image:
```bash
  cd /usr/share/vnx/filesystems
  # Cisco image
  wget ... c3640-js-mz.124-19.image
  ln -s c3640-js-mz.124-19.image c3640
```

* Calculate the idle-pc value for your computer following the procedure in http://dynagen.org/tutorial.htm:
 dynagen /usr/share/vnx/examples/R3640.net
 console R3640     # type 'no' to exit the config wizard and wait 
               # for the router to completely start 
 idlepc get R3640
Once you know the idlepc value for your system, include it in /etc/vnx.conf file.
