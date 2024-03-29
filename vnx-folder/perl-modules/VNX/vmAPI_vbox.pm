# vmAPI_lxc.pm
#
# This file is a module part of VNX package.
#
# Authors: David Fernández
# Coordinated by: David Fernández (david@dit.upm.es)
#
# Copyright (C) 2014   DIT-UPM
#           Departamento de Ingenieria de Sistemas Telematicos
#           Universidad Politecnica de Madrid
#           SPAIN
#           
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
# An online copy of the licence can be found at http://www.gnu.org/copyleft/gpl.html
#

package VNX::vmAPI_vbox;

use strict;
use warnings;
use Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw(
  init
  define_vm
  undefine_vm
  destroy_vm
  start_vm
  shutdown_vm
  save_vm
  restore_vm
  suspend_vm
  resume_vm
  reboot_vm
  reset_vm
  get_state_vm
  execute_cmd
  );


use Sys::Virt;
use Sys::Virt::Domain;
use VNX::Globals;
use VNX::DataHandler;
use VNX::Execution;
use VNX::BinariesData;
use VNX::CheckSemantics;
use VNX::TextManipulation;
use VNX::NetChecks;
use VNX::FileChecks;
use VNX::DocumentChecks;
use VNX::IPChecks;
use VNX::vmAPICommon;
use File::Basename;
use XML::LibXML;
use IO::Socket::UNIX qw( SOCK_STREAM );


use constant USE_UNIX_SOCKETS => 0;  # Use unix sockets (1) or TCP (0) to communicate with virtual machine 
my $lxc_dir="/var/lib/lxc";
my $union_type;

# ---------------------------------------------------------------------------------------
#
# Module vmAPI_vbox initialization code 
#
# ---------------------------------------------------------------------------------------
sub init {

    my $logp = "vbox-init> ";
    
    my $error;

    return unless ( $dh->any_vmtouse_of_type('vbox') );
    
    # Init code
    
    return $error;  
}

