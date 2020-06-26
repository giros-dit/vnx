# Virtual Networks over linuX (VNX)

<center>![VNX](img/vnx.png)</center>

VNX is a general purpose open-source virtualization tool designed to help building virtual network testbeds automatically. It allows the definition and automatic deployment of network scenarios made of virtual machines of different types (Linux, Windows, FreeBSD, Olive or Dynamips routers, etc) interconnected following a user-defined topology, possibly connected to external networks.

VNX has been developed by the [Telematics Engineering Department (DIT)](https://www.dit.upm.es) of the [Technical University of Madrid (UPM)](http://www.upm.es/internacional).

VNX is a useful tool for testing network applications/services over complex testbeds made of virtual nodes and networks, as well as for creating complex network laboratories to allow students to interact with realistic network scenarios. As other similar tools aimed to create virtual network scenarios (like GNS3, NetKit, MLN or Marionnet), VNX provides a way to manage testbeds avoiding the investment and management complexity needed to create them using real equipment.

VNX is made of two main parts:

- XML language that allows describing the virtual network scenario (VNX specification language)
- VNX engine, that parses the scenario description and builds and manages the virtual scenario over a Linux machine

VNX comes with a distributed version (EDIV) that allows the deployment of virtual scenarios over clusters of Linux servers, improving the scalability to scenarios made of tenths or even hundreds of virtual machines.

VNX is built over the long experience of a previous tool named [VNUML (Virtual Networks over User Mode Linux)](http://web.dit.upm.es/vnumlwiki/index.php/Main_Page) and brings important new functionalities that overcome the most important limitations VNUML tool had:

- Integration of new virtualization platforms to allow virtual machines running other operating systems (Windows, FreeBSD, etc) apart from Linux. In this sense:
    - VNX uses libvirt to interact with the virtualization capabilities of the host, allowing the use of most of the virtualization platforms available for Linux (KVM, Xen, etc)
    - Integrates Dynamips and Olive router virtualization platforms to allow limited emulation of CISCO and Juniper routers
    - Integrates also Linux Containers (LXC) support
- Individual management of virtual machines
- Autoconfiguration and command execution capabilities for several operating systems: Linux, FreeBSD and Windows (XP and 7)
- Integration of Openvswitch with support for VLAN configuration, inter-switches connections and SDN parameter configuration (controller ip address, mode, Openflow version, etc.).

VNX has been developed with the help and support of several people and companies. See the VNX [history](home/history.md) page for details.