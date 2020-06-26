# Updating VNX

This document describes the procedure to manually update VNX to the [latest version](http://vnx.dit.upm.es/vnx/vnx-latest.tgz). There are two methods to update VNX:

- Using `vnx_update` script distributed with VNX:
```bash
/usr/share/vnx/bin/vnx_update
```

- Manually downloading the tgz file, uncompressing and installing it:
```bash
mkdir /tmp/vnx-update
cd /tmp/vnx-update
rm -rf /tmp/vnx-update/vnx-*
wget http://vnx.dit.upm.es/vnx/vnx-latest.tgz
tar xfvz vnx-latest.tgz
cd vnx-*
./install_vnx
```