# ---------------------------------------------------------------------------------------
#
# define_vm
#
# Defined a virtual machine 
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine (e.g. lxc)
#   - $vm_doc: XML document describing the virtual machine in DOM tree format
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub define_vm {

    my $self    = shift;
    my $vm_name = shift;
    my $type    = shift;
    my $vm_doc  = shift;

    my $logp = "vbox-define_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);
    my $error;
    my $extConfFile;

    my $doc = $dh->get_doc;                                # scenario global doc
    my $vm = $vm_doc->findnodes("/create_conf/vm")->[0];   # VM node in $vm_doc
    my @vm_ordered = $dh->get_vm_ordered;                  # ordered list of VMs in scenario 

    my $sdisk_content;
    my $sdisk_fname_raw;
    my $sdisk_fname_vmdk;
    my $filesystem;

    wlog (VVV, "---- " . $vm->getAttribute("name"), $logp);
    wlog (VVV, "---- " . $vm->getAttribute("exec_mode"), $logp);

    my $exec_mode   = $dh->get_vm_exec_mode($vm);
    wlog (VVV, "---- vm_exec_mode = $exec_mode", $logp);

    #
    # define_vm for lxc
    #
    if  ($type eq "vbox") {

        # Check if a VBox VM with the same name is already defined
        my $vbox_dir;
        if ($uid_name eq 'root' ) {
        	$vbox_dir = '/root/VirtualBox VMs/';
        } else {
            $vbox_dir = "/home/$uid_name/VirtualBox VMs/";
        }
        if ( -d "{$vbox_dir}${vm_name}") {
            $error = "ERROR: a VirtualBox VM named $vm_name already exists. Check {$vbox_dir}${vm_name} directory content.";
            return $error;
        }

        #
        # Read VM XML specification file
        # 
#        my $parser       = XML::LibXML->new();
#        my $dom          = $parser->parse_string($vm_doc);
#        my $global_node  = $dom->getElementsByTagName("create_conf")->item(0);
#        my $vm     = $global_node->getElementsByTagName("vm")->item(0);

        my $filesystem_type   = $vm->getElementsByTagName("filesystem")->item(0)->getAttribute("type");
        my $filesystem        = $vm->getElementsByTagName("filesystem")->item(0)->getFirstChild->getData;

        
        # Register the VM
        $execution->execute( $logp, "VBoxManage createvm --name $vm_name --register" ); 
pak();        
        # memory
        my $mem = $vm->getElementsByTagName("mem")->item(0)->getFirstChild->getData;
        $mem = $mem / 1024; 
        $execution->execute( $logp, "VBoxManage modifyvm $vm_name --memory $mem" ); 
         
        # Other default parameters
        $execution->execute( $logp, "VBoxManage modifyvm $vm_name --vram 17" ); 
        $execution->execute( $logp, "VBoxManage modifyvm $vm_name --rtcuseutc on" ); 
pak();        
        # Create storage controller
        $execution->execute( $logp, "VBoxManage storagectl $vm_name --name 'SATAController' " .
                                    "--add sata --controller IntelAHCI --sataportcount 2 --hostiocache on" ); 
        
        # Attach disk to controller
        if ( $filesystem_type eq "cow" ) {
            $execution->execute( $logp, "VBoxManage storageattach $vm_name --storagectl 'SATAController' " .
                                        " --port 0 --device 0 --type hdd --medium $filesystem --mtype multiattach");
        } else {
            $execution->execute( $logp, "VBoxManage storageattach $vm_name --storagectl 'SATAController' " .
                                        " --port 0 --device 0 --type hdd --medium $filesystem --mtype normal");        	
        }
pak();

        # Create the shared filesystem 
        wlog (VVV, "vmfs_on_tmp=$vmfs_on_tmp", $logp);
        if ($vmfs_on_tmp eq 'yes') {
            $sdisk_fname_raw = $dh->get_vm_fs_dir_ontmp($vm_name) . "/sdisk.img";
            $sdisk_fname_vmdk = $dh->get_vm_fs_dir_ontmp($vm_name) . "/sdisk.vmdk";
        } else {
            $sdisk_fname_raw = $dh->get_vm_fs_dir($vm_name) . "/sdisk.img";
            $sdisk_fname_vmdk = $dh->get_vm_fs_dir($vm_name) . "/sdisk.vmdk";
        }                
        
        # qemu-img create jconfig.img 12M
        # TODO: change the fixed 50M to something configurable
        $execution->execute( $logp, $bd->get_binaries_path_ref->{"qemu-img"} . " create $sdisk_fname_raw 50M" );
pak();
        # mkfs.msdos jconfig.img
        $execution->execute( $logp, $bd->get_binaries_path_ref->{"mkfs.msdos"} . " $sdisk_fname_raw" ); 
        # Mount the shared disk to copy filetree files
        $sdisk_content = $dh->get_vm_hostfs_dir($vm_name) . "/";
        $execution->execute( $logp, $bd->get_binaries_path_ref->{"mount"} . " -o loop,uid=$uid " . $sdisk_fname_raw . " " . $sdisk_content );
        # Create filetree and config dirs in the shared disk
        $execution->execute( $logp, "mkdir -p $sdisk_content/filetree");
        $execution->execute( $logp, "mkdir -p $sdisk_content/config");          

        # Copy something to test...
        $execution->execute( $logp, $bd->get_binaries_path_ref->{"cp"} . " /etc/vnx.conf $sdisk_content/" );

        # Dismount shared disk
        # Note: under some systems this umount fails. We sleep for a while and, in case it fails, we wait and retry 3 times...
        Time::HiRes::sleep(0.2);
        my $retry=3;
        while ( $execution->execute( $logp, $bd->get_binaries_path_ref->{"umount"} . " " . $sdisk_content ) ) {
            $retry--; last if $retry == 0;  
            wlog (N, "umount $sdisk_content failed. Retrying...", "");          
            Time::HiRes::sleep(0.2);
        }

        # Convert shared disk to vmdk format
        $execution->execute( $logp, $bd->get_binaries_path_ref->{"qemu-img"} . " convert -O vmdk $sdisk_fname_raw $sdisk_fname_vmdk" );
        
        # Attach shared disk to VM
        $execution->execute( $logp, "VBoxManage storageattach $vm_name --storagectl 'SATAController' " .
                                    " --port 1 --device 0 --type hdd --medium $sdisk_fname_vmdk --mtype normal");         
pak();




#change_to_root();

=BEGIN
        # Directory where vm files are going to be mounted
        my $vm_lxc_dir;

        if ( $filesystem_type eq "cow" ) {

            # Directory where COW files are going to be stored (upper dir in terms of overlayfs) 
            my $vm_cow_dir = $dh->get_vm_fs_dir($vm_name);

            # Directory where vm overlay rootfs is going to be mounted
            $vm_lxc_dir = $dh->get_vm_dir($vm_name) . "/mnt";

            # Create the overlay filesystem
            # umount first, just in case it is mounted...
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"umount"} . " " . $vm_lxc_dir );

            if ($union_type eq 'overlayfs') {
                # Ex: mount -t overlayfs -o upperdir=/tmp/lxc1,lowerdir=/var/lib/lxc/vnx_rootfs_lxc_ubuntu-13.04-v025/ none /var/lib/lxc/lxc1
                $execution->execute( $logp, $bd->get_binaries_path_ref->{"mount"} . " -t overlayfs -o upperdir=" . $vm_cow_dir . 
                                     ",lowerdir=" . $filesystem . " none " . $vm_lxc_dir );
            } elsif ($union_type eq 'aufs') {
                # Ex: mount -t aufs -o br=/tmp/lxc1-rw:/var/lib/lxc/vnx_rootfs_lxc_ubuntu-12.04-v024/=ro none /tmp/lxc1
                $execution->execute( $logp, $bd->get_binaries_path_ref->{"mount"} . " -t aufs -o br=" . $vm_cow_dir . 
                                     ":" . $filesystem . "/=ro none " . $vm_lxc_dir );
            }
        } else {
            
            #$vm_lxc_dir = $filesystem;
            $vm_lxc_dir = $dh->get_vm_dir($vm_name) . "/mnt";
            $execution->execute( $logp, "rmdir $vm_lxc_dir" );
            $execution->execute( $logp, "ln -s $filesystem $vm_lxc_dir" );
            
        }
        
        $execution->execute( $logp, $bd->get_binaries_path_ref->{"ln"} . " -s $vm_lxc_dir $lxc_dir/$vm_name" );
        
        die "ERROR: variable vm_lxc_dir is empty" unless ($vm_lxc_dir ne '');
        my $vm_lxc_rootfs="${vm_lxc_dir}/rootfs";
        my $vm_lxc_config="${vm_lxc_dir}/config";
        my $vm_lxc_fstab="${vm_lxc_dir}/fstab";

        # Configure /etc/hostname and /etc/hosts files in VM
        # echo lxc1 > /var/lib/lxc/lxc1/rootfs/etc/hostname
        $execution->execute( $logp, "echo $vm_name > ${vm_lxc_rootfs}/etc/hostname" ); 
        # Ex: sed -i -e "s/127.0.1.1.*/127.0.1.1   lxc1/" /var/lib/lxc/lxc1/rootfs/etc/host
        $execution->execute( $logp, "sed -i -e 's/127.0.1.1.*/127.0.1.1   $vm_name/' ${vm_lxc_rootfs}/etc/hosts" ); 

        # Modify LXC VM config file
        # Backup config file just in case...
        $execution->execute( $logp, "cp $vm_lxc_config $vm_lxc_config" . ".bak" ); 

        # Delete lines with "lxc.utsname" 
        $execution->execute( $logp, "sed -i -e '/lxc.utsname/d' $vm_lxc_config" ); 
        # Delete lines with "lxc.rootfs" 
        $execution->execute( $logp, "sed -i -e '/lxc.rootfs/d' $vm_lxc_config" ); 
        # Delete lines with "lxc.fstab" 
        $execution->execute( $logp, "sed -i -e '/lxc.mount/d' $vm_lxc_config" ); 
        # Delete lines with "lxc.network" 
        $execution->execute( $logp, "sed -i -e '/lxc.network/d' $vm_lxc_config" ); 

        # Open LXC vm config file
        open CONFIG_FILE, ">> $vm_lxc_config" 
            or  $execution->smartdie("cannot open $vm_lxc_config file $!" ) 
            unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
                          
        # Set vm name: lxc.utsname = $vm_name
        $execution->execute( $logp, "", *CONFIG_FILE );
        $execution->execute( $logp, "lxc.utsname = $vm_name", *CONFIG_FILE );
        
        # Set lxc.rootfs: lxc.rootfs = $vm_lxc_dir/rootfs
        $execution->execute( $logp, "lxc.rootfs = $vm_lxc_dir/rootfs", *CONFIG_FILE );
        
        # Set lxc.mount: lxc.mount = $vm_lxc_dir/fstab
        $execution->execute( $logp, "lxc.mount = $vm_lxc_dir/fstab", *CONFIG_FILE );
