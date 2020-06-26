
# VNX Latest News

**Ago 27th, 2019** -- New **Openstack Stein Laboratory** virtual scenario released. See more details [[Vnx-labo-openstack-4nodes-classic-ovs-stein|here]]. 

**Ago 31th, 2017** - New KVM and LXC root filesystems based on Ubuntu 17.04 available (only 64 bits). Download it from [http://vnx.dit.upm.es/vnx/filesystems here] or using "vnx_download_rootfs" command.

**Ago 30th, 2017** - Added support for **VyOS network operating system**. Now VNX supports the creation of virtual scenarios including VyOS based virtual machines (either KVM or LXC). See more details [[Vnx-latest-features|here]].

**Dec 29th, 2016** -- New KVM root filesystems based on Kali 2016.2 distribution (https://www.kali.org/). Download it from [here](http://vnx.dit.upm.es/vnx/filesystems) or using "vnx_download_rootfs -p kali" command. Note: use the ``<video>vmvga</video>`` tag in the virtual machine. See the simple_kali64_inet.xml example scenario in latest VNX version.

**Nov 28th, 2016** -- New KVM root filesystems based on Metasploitable2 distribution (http://r-7.co/Metasploitable2). Download it from [http://vnx.dit.upm.es/vnx/filesystems here] or using "vnx_download_rootfs -p metasploitable" command.

**Nov 2nd, 2016** -- New KVM root filesystems based on Fedora 24 server available (only 64 bits version). Download it from [http://vnx.dit.upm.es/vnx/filesystems here] or using "vnx_download_rootfs" command.

**Oct 23th, 2016** -- Openstack Mitaka test scenario released. See more details [[Vnx-labo-openstack-4nodes-classic-ovs-mitaka|here]].

**May 25th, 2016** -- VPLS test scenario based on OpenBSD published. See more details [[Vnx-labo-vpls|here]].

**May 16th, 2016** -- Support for virtio drivers in libvirt virtual machines implemented to improve performance. See more details [[vnx-latest-features|here]].

**May 7th, 2016** -- New KVM and LXC root filesystems based on Ubuntu 16.04 available (have a look at the new Xubuntu version distributed). Download it from [http://vnx.dit.upm.es/vnx/filesystems here] or using "vnx_download_rootfs" command.

**May 2nd, 2016** -- OpenBSD support: VNX now supports OpenBSD virtual machines thanks to Francisco Javier Ruiz contribution.

**March 21th, 2016** -- See some very interesting SDN virtual scenarios prepared by Carlos Martín-Cleto for his Master's Thesis: https://github.com/cletomcj/vnx-sdn.

**February 21th, 2016** -- New vagrant and virtualbox (OVA) [http://goo.gl/8RxXvA VNX demo virtual machines] available for easily test LXC based virtual scenarios (see instructions for [http://goo.gl/f9jnvA Vagrant] and [http://goo.gl/JdB9ik VirtualBox]).

**February 15th, 2016** -- New KVM root filesystems based on Ubuntu 15.10 available (server and lubuntu in 32 and 64 bits versions). Download it from [http://vnx.dit.upm.es/vnx/filesystems here] or using "vnx_download_rootfs" command.

**February 14th, 2016** -- New recipe to [http://web.dit.upm.es/vnxwiki/index.php/Vnx-install-fedora23 install VNX on Fedora]. Tested on a fresh copy of Fedora 23 workstation. 

**July 24th, 2015** -- New Openstack-Opendaylight laboratory scenarios available: https://goo.gl/JpxCnB. Designed to explore an OpenStack environment running OpenDaylight as the network management provider. Prepared by Raúl Álvarez Pinilla as a result of his Master's Thesis. 

**June 16th, 2015** -- New LXC root filesystems based on Ubuntu 15.04 available (32 and 64 bits). Download it from [http://vnx.dit.upm.es/vnx/filesystems here] or using "vnx_download_rootfs" command.

**June 10th, 2015** -- New root filesystems based on REMnux: A Linux Toolkit for Reverse-Engineering and Analyzing Malware. Download it from [http://vnx.dit.upm.es/vnx/filesystems here] or using "vnx_download_rootfs" command. Use simple_remnux.xml example scenario to test it.

**June 6th, 2015** -- New interesting VNX scenario available: a [[Vnx-labo-fw|security lab]] designed to allow 16 student groups to work together configuring firewalls and using security related tools and distributions.

**April 25th, 2015** -- New root filesystems based on Ubuntu 15.04 available (server and lubuntu in 32 and 64 bits versions). Download it from [http://vnx.dit.upm.es/vnx/filesystems here] or using "vnx_download_rootfs" command.

**March 16th, 2015** -- Latest VNX versions include bash completion capabilities. Just use tab key to see the command line options available and help completiting option values. 

**March 6th, 2015** -- New root filesystems based on Kali 1.1.0 available (32 and 64 bits versions). Download it from [http://vnx.dit.upm.es/vnx/filesystems here] or using "vnx_download_rootfs" command. Update VNX version with 'vnx_update' command before using it.

**October 24th, 2014** -- New root filesystems based on Ubuntu 14.10 available (server and lubuntu in 32 and 64 bits versions). Download it from [http://vnx.dit.upm.es/vnx/filesystems here] or using "vnx_download_rootfs" command.

**August 27th, 2014** -- New functionality implemented to specify the position, size and desktop number where the VM console windows are shown by using .cvnx files. See more information [http://web.dit.upm.es/vnxwiki/index.php/Vnx-console-mgmt here].

**August 25th, 2014** -- VNX now supports LXC virtual machines. See the VNX tutorial for LXC [http://web.dit.upm.es/vnxwiki/index.php/Vnx-tutorial-lxc here]. Additionally, see how to [http://web.dit.upm.es/vnxwiki/index.php/Vnx-rootfslxc create] or [http://web.dit.upm.es/vnxwiki/index.php/Vnx-modify-rootfs modify] a LXC root filesystem. 

**June 27th, 2014** -- Jorge Somavilla wins the [http://www.coit.es/descargar.php?idfichero=9461 ''Asociación de Telemática'' prize from COIT-AEIT] to his [[References#Final_Degree_Projects|Final Degree Project about VNX]]. See on [https://twitter.com/jsomav/status/484039220626210816 twitter].

**June 21th, 2014** -- New root filesystem based on Kali Linux (old Backtrack) available (32 and 64 bits versions). Download it from [http://vnx.dit.upm.es/vnx/filesystems here] or using "vnx_download_rootfs" command. Use simple_kali.xml and simple_kali64.xml examples to test them (now the examples include direct Internet connection). Update VNX to latest version to use them.

**June 14th, 2014** -- Follow VNX news in twitter: https://twitter.com/vnx_upm

**June 14th, 2014** -- A Vagrant virtual machine to easily test VNX has been created. See [[Vnx-tutorial-vagrant|how to use it]] and [[Vnx-create-vagrant-vm|how it has been created]]

**October 17th, 2012** -- New root filesystem added based on [http://www.caine-live.net/ CAINE (Computer Aided INvestigative Environment)] Ubuntu distribution. Download it from [http://vnx.dit.upm.es/vnx/filesystems here] or using "vnx_download_rootfs" command. A new simple_caine.xml example has been added to latest VNX distribution to easy testing it.

**June 19th, 2012** -- A new updated Debian root filesystem has been created, as well as a new UML kernel (ver 3.3.8) to work with it. See [[Vnx-install-root_fs#UML_root_filesystems|how to download and install them]] and the recipes followed for their creation: [[Vnx-rootfsdebian|rootfs]] and [[Vnx-rootfs-uml-kernel|kernel]]. To create the kernel, the traditional UML exec extension kernel patch has been updated to work with kernel 3.3.8. You can find the new kernel patch [http://vnx.dit.upm.es/vnx/kernels/mconsole-exec-3.3.8.patch here]

**May 31th, 2012** -- New beta version of VNX (2.0b.2243) released including distributed deployment capabilities (EDIV). See the [[Docintro|documentation]] for more information.

**May 24th, 2012** -- Jorge Somavilla wins the TNC2012 student poster competition. Read the full story [http://www.terena.org/news/fullstory.php?news_id=3168 here], [http://www.rediris.es/anuncios/2012/20120525_0.html.es here] or [http://www.upm.es/institucional/UPM/CanalUPM/Noticias/2532c60f455e7310VgnVCM10000009c7648aRCRD here]