# LXC Tutorial

## Description

VNX includes several example scenarios based on the [VNUML tutorial scenario](http://web.dit.upm.es/vnumlwiki/index.php/Tutorial) but including all types of virtual machines supported by VNX (see tutorial_*.xml files in /usr/share/vnx/examples directory). 

The scenario presented here is made of 6 Ubuntu LXC virtual machines (4 hosts -h1, h2, h3 and h4- and 2 routers -r1 and r2-) connected through three virtual networks. The host participates in the scenario having a network interface in Net3. All systems use an Ubuntu server root filesystem.

## Preparing the scenario

To use this scenario, you need to download one of the VNX LXC root filesystems. For example:

```bash
cd /usr/share/vnx/filesystems
vnx_download_rootfs -r vnx_rootfs_lxc_ubuntu-14.04-v025.tgz -y -l
```

You can see the LXC rootfs available using:
```bash
vnx_download_rootfs -l
```

Beware that LXC 'light' virtual machines use the host kernel to run, so you can have problems if your host and VM images are very different. LXC support in VNX have been successfully tested only in Ubuntu 13.10 and 14.04.

## Starting the scenario

Start the scenario with:

```bash
cd /usr/share/vnx/examples/
sudo vnx -f tutorial_lxc_ubuntu.xml -v --create
```

You will see the six textual consoles of the virtual machine consoles opening. 

If you close the console of a VM (for example h4), you can reopen it with:
```bash
sudo vnx -f tutorial_lxc_ubuntu.xml -v --console -M h4
```

LXC allows to open multiple textual consoles of each VM. Repeat the command to open new ones.

You can also open the consoles manually with the commands shown at the end of vnx execution:

```
----------------------------------------------------------------------------------------------------
 Scenario "tutorial_lxc_ubuntu" started

 VM_NAME     | TYPE                | CONSOLE ACCESS COMMAND
-----------------------------------------------------------------------------------------
 h1          | lxc                 | con0:  'lxc-console -n h1'
             |                     | con1:  'lxc-console -n h1'
-----------------------------------------------------------------------------------------
 h2          | lxc                 | con0:  'lxc-console -n h2'
             |                     | con1:  'lxc-console -n h2'
-----------------------------------------------------------------------------------------
 r1          | lxc                 | con0:  'lxc-console -n r1'
             |                     | con1:  'lxc-console -n r1'
-----------------------------------------------------------------------------------------
 r2          | lxc                 | con0:  'lxc-console -n r2'
             |                     | con1:  'lxc-console -n r2'
-----------------------------------------------------------------------------------------
 h3          | lxc                 | con0:  'lxc-console -n h3'
             |                     | con1:  'lxc-console -n h3'
-----------------------------------------------------------------------------------------
 h4          | lxc                 | con0:  'lxc-console -n h4'
             |                     | con1:  'lxc-console -n h4'
-----------------------------------------------------------------------------------------
```

You can show the previous table at any time with:
```bash
sudo vnx -f tutorial_lxc_ubuntu.xml -v --console-info
```

See for more details about consoles.

## Executing commands

You can start the web servers in h3 and h4 with:
```bash
sudo vnx -f tutorial_lxc_ubuntu.xml -v -x start-www -M h3,h4
```

This command will execute on h3 and h4 the commands defined by means of <exec> and <filetree> tags and marked with seq="start-www". For example, for h3 virtual machine: 
```xml
 <!-- Copy the files under conf/tutorial_ubuntu/h3 to vm /var/www directory -->
 <filetree seq="start-www" root="/var/www">conf/tutorial_ubuntu/h3</filetree>
 <!-- Start/stop apache www server -->
 <exec seq="start-www" type="verbatim" ostype="system">chmod 644 /var/www/*</exec>
 <exec seq="start-www" type="verbatim" ostype="system">service apache2 start</exec>
```

Once you have started the web servers, you can connect to them from the host or from h1 by opening a web navigator and loading http://10.1.2.2.

## Stopping the scenario

To stop the scenario preserving the changes made inside virtual machines you have to use the "-d" or "--shutdown" option:
```bash
sudo vnx -f tutorial_lxc_ubuntu.xml -v --shutdown
```

You can later restart the scenario with:
```bash
sudo vnx -f tutorial_lxc_ubuntu.xml -v --start
```

To stop the scenario discarding all the changes made in the virtual machines use the "-P" or "--destroy" option:
```bash
sudo vnx -f tutorial_lxc_ubuntu.xml -v --destroy
```

## Other interesting options

You can see the status of the VMs of the scenario with:
```bash
sudo vnx -f tutorial_lxc_ubuntu.xml -v --show-status
```

You can restart the virtual machines individually with:
```bash
sudo vnx -f tutorial_lxc_ubuntu.xml -v --shutdown -M h1
sudo vnx -f tutorial_lxc_ubuntu.xml -v --start -M h1
```

You can suspend to memory and restore a virtual machine with:
```bash
sudo vnx -f tutorial_lxc_ubuntu.xml -v --suspend -M h1
sudo vnx -f tutorial_lxc_ubuntu.xml -v --resume -M h1
```

You can see a graphical map of the virtual scenario using the --show-map option:
```bash
sudo vnx -f tutorial_lxc_ubuntu.xml -v --show-map
```

## tutorial_lxc_ubuntu.xml scenario

```xml
<pre>
<?xml version="1.0" encoding="UTF-8"?>

<!--

~~~~~~~~~~~~~~~~~~~~
VNX Sample scenarios
~~~~~~~~~~~~~~~~~~~~

Name:        tutorial_ubuntu
Description: As simple tutorial scenario made of 6 LXC Ubuntu virtual machines (4 hosts: h1, h2, h3 and h4; 
             and 2 routers: r1 and r2) connected through three virtual networks. The host participates 
             in the scenario having a network interface in Net3.     

This file is part of the Virtual Networks over LinuX (VNX) Project distribution. 
(www: http://www.dit.upm.es/vnx - e-mail: vnx@dit.upm.es) 

Departamento de Ingenieria de Sistemas Telematicos (DIT)
Universidad Politecnica de Madrid
SPAIN

-->

<vnx xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:noNamespaceSchemaLocation="/usr/share/xml/vnx/vnx-2.00.xsd">
  <global>
    <version>2.0</version>
    <scenario_name>tutorial_lxc_ubuntu</scenario_name>
    <automac/>
    <vm_mgmt type="none" />
    <!--vm_mgmt type="private" network="10.250.0.0" mask="24" offset="200">
       <host_mapping />
    </vm_mgmt-->
    <vm_defaults>
        <console id="0" display="no"/>
        <console id="1" display="yes"/>
    </vm_defaults>

    <cmd-seq seq="ls12">ls1,ls2</cmd-seq>
    <cmd-seq seq="ls123">ls12,ls3</cmd-seq>
    <cmd-seq seq="ls1234">ls123,ls4</cmd-seq>

    <help>
        <seq_help seq='start-www'>Start apache2 web server</seq_help>
        <seq_help seq='stop-www'>Stop apache2 web server</seq_help>
    </help>
    
  </global>

  <net name="Net0" mode="virtual_bridge" />
  <net name="Net1" mode="virtual_bridge" />
  <net name="Net2" mode="virtual_bridge" />
  <net name="Net3" mode="virtual_bridge" />

  <vm name="h1" type="lxc">
    <filesystem type="cow">/usr/share/vnx/filesystems/rootfs_lxc</filesystem>
    <if id="1" net="Net0">
      <ipv4>10.1.0.2/24</ipv4>
    </if>
    <route type="ipv4" gw="10.1.0.1">default</route>   
  </vm>

  <vm name="h2" type="lxc">
    <filesystem type="cow">/usr/share/vnx/filesystems/rootfs_lxc</filesystem>
    <if id="1" net="Net0">
      <ipv4>10.1.0.3/24</ipv4>
    </if>
    <route type="ipv4" gw="10.1.0.1">default</route>
    <exec seq="ls1" type="verbatim">ls -al /tmp</exec>
    <exec seq="ls2" type="verbatim">ls -al /root</exec>
    <exec seq="ls3" type="verbatim">ls -al /usr</exec>
    <exec seq="ls4" type="verbatim">ls -al /bin</exec>
  </vm>

  <vm name="r1" type="lxc">
    <filesystem type="cow">/usr/share/vnx/filesystems/rootfs_lxc</filesystem>
    <if id="1" net="Net0">
      <ipv4>10.1.0.1/24</ipv4>
    </if>
    <if id="2" net="Net1">
      <ipv4>10.1.1.1/24</ipv4>
    </if>
    <if id="3" net="Net3">
      <ipv4>10.1.3.1/24</ipv4>
    </if>
    <route type="ipv4" gw="10.1.1.2">10.1.2.0/24</route>
    <forwarding type="ip" />
  </vm>

  <vm name="r2" type="lxc">
    <filesystem type="cow">/usr/share/vnx/filesystems/rootfs_lxc</filesystem>
    <if id="1" net="Net1" name="s1/0">
      <ipv4>10.1.1.2/24</ipv4>
    </if>
    <if id="2" net="Net2" name="e0/0">
      <ipv4>10.1.2.1/24</ipv4>
    </if>
    <route type="ipv4" gw="10.1.1.1">default</route>
    <forwarding type="ip" />
  </vm>

  <vm name="h3" type="lxc">
   <filesystem type="cow">/usr/share/vnx/filesystems/rootfs_lxc</filesystem>
   <if id="1" net="Net2">
      <ipv4>10.1.2.2/24</ipv4>
    </if>
    <route type="ipv4" gw="10.1.2.1">default</route>
    <!-- Copy the files under conf/tutorial_ubuntu/h3 to vm /var/www directory -->
    <filetree seq="start-www" root="/var/www/">conf/tutorial_ubuntu/h3</filetree>
    <!-- Start/stop apache www server -->
    <exec seq="start-www" type="verbatim" ostype="system">chmod 644 /var/www/*</exec>
    <exec seq="start-www" type="verbatim" ostype="system">service apache2 start</exec>
    <exec seq="stop-www" type="verbatim"  ostype="system">service apache2 stop</exec>    
  </vm>
  
  <vm name="h4" type="lxc">
    <filesystem type="cow">/usr/share/vnx/filesystems/rootfs_lxc</filesystem>
    <if id="1" net="Net2">
      <ipv4>10.1.2.3/24</ipv4>
    </if>
    <route type="ipv4" gw="10.1.2.1">default</route>    
    <!-- Copy the files under conf/tutorial_ubuntu/h4 to vm /var/www directory -->
    <filetree seq="start-www" root="/var/www/">conf/tutorial_ubuntu/h4</filetree>
    <!-- Start/stop apache www server -->
    <exec seq="start-www" type="verbatim" ostype="system">chmod 644 /var/www/*</exec>
    <exec seq="start-www" type="verbatim" ostype="system">service apache2 start</exec>
    <exec seq="stop-www" type="verbatim"  ostype="system">service apache2 stop</exec>    
  </vm>
  
  <host>
    <hostif net="Net3">
       <ipv4>10.1.3.2/24</ipv4>
    </hostif>
    <route type="ipv4" gw="10.1.3.1">10.1.0.0/16</route>
  </host>

</vnx>
</pre>
```