=END
=cut
        
        #
        # Configure network interfaces
        #   
        # Example:
        #    # interface eth0
        #    lxc.network.type=veth
        #    # ifname inside VM
        #    lxc.network.name = eth0
        #    # ifname on the host
        #    lxc.network.veth.pair = lxc1e0
        #    lxc.network.hwaddr = 02:fd:00:04:01:00
        #    # bridge if connects to
        #    lxc.network.link=lxcbr0
        #    lxc.network.flags=up        
       
        my $mng_if_exists = 0;
        my $mng_if_mac;

        # Create vm /etc/network/interfaces file
        #my $vm_etc_net_ifs = $vm_lxc_rootfs . "/etc/network/interfaces";
        # Backup file, just in case.... 
        #$execution->execute( $logp, "cp $vm_etc_net_ifs ${vm_etc_net_ifs}.bak" );
        # Add loopback interface        
        #$execution->execute( $logp, "echo 'auto lo' > $vm_etc_net_ifs" );
        #$execution->execute( $logp, "echo 'iface lo inet loopback' >> $vm_etc_net_ifs" );

        foreach my $if ($vm->getElementsByTagName("if")) {
            my $id    = $if->getAttribute("id");
            my $net   = $if->getAttribute("net");
            my $mac   = $if->getAttribute("mac");
            $mac =~ s/,//; # TODO: why is there a comma before mac addresses?

            if ($id == 0) {

            } else {
                # Add interface to VM
                my $nic_id = $id + 1;
                $execution->execute( $logp, "VBoxManage modifyvm $vm_name --nic${nic_id} bridged --bridgeadapter${nic_id} $net" );
            }
            
        }                       

        #
        # VM autoconfiguration 
        #
        # Adapted from 'autoconfigure_ubuntu' fuction in vnxaced.pl             
        #
        # TODO: generalize to other Linux distributions

=BEGIN        
        # Files modified
        my $interfaces_file = ${vm_lxc_rootfs} . "/etc/network/interfaces";
        my $sysctl_file     = ${vm_lxc_rootfs} . "/etc/sysctl.conf";
        my $hosts_file      = ${vm_lxc_rootfs} . "/etc/hosts";
        my $hostname_file   = ${vm_lxc_rootfs} . "/etc/hostname";
        my $resolv_file     = ${vm_lxc_rootfs} . "/etc/resolv.conf";
        my $rules_file      = ${vm_lxc_rootfs} . "/etc/udev/rules.d/70-persistent-net.rules";

        # Backup and delete /etc/resolv.conf file
        system "cp $resolv_file ${resolv_file}.bak";
        system "rm -f $resolv_file";
            
        # before the loop, backup /etc/udev/...70 and /etc/network/interfaces
        # and erase their contents
        wlog (VVV, "configuring $rules_file and $interfaces_file...", $logp);
        #system "cp $rules_file $rules_file.backup";
        system "echo \"\" > $rules_file";
        open RULES, ">" . $rules_file or print "error opening $rules_file";
        system "cp $interfaces_file $interfaces_file.backup";
        system "echo \"\" > $interfaces_file";
        open INTERFACES, ">" . $interfaces_file or print "error opening $interfaces_file";
    
        print INTERFACES "\n";
        print INTERFACES "auto lo\n";
        print INTERFACES "iface lo inet loopback\n";
    
        # Network routes configuration: <route> tags
        my @ip_routes;   # Stores the route configuration lines
        foreach my $route ($vm->getElementsByTagName("route")) {
            
            my $route_type = $route->getAttribute("type");
            my $route_gw   = $route->getAttribute("gw");
            my $route_data = $route->getFirstChild->getData;
            if ($route_type eq 'ipv4') {
                if ($route_data eq 'default') {
                    push (@ip_routes, "   up route add -net default gw " . $route_gw . "\n");
                } else {
                    push (@ip_routes, "   up route add -net $route_data gw " . $route_gw . "\n");
                }
            } elsif ($route_type eq 'ipv6') {
                if ($route_data eq 'default') {
                    push (@ip_routes, "   up route -A inet6 add default gw " . $route_gw . "\n");
                } else {
                    push (@ip_routes, "   up route -A inet6 add $route_data gw " . $route_gw . "\n");
                }
            }
        }   
    
        # Network interfaces configuration: <if> tags
        foreach my $if ($vm->getElementsByTagName("if")) {
            my $id    = $if->getAttribute("id");
            my $net   = str($if->getAttribute("net"));
            my $mac   = $if->getAttribute("mac");
            $mac =~ s/,//g;
    
            my $ifName;
            # Special case: loopback interface
            if ( $net eq "lo" ) {
                $ifName = "lo:" . $id;
            } else {
                $ifName = "eth" . $id;
            }
    
            print RULES "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"?*\", ATTR{address}==\"" . $mac .  "\", ATTR{type}==\"1\", KERNEL==\"eth*\", NAME=\"" . $ifName . "\"\n\n";
            print INTERFACES "auto " . $ifName . "\n";
    
            my $ipv4_tag_list = $if->getElementsByTagName("ipv4");
            my $ipv6_tag_list = $if->getElementsByTagName("ipv6");
    
            if ( ($ipv4_tag_list->size == 0 ) && ( $ipv6_tag_list->size == 0 ) ) {
                # No addresses configured for the interface. We include the following commands to 
                # have the interface active on start
                print INTERFACES "iface " . $ifName . " inet manual\n";
                print INTERFACES "  up ifconfig " . $ifName . " 0.0.0.0 up\n";
            } else {
                # Config IPv4 addresses
                for ( my $j = 0 ; $j < $ipv4_tag_list->size ; $j++ ) {
    
                    my $ipv4_tag = $ipv4_tag_list->item($j);
                    my $mask    = $ipv4_tag->getAttribute("mask");
                    my $ip      = $ipv4_tag->getFirstChild->getData;
    
                    if ($j == 0) {
                        print INTERFACES "iface " . $ifName . " inet static\n";
                        print INTERFACES "   address " . $ip . "\n";
                        print INTERFACES "   netmask " . $mask . "\n";
                    } else {
                        print INTERFACES "   up /sbin/ifconfig " . $ifName . " inet add " . $ip . " netmask " . $mask . "\n";
                    }
                }
                # Config IPv6 addresses
                for ( my $j = 0 ; $j < $ipv6_tag_list->size ; $j++ ) {
    
                    my $ipv6_tag = $ipv6_tag_list->item($j);
                    my $ip    = $ipv6_tag->getFirstChild->getData;
                    my $mask = $ip;
                    $mask =~ s/.*\///;
                    $ip =~ s/\/.*//;
    
                    if ($j == 0) {
                        print INTERFACES "iface " . $ifName . " inet6 static\n";
                        print INTERFACES "   address " . $ip . "\n";
                        print INTERFACES "   netmask " . $mask . "\n\n";
                    } else {
                        print INTERFACES "   up /sbin/ifconfig " . $ifName . " inet6 add " . $ip . "/" . $mask . "\n";
                    }
                }
                # TODO: To simplify and avoid the problems related with some routes not being installed 
                                # due to the interfaces start order, we add all routes to all interfaces. This should be 
                                # refined to add only the routes going to each interface
                print INTERFACES @ip_routes;
    
            }
        }
            
        close RULES;
        close INTERFACES;
            
        # Packet forwarding: <forwarding> tag
        my $ipv4Forwarding = 0;
        my $ipv6Forwarding = 0;
        my $forwardingTaglist = $vm->getElementsByTagName("forwarding");
        my $numforwarding = $forwardingTaglist->size;
        for (my $j = 0 ; $j < $numforwarding ; $j++){
            my $forwardingTag   = $forwardingTaglist->item($j);
            my $forwarding_type = $forwardingTag->getAttribute("type");
            if ($forwarding_type eq "ip"){
                $ipv4Forwarding = 1;
                $ipv6Forwarding = 1;
            } elsif ($forwarding_type eq "ipv4"){
                $ipv4Forwarding = 1;
            } elsif ($forwarding_type eq "ipv6"){
                $ipv6Forwarding = 1;
            }
        }
        wlog (VVV, "configuring ipv4 ($ipv4Forwarding) and ipv6 ($ipv6Forwarding) forwarding in $sysctl_file...", $logp);
        system "echo >> $sysctl_file ";
        system "echo '# Configured by VNXACED' >> $sysctl_file ";
        system "echo 'net.ipv4.ip_forward=$ipv4Forwarding' >> $sysctl_file ";
        system "echo 'net.ipv6.conf.all.forwarding=$ipv6Forwarding' >> $sysctl_file ";
    
        # Configuring /etc/hosts and /etc/hostname
        #write_log ("   configuring $hosts_file and /etc/hostname...");
        #system "cp $hosts_file $hosts_file.backup";
    
        #/etc/hosts: insert the new first line
        #system "sed '1i\ 127.0.0.1  $vm_name    localhost.localdomain   localhost' $hosts_file > /tmp/hosts.tmp";
        #system "mv /tmp/hosts.tmp $hosts_file";
    
        #/etc/hosts: and delete the second line (former first line)
        #system "sed '2 d' $hosts_file > /tmp/hosts.tmp";
        #system "mv /tmp/hosts.tmp $hosts_file";
    
        #/etc/hosts: insert the new second line
        #system "sed '2i\ 127.0.1.1  $vm_name' $hosts_file > /tmp/hosts.tmp";
        #system "mv /tmp/hosts.tmp $hosts_file";
    
        #/etc/hosts: and delete the third line (former second line)
        #system "sed '3 d' $hosts_file > /tmp/hosts.tmp";
        #system "mv /tmp/hosts.tmp $hosts_file";
    
        #/etc/hostname: insert the new first line
        #system "sed '1i\ $vm_name' $hostname_file > /tmp/hostname.tpm";
        #system "mv /tmp/hostname.tpm $hostname_file";
    
        #/etc/hostname: and delete the second line (former first line)
        #system "sed '2 d' $hostname_file > /tmp/hostname.tpm";
        #system "mv /tmp/hostname.tpm $hostname_file";
    
        #system "hostname $vm_name";
        
        # end of vm autoconfiguration

back_to_user();     

        #
        # VM CONSOLES
        # 
        my $consFile = $dh->get_vm_dir($vm_name) . "/run/console";
        open (CONS_FILE, "> $consFile") || $execution->smartdie ("ERROR: Cannot open file $consFile");

        my @cons_list = $dh->merge_console($vm);
    
        if (scalar(@cons_list) == 0) {
            # No consoles defined; use default configuration 
            print CONS_FILE "con1=yes,lxc,$vm_name\n";
            wlog (VVV, "con1=yes,lxc,$vm_name", $logp);

        } else{
            foreach my $cons (@cons_list) {
                my $cons_id      = $cons->getAttribute("id");
                my $cons_display = $cons->getAttribute("display");
                if (empty($cons_display)) { $cons_display = 'yes'};
                my $cons_value = &text_tag($cons);

                print CONS_FILE "con${cons_id}=$cons_display,lxc,$vm_name\n";
                wlog (VVV, "con${cons_id}=$cons_display,lxc,$vm_name", $logp);

            }
        }
        close (CONS_FILE); 
=END
=cut
        return $error;

    } else {
        $error = "define_vm for type $type not implemented yet.\n";
        return $error;
    }
}

# ---------------------------------------------------------------------------------------
#
# undefine_vm
#
# Undefines a virtual machine 
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine (e.g. lxc)
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub undefine_vm {

    my $self   = shift;
    my $vm_name = shift;
    my $type   = shift;

    my $logp = "vbox-undefine_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;
    my $con;

return "not implemented yet....";

    #
    # undefine_vm for lxc
    #
    if ($type eq "vbox") {

        my $vm_lxc_dir = $dh->get_vm_dir($vm_name) . "/mnt";

        # Remove symlink to VM in /var/lib/lxc/ if existant  
        if ( -l "$lxc_dir/$vm_name") {
            #my $a = `stat -c "%d:%i" $lxc_dir/$vm_name`; my $b = `stat -c "%d:%i" $vm_lxc_dir`;
            #wlog (VVV, "a=$a, b=$b");
            if ( `stat -c "%d:%i" $lxc_dir/$vm_name` eq `stat -c "%d:%i" $vm_lxc_dir`) {
                $execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " $lxc_dir/$vm_name" );
            } else {
                $error="ERROR: a directory $lxc_dir/$vm_name exists but does not point to VM $vm_name directories. Remove it manually if not used."
            }
        } elsif ( -d "$lxc_dir/$vm_name") {
            $error="ERROR: a directory $lxc_dir/$vm_name exists but does not point to VM $vm_name directories. Remove it manually if not used."
        }

        # Umount the overlay filesystem
        $execution->execute( $logp, $bd->get_binaries_path_ref->{"umount"} . " " . $vm_lxc_dir );
        
        # Delete COW files directory
        my $vm_cow_dir = $dh->get_vm_dir($vm_name);
        $execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -rf " . $vm_cow_dir . "/fs/*" );

        return $error;
    }

    else {
        $error = "undefine_vm for type $type not implemented yet.\n";
        return $error;
    }
}

# ---------------------------------------------------------------------------------------
#
# destroy_vm
#
# Destroys a virtual machine 
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine 
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub destroy_vm {

    my $self   = shift;
    my $vm_name = shift;
    my $type   = shift;

    my $logp = "vbox-destroy_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;
    my $con;

return "not implemented yet....";
    
    
    #
    # destroy_vm for lxc
    #
    if ($type eq "vbox") {

        my $vm_lxc_dir = $dh->get_vm_dir($vm_name) . "/mnt";

        #my $a = `stat -c "%d:%i" $lxc_dir/$vm_name/`; my $b = `stat -c "%d:%i" $vm_lxc_dir/`;
        #wlog (VVV, "$lxc_dir/$vm_name/=$a, $vm_lxc_dir/=$b");
        

        $execution->execute( $logp, "vbox-kill -n $vm_name");

        # Remove symlink to VM in /var/lib/lxc/ if existant  
        if ( -l "$lxc_dir/$vm_name") {
            #my $a = `stat -c "%d:%i" $lxc_dir/$vm_name/`; my $b = `stat -c "%d:%i" $vm_lxc_dir/`;
            #wlog (VVV, "a=$a, b=$b");
            if ( `stat -c "%d:%i" $lxc_dir/$vm_name/` eq `stat -c "%d:%i" $vm_lxc_dir/`) {
                $execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " $lxc_dir/$vm_name" );
            } else {
                $error="ERROR: a directory $lxc_dir/$vm_name exists but does not point to VM $vm_name directories. Remove it manually if not used."
            }
        } elsif ( -d "$lxc_dir/$vm_name") {
            $error="ERROR: a directory $lxc_dir/$vm_name exists but does not point to VM $vm_name directories. Remove it manually if not used."
        }

        # Umount the overlay filesystem
        $execution->execute( $logp, $bd->get_binaries_path_ref->{"umount"} . " " . $vm_lxc_dir );

        # Delete COW files directory
        my $vm_cow_dir = $dh->get_vm_dir($vm_name);
        $execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -rf " . $vm_cow_dir . "/fs/*" );

        return $error;

    }
    else {
        $error = "destroy_vm for type $type not implemented yet.\n";
        return $error;
    }
}

# ---------------------------------------------------------------------------------------
#
# start_vm
#
# Starts a virtual machine already defined with define_vm
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine
#   - $no_consoles: if true, virtual machine consoles are not opened
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub start_vm {

    my $self   = shift;
    my $vm_name = shift;
    my $type   = shift;
    my $no_consoles = shift;

    my $logp = "vbox-start_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;
    my $con;
    
    #
    # start_vm for lxc
    #
    if ($type eq "vbox") {

return "not implemented yet....";



        my $vm_lxc_dir = $dh->get_vm_dir($vm_name) . "/mnt";
#pak ("before: vbox-start -n $vm_name -f $vm_lxc_dir/config");        
        my $res = $execution->execute( $logp, "vbox-start -d -n $vm_name -f $vm_lxc_dir/config");
        if ($res) { 
            wlog (N, "$res", $logp)
        }
        
        # Start the active consoles, unless options -n|--no_console were specified by the user
        unless ($no_consoles eq 1){
            Time::HiRes::sleep(0.5);
            VNX::vmAPICommon->start_consoles_from_console_file ($vm_name);
        }

# Execution of on_boot commands moved to vnx.pl

        
        # If host_mapping is in use and the vm has a management interface, 
        # then we have to add an entry for this vm in $dh->get_sim_dir/hostlines file
        if ( $dh->get_host_mapping ) {
            my @vm_ordered = $dh->get_vm_ordered;
            for ( my $i = 0 ; $i < @vm_ordered ; $i++ ) {
                my $vm = $vm_ordered[$i];
                my $name = $vm->getAttribute("name");
                unless ( $name eq $vm_name ) { next; }
                                    
                # Check whether the vm has a management interface enabled
                my $mng_if_value = &mng_if_value($vm);
                unless ( ($dh->get_vmmgmt_type eq 'none' ) || ($mng_if_value eq "no") ) {
                            
                    # Get the vm management ip address 
                    my %net = &get_admin_address( 'file', $vm_name );
                    # Add it to hostlines file
                    open HOSTLINES, ">>" . $dh->get_sim_dir . "/hostlines"
                        or $execution->smartdie("can not open $dh->get_sim_dir/hostlines\n")
                        unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
                    print HOSTLINES $net{'vm'}->addr() . " $vm_name\n";
					print HOSTLINES $net{'vm'}->addr() . " " . $etchosts_prefix . $vm_name . "\n";                    
                    close HOSTLINES;
                }               
            }
        }
        
        return $error;

    }
    else {
        $error = "Type is not yet supported\n";
        return $error;
    }
}



# ---------------------------------------------------------------------------------------
#
# shutdown_vm
#
# Shutdowns a virtual machine
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub shutdown_vm {

    my $self   = shift;
    my $vm_name = shift;
    my $type   = shift;

    my $logp = "vbox-shutdown_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;

    # Sample code
    print "Shutting down vm $vm_name of type $type\n" if ($exemode == $EXE_VERBOSE);

    #
    # shutdown_vm for lxc
    #
    if ($type eq "vbox") {
        
        my $vm_lxc_dir = $dh->get_vm_dir($vm_name) . "/mnt";
        $execution->execute( $logp, "vbox-stop -s -W -n $vm_name");

        # Remove symlink to VM in /var/lib/lxc/ if existant  
        if ( -l "$lxc_dir/$vm_name") {
            if ( `stat -c "%d:%i" $lxc_dir/$vm_name/` eq `stat -c "%d:%i" $vm_lxc_dir/`) {
                $execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " $lxc_dir/$vm_name" );
            } else {
                $error="ERROR: a directory $lxc_dir/$vm_name exists but does not point to VM $vm_name directories. Remove it manually if not used."
            }
        } elsif ( -d "$lxc_dir/$vm_name") {
            $error="ERROR: a directory $lxc_dir/$vm_name exists but does not point to VM $vm_name directories. Remove it manually if not used."
        }
        
        return $error;
    }
    else {
        $error = "Type is not yet supported\n";
        return $error;
    }
}


# ---------------------------------------------------------------------------------------
#
# save_vm
#
# Stops a virtual machine and saves its status to disk
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine
#   - $filename: the name of the file to save the VM state to
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub save_vm {

    my $self     = shift;
    my $vm_name  = shift;
    my $type     = shift;
    my $filename = shift;

    my $logp = "vbox-save_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;

return "not implemented yet....";

    # Sample code
    print "save_vm: saving vm $vm_name of type $type\n" if ($exemode == $EXE_VERBOSE);

    if ( $type eq "vbox" ) {
        return $error;

    }
}

# ---------------------------------------------------------------------------------------
#
# restore_vm
#
# Restores the status of a virtual machine from a file previously saved with save_vm
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine
#   - $filename: the name of the file with the VM state
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub restore_vm {

    my $self     = shift;
    my $vm_name   = shift;
    my $type     = shift;
    my $filename = shift;

    my $logp = "vbox-restore_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;

return "not implemented yet....";

    print
      "restore_vm: restoring vm $vm_name of type $type from file $filename\n";

    #
    # restore_vm for lxc
    #
    if ($type eq "vbox") {

        return $error;

    }
    else {
        $error = "Type is not yet supported\n";
        return $error;
    }
}

# ---------------------------------------------------------------------------------------
#
# suspend_vm
#
# Stops a virtual machine and saves its status to memory
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub suspend_vm {

    my $self   = shift;
    my $vm_name = shift;
    my $type   = shift;

    my $logp = "vbox-suspend_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;

return "not implemented yet....";

    #
    # suspend_vm for lxc
    #
    if ($type eq "vbox") {

        return $error;

    }
    else {
        $error = "Type is not yet supported\n";
        return $error;
    }
}

# ---------------------------------------------------------------------------------------
#
# resume_vm
#
# Restores the status of a virtual machine from memory (previously saved with suspend_vm)
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub resume_vm {

    my $self   = shift;
    my $vm_name = shift;
    my $type   = shift;

    my $logp = "vbox-resume_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;

return "not implemented yet....";

    # Sample code
    print "resume_vm: resuming vm $vm_name\n" if ($exemode == $EXE_VERBOSE);

    #
    # resume_vm for lxc
    #
    if ($type eq "vbox") {

        return $error;

    }
    else {
        $error = "Type is not yet supported\n";
        return $error;
    }
}

# ---------------------------------------------------------------------------------------
#
# reboot_vm
#
# Reboots a virtual machine
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub reboot_vm {

    my $self   = shift;
    my $vm_name = shift;
    my $type   = shift;

    my $logp = "vbox-reboot_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;

return "not implemented yet....";

    #
    # reboot_vm for lxc
    #
    if ($type eq "vbox") {

        return $error;

    }
    else {
        $error = "Type is not yet supported\n";
        return $error;
    }

}

# ---------------------------------------------------------------------------------------
#
# reset_vm
#
# Restores the status of a virtual machine form a file previously saved with save_vm
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub reset_vm {

    my $self   = shift;
    my $vm_name = shift;
    my $type   = shift;

    my $logp = "vbox-reset_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;

return "not implemented yet....";

    # Sample code
    print "reset_vm: reseting vm $vm_name\n" if ($exemode == $EXE_VERBOSE);

    #
    # reset_vm for lxc
    #
    if ($type eq "vbox") {

        return $error;

    }else {
        $error = "Type is not yet supported\n";
        return $error;
    }
}

# ---------------------------------------------------------------------------------------
#
# get_state_vm
#
# Returns the status of a VM from the hypervisor point of view 
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $ref_hstate: reference to a variable that will hold the state of VM as reported by the hipervisor 
#   - $ref_vstate: reference to a variable that will hold the equivalent VNX state (undefined, defined, 
#                  running, suspended, hibernated) to the state reported by the supervisor (a best effort
#                  mapping among both state spaces is done) 
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub get_state_vm {

    my $self   = shift;
    my $vm_name = shift;
    my $ref_hstate = shift;
    my $ref_vstate = shift;

    my $logp = "lxc-get_status_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name ...)", $logp);

    my $error;

    $$ref_vstate = "--";
    $$ref_hstate = "--";
    
    wlog (VVV, "state=$$ref_vstate, hstate=$$ref_hstate, error=" . str($error));
    return $error;
}

# ---------------------------------------------------------------------------------------
#
# execute_cmd
#
# Executes a set of <filetree> and <exec> commands in a virtual mchine
#
# Arguments:
#   - $vm_name: the name of the virtual machine
#   - $type: the merged type of the virtual machine (e.g. libvirt-kvm-freebsd)
#   - $seq: the sequence tag of commands to execute
#   - $vm: the virtual machine XML definition node
#   - $seq: the sequence tag of commands to execute
#   - $plugin_ftree_list_ref: a reference to an array with the plugin <filetree> commands
#   - $plugin_exec_list_ref: a reference to an array with the plugin <exec> commands
#   - $ftree_list_ref: a reference to an array with the user-defined <filetree> commands
#   - $exec_list_ref: a reference to an array with the user-defined <exec> commands
# 
# Returns:
#   - undefined or '' if no error
#   - string describing error, in case of error
#
# ---------------------------------------------------------------------------------------
sub execute_cmd {

    my $self    = shift;
    my $vm_name = shift;
    my $merged_type = shift;
    my $seq     = shift;
    my $vm      = shift;
    my $plugin_ftree_list_ref = shift;
    my $plugin_exec_list_ref  = shift;
    my $ftree_list_ref        = shift;
    my $exec_list_ref         = shift;

    my $error;

    my $logp = "vbox-execute_cmd-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$merged_type, seq=$seq ...)", $logp);

return "not implemented yet....";

    my $random_id  = &generate_random_string(6);


    if ($merged_type eq "vbox")    {
        
        my $user   = get_user_in_seq( $vm, $seq );
        # exec_mode should always be 'vbox-attach' 
        my $exec_mode   = $dh->get_vm_exec_mode($vm);
        wlog (VVV, "---- vm_exec_mode = $exec_mode", $logp);

        if ($exec_mode ne "vbox-attach") {
            return "execution mode $exec_mode not supported for VM of type $merged_type";
        }       
       
        # We create the command.xml file. It is not needed for LXC, as the commands are 
        # directly executed o the VM using vbox-attach. But we create it anyway for 
        # compatibility with other virtualization modules
        my $command_file = $dh->get_vm_dir($vm_name) . "/${vm_name}_command.xml";
        wlog (VVV, "opening file $command_file...", $logp);
        my $retry = 3;
        open COMMAND_FILE, "> $command_file" 
            or  $execution->smartdie("cannot open /command_file $!" ) 
            unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
                          
        $execution->execute( $logp, "<command>", *COMMAND_FILE );
        # Insert random id number for the command file
        my $fileid = $vm_name . "-" . &generate_random_string(6);
        $execution->execute( $logp, "<id>" . $fileid ."</id>", *COMMAND_FILE );
        my $dst_num = 1;
            
        my $vm_lxc_dir = $dh->get_vm_dir($vm_name) . "/mnt";
        my $vm_lxc_rootfs="${vm_lxc_dir}/rootfs";
        
        # Get shell to use to execute commands on the vm
        # The shell type (sh, bashc, etc) can be changed with the <shell> tag inside <vm>
        my $shell = $dh->merge_shell ($vm);
        
        #       
        # Process of <filetree> tags
        #

        # 1 - Plugins <filetree> tags
        wlog (VVV, "execute_cmd: number of plugin ftrees " . scalar(@{$plugin_ftree_list_ref}), $logp);
        
        foreach my $filetree (@{$plugin_ftree_list_ref}) {
            # Add the <filetree> tag to the command.xml file
            my $filetree_txt = $filetree->toString(1);
            $execution->execute( $logp, "$filetree_txt", *COMMAND_FILE );
            wlog (VVV, "execute_cmd: adding plugin filetree \"$filetree_txt\" to command.xml", $logp);

            my $files_dir = $dh->get_vm_tmp_dir($vm_name) . "/$seq"; 
            execute_filetree ($vm_name, $filetree, "$files_dir/filetree/$dst_num/", $shell);
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -rf $files_dir/filetree/$dst_num" );
            
            $dst_num++;          
        }
        
        # 2 - User defined <filetree> tags
        wlog (VVV, "execute_cmd: number of user defined ftrees " . scalar(@{$ftree_list_ref}), $logp);
        
        foreach my $filetree (@{$ftree_list_ref}) {
            # Add the <filetree> tag to the command.xml file
            my $filetree_txt = $filetree->toString(1);
            $execution->execute( $logp, "$filetree_txt", *COMMAND_FILE );
            wlog (VVV, "execute_cmd: adding user defined filetree \"$filetree_txt\" to command.xml", $logp);
   
            my $files_dir = $dh->get_vm_tmp_dir($vm_name) . "/$seq"; 
            execute_filetree ($vm_name, $filetree, "$files_dir/filetree/$dst_num/", $shell);
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -rf $files_dir/filetree/$dst_num" );
            
            $dst_num++;            
        }
        
        my $res=`tree $vm_lxc_rootfs/tmp`; 
        wlog (VVV, "execute_cmd: shared disk content:\n $res", $logp);

        my $command = $bd->get_binaries_path_ref->{"date"};
        chomp( my $now = `$command` );

        #       
        # Process of <exec> tags
        #
        
        # 1 - Plugins <exec> tags
        wlog (VVV, "execute_cmd: number of plugin <exec> = " . scalar(@{$plugin_ftree_list_ref}), $logp);
        
        foreach my $cmd (@{$plugin_exec_list_ref}) {
            # Add the <exec> tag to the command.xml file
            my $cmd_txt = $cmd->toString(1);
            $execution->execute( $logp, "$cmd_txt", *COMMAND_FILE );
            wlog (VVV, "execute_cmd: adding plugin exec \"$cmd_txt\" to command.xml", $logp);

            my $command = $cmd->getFirstChild->getData;
            my $vm_lxc_dir = $dh->get_vm_dir($vm_name) . "/mnt";

            #
            # We execute the command inside a shell using:
            #   sh -c 'command'
            # to avoid problems with complex commands made of several lines or including 
            # input/output redirection. We have to scape "'" inside the command changing
            # each "'" by "'\''" (see http://www.grymoire.com/Unix/Quote.html#uh-8)
            # 
            $command =~ s/'/'\\''/g;
            wlog (VVV, "shell: $shell, original command: $command, scaped command: $command", $logp);
            wlog (V, "executing user defined exec command '$command'", $logp);
            my $cmd_output = $execution->execute_getting_output( $logp, "vbox-attach -n $vm_name -- $shell -c '$command'");
            wlog (N, "$cmd_output", '') if ($cmd_output ne '');
            
        }

        # 2 - User defined <exec> tags
        wlog (VVV, "execute_cmd: number of user-defined <exec> = " . scalar(@{$ftree_list_ref}), $logp);
        
        foreach my $cmd (@{$exec_list_ref}) {
            # Add the <exec> tag to the command.xml file
            my $cmd_txt = $cmd->toString(1);
            $execution->execute( $logp, "$cmd_txt", *COMMAND_FILE );
            wlog (VVV, "execute_cmd: adding user defined exec \"$cmd_txt\" to command.xml", $logp);
            
            my $command = $cmd->getFirstChild->getData;
            my $vm_lxc_dir = $dh->get_vm_dir($vm_name) . "/mnt";
            
            #
            # We execute the command inside a shell using:
            #   sh -c 'command'
            # to avoid problems with complex commands made of several lines or including 
            # input/output redirection. We have to scape "'" inside the command changing
            # each "'" by "'\''" (see http://www.grymoire.com/Unix/Quote.html#uh-8)
            # 
            $command =~ s/'/'\\''/g;
            wlog (VVV, "shell: $shell, original command: $command, scaped command: $command", $logp);
            wlog (V, "executing user defined exec command '$command'", $logp);
            my $cmd_output = $execution->execute_getting_output( $logp, "vbox-attach -n $vm_name -- $shell -c '$command'");
            wlog (N, "$cmd_output", '') if ($cmd_output ne '');
        }

        # We close file and mark it executable
        $execution->execute( $logp, "</command>", *COMMAND_FILE );
        close COMMAND_FILE
          unless ( $execution->get_exe_mode() eq $EXE_DEBUG );

        # Print command.xml file content to log if VVV
        open FILE, "< " . $dh->get_vm_dir($vm_name) . "/${vm_name}_command.xml";
        my $cmd_file = do { local $/; <FILE> };
        close FILE;
        wlog (VVV, "command.xml file passed to vm $vm_name: \n$cmd_file", $logp);


    } 

    return $error;
}

#
# execute_filetree: adapted from the same function in vnxaced.pl
#
# Copies the files specified in a filetree tag to the virtual machine rootfs
# 
sub execute_filetree {

    my $vm_name = shift;
    my $filetree_tag = shift;
    my $source_path = shift;
    my $shell = shift;


    my $logp = "vbox-execute_filetree-$vm_name> ";

    my $seq          = str($filetree_tag->getAttribute("seq"));
    my $root         = str($filetree_tag->getAttribute("root"));
    my $user         = str($filetree_tag->getAttribute("user"));
    my $group        = str($filetree_tag->getAttribute("group"));
    my $perms        = str($filetree_tag->getAttribute("perms"));
    my $source       = str($filetree_tag->getFirstChild->getData);
    
    # Store directory where the vm rootfs is mounted
    my $vm_lxc_dir = $dh->get_vm_dir($vm_name) . "/mnt";
    my $vm_lxc_rootfs="${vm_lxc_dir}/rootfs/";
    
    # Calculate the root pathname from the host point of view: add vm rootfs location 
    # to filetree files destination ($root). We use:
    #  - $host_root for the commands executed from the host (copy commands mainly)
    #  - $root for the commands executed from inside the virtual machine (chown commands)
    my $host_root = $vm_lxc_rootfs . $root;
    
    wlog (VVV, "   processing " . $filetree_tag->toString(1), $logp ) ;
    wlog (VVV, "      seq=$seq, root=$root, user=$user, group=$group, perms=$perms, source_path=$source_path", $logp);

    my $res=`ls -R $source_path`; wlog (VVV, "filetree source files: $res", $logp);
    # Get the number of files in source dir
    my $num_files=`ls -a1 $source_path | wc -l`;
    if ($num_files < 3) { # count "." and ".."
        wlog (VVV, "   ERROR in filetree: no files to copy in $source_path (seq=$seq)\n", $logp);
        return;
    }
    # Check if files destination (root attribute) is a directory or a file
    my $cmd;
    if ( $host_root =~ /\/$/ ) {
        # Destination is a directory
        wlog (VVV, "   Destination is a directory", $logp);
        unless (-d $root){
            wlog (VVV, "   creating unexisting dir '$host_root'...", $logp);
            system "mkdir -p $root";
        }

        $cmd="cp -vR ${source_path}* $host_root";
        wlog (VVV, "   Executing '$cmd' ...", $logp);
        $res=`$cmd`;
        wlog (VVV, "Copying filetree files ($host_root):", $logp);
        wlog (VVV, "$res", $logp);

        # Change owner and permissions if specified in <filetree>
        my @files= <${source_path}*>;
        foreach my $file (@files) {
            my $fname = basename ($file);
            wlog (VVV, $file . "," . $fname, $logp);
            if ( ($user ne '') or ($group ne '')  ) {
                my $cmd="chown -R $user.$group $root/$fname"; 
                my $res = $execution->execute_getting_output( $logp, "vbox-attach -n $vm_name -- $shell -c '$cmd'");
                wlog(N, $res, $logp) if ($res ne ''); 
            }
            if ( $perms ne '' ) {
                my $cmd="chmod -R $perms $root/$fname"; 
                my $res = $execution->execute_getting_output( $logp, "vbox-attach -n $vm_name -- $shell -c '$cmd'");
                wlog(N, $res, $logp) if ($res ne ''); 
            }
        }
            
    } else {
        # Destination is a file
        # Check that $source_path contains only one file
        wlog (VVV, "   Destination is a file", $logp);
        wlog (VVV, "       source_path=${source_path}", $logp);
        wlog (VVV, "       root=${root}", $logp);
        if ($num_files > 3) { # count "." and ".."
            wlog (N, "   ERROR in filetree: destination ($root) is a file and there is more than one file in $source_path (seq=$seq)\n", $logp);
            next;
        }
        my $file_dir = dirname($root);
        unless (-d $file_dir){
            wlog (VVV, "   creating unexisting dir '$file_dir'...", $logp);
            system "mkdir -p $file_dir";
        }
        $cmd="cp -v ${source_path}* $host_root";
        wlog (VVV, "   Executing '$cmd' ...", $logp);
        $res=`$cmd`;
        wlog (VVV, "Copying filetree file ($host_root):", $logp);
        wlog (VVV, "$res", $logp);
        # Change owner and permissions of file $root if specified in <filetree>
        if ( ($user ne '') or ($group ne '') ) {
            $cmd="chown -R $user.$group $root"; 
            my $res = $execution->execute_getting_output( $logp, "vbox-attach -n $vm_name -- $shell -c '$cmd'");
            wlog(N, $res, $logp) if ($res ne ''); 
        }
        if ( $perms ne '' ) {
            $cmd="chmod -R $perms $root";
            my $res = $execution->execute_getting_output( $logp, "vbox-attach -n $vm_name -- $shell -c '$cmd'");
            wlog(N, $res, $logp) if ($res ne ''); 
        }
    }
}



###################################################################
#
sub get_user_in_seq {

    my $vm  = shift;
    my $seq = shift;

    my $username = "";

    # Looking for in <exec>
    #my $exec_list = $vm->getElementsByTagName("exec");
    #for ( my $i = 0 ; $i < $exec_list->getLength ; $i++ ) {
    foreach my $exec ($vm->getElementsByTagName("exec")) {
        if ( $exec->getAttribute("seq") eq $seq ) {
            #if ( $exec->getAttribute("user") ne "" ) {
            unless ( empty($exec->getAttribute("user")) ) {
                $username = $exec->getAttribute("user");
                last;
            }
        }
    }

    # If not found in <exec>, try with <filetree>
    if ( $username eq "" ) {
        #my $filetree_list = $vm->getElementsByTagName("filetree");
        #for ( my $i = 0 ; $i < $filetree_list->getLength ; $i++ ) {
        foreach my $filetree ($vm->getElementsByTagName("filetree")) {
            if ( $filetree->getAttribute("seq") eq $seq ) {
                #if ( $filetree->getAttribute("user") ne "" ) {
                unless ( empty($filetree->getAttribute("user")) ) {
                    $username = $filetree->getAttribute("user");
                    last;
                }
            }
        }
    }

    # If no mode was found in <exec> or <filetree>, use default
    if ( $username eq "" ) {
        $username = "root";
    }

    return $username;

}



###################################################################
# save_dir_permissions
#
# Argument:
# - a directory in the host enviroment in which the permissions
#   of the files will be saved
#
# Returns:
# - a hash with the permissions (a 3-character string with an octal
#   representation). The key of the hash is the file name
#
sub save_dir_permissions {

    my $dir = shift;

    my @files = &get_directory_files($dir);
    my %file_perms;

    foreach (@files) {

        # The directory itself is ignored
        unless ( $_ eq $dir ) {

# Tip from: http://open.itworld.com/5040/nls_unix_fileattributes_060309/page_1.html
            my $mode = ( stat($_) )[2];
            $file_perms{$_} = sprintf( "%04o", $mode & 07777 );

            #print "DEBUG: save_dir_permissions $_: " . $file_perms{$_} . "\n";
        }
    }

    return %file_perms;
}



###################################################################
# get_directory_files
#
# Argument:
# - a directory in the host enviroment
#
# Returns:
# - a list with all files in the given directory
#
sub get_directory_files {

    my $dir = shift;

    # FIXME: the current implementation is based on invoking find shell
    # command. Maybe there are smarter ways of doing the same
    # just with Perl commands. This would remove the need of "find"
    # in @binaries_mandatory in BinariesData.pm

    my $command = $bd->get_binaries_path_ref->{"find"} . " $dir";
    my $out     = `$command`;
    my @files   = split( /\n/, $out );

    return @files;
}



###################################################################
# Wait for a filetree end file (see conf_files function)
sub filetree_wait {
    my $file = shift;

    do {
        if ( -f $file ) {
            return 1;
        }
        sleep 1;
    } while (1);
    return 0;
}

1;

