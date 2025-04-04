# vmAPI_lxc.pm
#
# This file is a module part of VNX package.
#
# Authors: David Fernández
# Coordinated by: David Fernández (david.fernandez@upm.es)
#
# Copyright (C) 2022   DIT-UPM
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

package VNX::vmAPI_lxc;

use strict;
use warnings;
use Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw(
  init
  define_vm
  undefine_vm
  start_vm
  shutdown_vm
  suspend_vm
  resume_vm
  save_vm
  restore_vm
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
use Cwd qw(abs_path);
use Data::Dumper;

my $lxc_dir="/var/lib/lxc";
# LXC config options 
my $union_type;
my $aa_unconfined;
my $aufs_options;
my $nested_lxc;
my $overlayfs_workdir_option;
my $overlayfs_name = 'overlayfs';   # Should be 'overlay' for Fedora and CentOS, 'overlayfs' for the rest


# ---------------------------------------------------------------------------------------
#
# Module vmAPI_lxc initialization code 
#
# ---------------------------------------------------------------------------------------
sub init {

    my $logp = "lxc-init> ";
    #my $error;
    
    return unless ( $dh->any_vmtouse_of_type('lxc') );
    
    $union_type = get_conf_value ($vnxConfigFile, 'lxc', 'union_type', 'root');
    if (empty($union_type)) {
        $union_type = 'overlayfs'; # default value
    } elsif ( ($union_type ne 'overlayfs') && ($union_type ne 'aufs') ){
        return "in $vnxConfigFile, incorrect value ($union_type) assigned to 'union_type' \nparameter in [lxc] section (should be overlayfs or aufs).";
    }
    wlog (VVV, "[lxc] conf: union_type=$union_type");

    # check if the overlay type is supported by the system
    if ($union_type eq 'overlayfs') {

		system( "modprobe overlay > /dev/null 2>&1" );
		if ( $? == 0 ) {
		    $overlayfs_name = 'overlay';
		} else {
		    system( "modprobe overlayfs > /dev/null 2>&1" );
		    if ( $? == 0 ) {
		        $overlayfs_name = 'overlayfs';
		    } else {
            	return "overlayfs filesystems not supported in this system."
		    }
		}
    	wlog (VVV, "[lxc] conf: overlayfs_name = $overlayfs_name");


        #if ( ($os_id eq 'fedora' or $os_id eq 'centos') ||
        #   ($os_id eq 'ubuntu' and $os_ver_id >= 16.10 ) ||
        #   ($os_id eq 'kali' and $os_ver_id >= 2016.2 ) ) {
        #    system( "modprobe overlay" );
        #    $overlayfs_name = 'overlay';
        #} else  {
        #    system( "modprobe overlayfs" );
        #}
        #if ( $? != 0 ) {
        #    return "overlayfs filesystems not supported in this system."
        #}
    } elsif ($union_type eq 'aufs') {
        system( "modprobe aufs" );
        if ( $? != 0 ) {
            return "aufs filesystems not supported in this system."
        }
    }

    $aa_unconfined = get_conf_value ($vnxConfigFile, 'lxc', 'aa_unconfined', 'root');
    if (empty($aa_unconfined)) {
        $aa_unconfined = 'no'; # default value
    } elsif ( ($aa_unconfined ne 'yes') && ($aa_unconfined ne 'no') ){
        return "in $vnxConfigFile, incorrect value ($aa_unconfined) assigned to 'aa_unconfined' \nparameter in [lxc] section (should be yes or no).";
    }
    wlog (VVV, "[lxc] conf: aa_unconfined=$aa_unconfined");

    $aufs_options = get_conf_value ($vnxConfigFile, 'lxc', 'aufs_options', 'root');
    if (empty($aufs_options)) {
        $aufs_options = ''; # default value
    } else {
        $aufs_options .= ','; # default value
    }
    wlog (VVV, "[lxc] conf: aufs_options=$aufs_options");

    $nested_lxc = get_conf_value ($vnxConfigFile, 'lxc', 'nested_lxc', 'root');
    if (empty($nested_lxc)) {
        $nested_lxc = 'no'; # default value
    } elsif ( ($nested_lxc ne 'yes') && ($nested_lxc ne 'no') ){
        return "in $vnxConfigFile, incorrect value ($nested_lxc) assigned to 'nested_lxc' \nparameter in [lxc] section (should be yes or no).";
    }
    if ( ($nested_lxc eq 'yes') && ($aa_unconfined eq 'yes') ){
        return "in $vnxConfigFile, cannot activate 'nested_lxc=yes' and 'aa_unconfined=yes' simultaneously. Only one of the two parameters can be set to yes.";
    }
    # nested_lxc option does not work as the apparmor profilo does not load in new linux versions. Disabled by now
    #if ( ($nested_lxc eq 'yes') ){
    #    wlog (N, "  WARNING: nested_lxc=yes option in /etc/vnx.conf does not work in recent linux versions. Disabled");
    #    $nested_lxc = 'no'; # default value
    #}
    wlog (VVV, "[lxc] conf: nested_lxc=$nested_lxc");

    $overlayfs_workdir_option = get_conf_value ($vnxConfigFile, 'lxc', 'overlayfs_workdir_option', 'root');
    if (empty($overlayfs_workdir_option)) {
        $overlayfs_workdir_option = 'no'; # default value
    } elsif ( ($overlayfs_workdir_option ne 'yes') && ($overlayfs_workdir_option ne 'no') ){
        return "in $vnxConfigFile, incorrect value ($overlayfs_workdir_option) assigned to '$overlayfs_workdir_option' \nparameter in [lxc] section (should be yes or no).";
    }
    wlog (VVV, "[lxc] conf: $overlayfs_workdir_option=$overlayfs_workdir_option");

    # Check whether LXC is installed (by executing lxc-info)
    system("which lxc-info > /dev/null 2>&1");
    if ( $? != 0 ) {
    	return "Cannot find 'lxc-info' command, check that LXC is installed in the system.";
    }
}

# ---------------------------------------------------------------------------------------
#
# define_vm
#
# Defines a LXC virtual machine
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

    my $logp = "lxc-define_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);
    my $error;
    my $extConfFile;

    my $doc = $dh->get_doc;                                # scenario global doc
    my $vm = $vm_doc->findnodes("/create_conf/vm")->[0];   # VM node in $vm_doc
    my @vm_ordered = $dh->get_vm_ordered;                  # ordered list of VMs in scenario 

    my $filesystem;

    my $exec_mode   = $dh->get_vm_exec_mode($vm);
    my $vm_arch = $vm->getAttribute("arch");
    if (empty($vm_arch)) { $vm_arch = 'i686' }  # default value

    # Get cgroups version
    my $cgr_vers = "cgroup";
    my $exit_code=system("mount | grep ^cgroup2 > /dev/null 2>&1");
    if($exit_code==0) {
        $cgr_vers = "cgroup2";
    }
    wlog (V, "Cgroup version: $cgr_vers", $logp);

    #
    # define_vm for lxc
    #
    if  ($type eq "lxc") {
    	    	
        # Check if an LXC VM with the same name is already defined
        if ( -l "$lxc_dir/$vm_name") {
        	# Check if the link points to an existing directory. If not, just delete it and continue
            my $dir = `readlink -e $lxc_dir/$vm_name`; chomp($dir);
            #print "dir=$dir\n";
            if ( $? == 0 ) { 
                # Link point to an existing directory. Check if it is a subdirectory of $vnx_dir
                if (index($dir, $vnx_dir) != -1) {
                    # Get the scenario name
                    my $sname = $dir;
                    $sname =~ s#^$vnx_dir/scenarios/##;
                    $sname =~ s#/.*##; chomp($sname);
                    #print "sname=$sname\n";
                    $error="A LXC vm named '$vm_name' already exists (vm names must be unique along the system).\n" .
                           "That vm seems to belong to VNX scenario '$sname'.\n" .
                           "If you are sure it is not being used, you can destroy it with:\n" .
                           "    sudo vnx -s $sname --destroy\n" .
                           "Or, alternatively, completely restart VNX host with:\n" .
                           "    sudo vnx --clean-host\n" .
                           "WARNING: the option --clean-host destroys all libvirt virtual machines (even the ones \n" .
                           "         not started by VNX) and all the containers created by VNX.";
        	} else {
                    $error="A LXC vm named '$vm_name' already exists (vm names must be unique along the system).\n" .
                           "The link '$lxc_dir/$vm_name' points to '$dir'. Check the state of the vm with:\n" .
                           "    sudo lxc-info -n $vm_name\n" .
                           "If you are pretty sure that vm '$vm_name' is not being used, just delete the faulty link with:\n" .
                           "    sudo rm $lxc_dir/$vm_name";
                }
                $execution->smartdie("$error\n")
            } else {
                # Does not point to an existing directory. Just delete the link:
change_to_root();
                $execution->execute( $logp, "rm -v $lxc_dir/$vm_name" );
back_to_user();     
        	}
        } elsif ( -d "$lxc_dir/$vm_name") {
            # It is a directory
            $error="A LXC vm named '$vm_name' already exists (vm names must be unique along the system).\n" .
                   "Stop and delete that vm before starting this scenario. Check its state with:\n" .
                   "    sudo lxc-info -n $vm_name\n" .
                   "If you are pretty sure that the vm is not being used and it is not started, you can\n" .
                   "just delete the directory with:\n" .
                   "    sudo rm -rf $lxc_dir/$vm_name";
            $execution->smartdie("$error\n")
        }

        my $filesystem_type   = $vm->getElementsByTagName("filesystem")->item(0)->getAttribute("type");
        my $filesystem        = $vm->getElementsByTagName("filesystem")->item(0)->getFirstChild->getData;


        # Directory where vm files are going to be mounted
        my $vm_lxc_dir;

        if ( $filesystem_type eq "cow" ) {

            # Directory where COW files are going to be stored (upper dir in terms of overlayfs) 
            my $vm_cow_dir = $dh->get_vm_fs_dir($vm_name);

            # Directory where vm overlay rootfs is going to be mounted
            $vm_lxc_dir = $dh->get_vm_dir($vm_name) . "/mnt";
            
            # workdir directory needed by overlayfs in new kernels
            my $workdir = '';
            if ($overlayfs_workdir_option eq 'yes') {
                $workdir = $dh->get_vm_dir($vm_name) . "/tmp/workdir";
                $execution->execute( $logp, "mkdir -p $workdir" );
                $workdir = ",workdir=$workdir";
            }
        
            # Create the overlay filesystem
            # umount first, just in case it is mounted...
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"umount"} . " " . $vm_lxc_dir );


            if ($union_type eq 'overlayfs') {
                # Ex: mount -t overlayfs -o upperdir=/tmp/lxc1,lowerdir=/var/lib/lxc/vnx_rootfs_lxc_ubuntu-13.04-v025/ none /var/lib/lxc/lxc1
                $execution->execute( $logp, $bd->get_binaries_path_ref->{"mount"} . " -t $overlayfs_name -o upperdir=" . $vm_cow_dir . 
                                     ",lowerdir=" . $filesystem . $workdir . " none " . $vm_lxc_dir );
            } elsif ($union_type eq 'aufs') {
                # Ex: mount -t aufs -o br=/tmp/lxc1-rw:/var/lib/lxc/vnx_rootfs_lxc_ubuntu-12.04-v024/=ro none /tmp/lxc1
                $execution->execute( $logp, $bd->get_binaries_path_ref->{"mount"} . " -t aufs -o ${aufs_options}br=" . $vm_cow_dir . 
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

        # Variables pointing to rootfs directory and config and fstab files
        my $vm_lxc_rootfs="${vm_lxc_dir}/rootfs";
        my $vm_lxc_config="${vm_lxc_dir}/config";
        my $vm_lxc_fstab="${vm_lxc_dir}/fstab";
        
        #
        # Guess image OS distro
        #
        my $rootfs_mount_dir = $vm_lxc_rootfs;
        my $get_os_distro_code = get_code_of_get_os_distro();

        # Big danger if rootfs mount directory ($rootfs_mount_dir) is empty: 
        # host files will be modified instead of rootfs image ones
        unless ( defined($rootfs_mount_dir) && $rootfs_mount_dir ne '' && $rootfs_mount_dir ne '/' ) {
            die;
        }

        # First, copy "get_os_distro" script to /tmp on image
        my $get_os_distro_file = "$rootfs_mount_dir/tmp/get_os_distro"; 
        open (GETOSDISTROFILE, "> $get_os_distro_file"); # or vnx_die ("cannot open file $get_os_distro_file");
        print GETOSDISTROFILE "$get_os_distro_code";
        close (GETOSDISTROFILE); 
        
        system "chmod +x $rootfs_mount_dir/tmp/get_os_distro";
        
        # Second, execute the script chrooted to the image
        my $os_distro = `LANG=C chroot $rootfs_mount_dir perl /tmp/get_os_distro`;
        my @platform = split(/,/, $os_distro);

        # Check consistency of VM definition and hardware platform 
        # We cannot use the information returned by get_os_distro ($platform[5]) because as it is executed 
        # using chroot and returns the host info, not the rootfs image. We use the command file instead
        my $rootfs_arch;
        if    ( `file $rootfs_mount_dir/bin/bash | grep 32-bit` ) { $rootfs_arch = 'i686' }
        elsif ( `file $rootfs_mount_dir/bin/bash | grep 64-bit` ) { $rootfs_arch = 'x86_64' }

        wlog (V, "Image OS detected: $platform[0],$platform[1],$platform[2],$platform[3]," . str($rootfs_arch), $logp);

        if ( defined($rootfs_arch) && $vm_arch ne $rootfs_arch ) {
            # Delete script, dismount the rootfs image and return error        
            system "rm $rootfs_mount_dir/tmp/get_os_distro";
            $execution->execute($logp, $bd->get_binaries_path_ref->{"vnx_mount_rootfs"} . " -b -u $rootfs_mount_dir");
            #system "vnx_mount_rootfs -b -u $rootfs_mount_dir";
            return "Inconsistency detected between VM $vm_name architecture defined in XML ($vm_arch) and rootfs architecture ($rootfs_arch)";
        } 
        
        # Third, delete the script
        system "rm $rootfs_mount_dir/tmp/get_os_distro";
        
        #
        # Root filesystem configuration
        #
        # Configure /etc/hostname and /etc/hosts files in VM
        # echo lxc1 > /var/lib/lxc/lxc1/rootfs/etc/hostname
        $execution->execute( $logp, "echo $vm_name > ${vm_lxc_rootfs}/etc/hostname" ); 
        # Ex: sed -i -e "s/127.0.1.1.*/127.0.1.1   lxc1/" /var/lib/lxc/lxc1/rootfs/etc/host
        $execution->execute( $logp, "sed -i -e 's/127.0.1.1.*/127.0.1.1   $vm_name/' ${vm_lxc_rootfs}/etc/hosts" ); 
        # Copy SSH keys if <ssh> tag specified in scenario
        #if( $vm_doc->exists("/create_conf/vm/ssh_key") ){
        #    my @ssh_key_list = $vm_doc->findnodes('/create_conf/vm/ssh_key');
            # Copy ssh key files content to $ssh_key_dir/ssh_keys file
            #foreach my $ssh_key (@ssh_key_list) {
            foreach my $ssh_key ($vm_doc->findnodes('/create_conf/vm/ssh_key')) {
                my $key_file = do_path_expansion( text_tag( $ssh_key ) );
                wlog (V, "<ssh_key> file: $key_file (" . text_tag($ssh_key) . ")");
                $execution->execute( $logp, "mkdir -p ${vm_lxc_rootfs}/root/.ssh/" );
                if (-e $key_file) {
                    $execution->execute( $logp, $bd->get_binaries_path_ref->{"cat"}
                                         . " $key_file >>" . "${vm_lxc_rootfs}/root/.ssh/authorized_keys" );
                } else {
                	wlog (N, "$hline\nWARNING: ssh key '$key_file' does not exist or is not readable.\n$hline")
                }
            }
        #}
        # Modify LXC VM config file
        # Backup config file just in case...
        $execution->execute( $logp, "cp $vm_lxc_config $vm_lxc_config" . ".bak" );

        # Check lxc version to adapt the config file if needed
        # See config file format differences here: https://discuss.linuxcontainers.org/t/lxc-2-1-has-been-released/487
        my $lxc_vers = `lxc-start --version`; chomp($lxc_vers);
		my $exit = system("grep -q lxc.rootfs.path $vm_lxc_config");
		my $lxc_configfile_vers;
		if ($exit) { $lxc_configfile_vers = 'old' } else { $lxc_configfile_vers = 'new' }
        wlog (V, "LXC config file version: $lxc_configfile_vers", $logp);

		my $lxc_format;

        if ( $lxc_vers =~ /^2\.1/ or $lxc_vers =~ /^3\./ or $lxc_vers =~ /^4\./ or
             $lxc_vers =~ /^5\./ or $lxc_vers =~ /^6\./ ) {
        	$lxc_format = 'new';
			if ( $lxc_configfile_vers eq 'old' ) {
        		wlog (V, "LXC config file in old format. Converting to new format.", $logp);
		        my $res = $execution->execute( $logp, "vnx_convert_lxc_config -q -n $vm_lxc_config" );
			}
        } else {
        	$lxc_format = 'old';
			if ( $lxc_configfile_vers eq 'new' ) {
        		wlog (V, "LXC config file in new format. Converting to old format.", $logp);
		        my $res = $execution->execute( $logp, "vnx_convert_lxc_config -q -o $vm_lxc_config" );
			}
        }
        if ( $lxc_vers =~ /^3\./ or $lxc_vers =~ /^4\./ or $lxc_vers =~ /^5\./) {
			system ("sed -i -e 's/ubuntu.common.conf/common.conf/' $vm_lxc_config");        
        }
        wlog (V, "LXC version: $lxc_vers ($lxc_format format)", $logp);

		if ($lxc_format eq 'new') {

	        # Delete lines with "lxc.utsname" 
	        $execution->execute( $logp, "sed -i -e '/lxc\.uts\.name/d' $vm_lxc_config" ); 
	        # Delete lines with "lxc.rootfs" 
	        $execution->execute( $logp, "sed -i -e '/lxc\.rootfs\.path/d' $vm_lxc_config" ); 
	        # Delete lines with "lxc.fstab" 
	        #$execution->execute( $logp, "sed -i -e '/lxc\.mount/d' $vm_lxc_config" ); 
	        $execution->execute( $logp, "sed -i -e '/lxc\.mount\.fstab/d' $vm_lxc_config" ); 
	        
	        # Delete lines with "lxc.network" 
	        $execution->execute( $logp, "sed -i -e '/lxc\.net\./d' $vm_lxc_config" ); 
	
	        # Open LXC vm config file
	        open CONFIG_FILE, ">> $vm_lxc_config" 
	            or  $execution->smartdie("cannot open $vm_lxc_config file $!" ) 
	            unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
	                          
	        # Set vm name: lxc.utsname = $vm_name
	        $execution->execute( $logp, "", *CONFIG_FILE );
	        $execution->execute( $logp, "lxc.uts.name = $vm_name", *CONFIG_FILE );
	        
	        # Set lxc.rootfs: lxc.rootfs = $vm_lxc_dir/rootfs
	        $execution->execute( $logp, "lxc.rootfs.path = $vm_lxc_dir/rootfs", *CONFIG_FILE );
	        
	        # Create lxc.mount.entry's for shared directories
	        foreach my $shared_dir ($vm->getElementsByTagName("shareddir")) {
	            my $root    = $shared_dir->getAttribute("root");
	            my $options = $shared_dir->getAttribute("options");
	            if ($options) { $options .= ',bind' } else { $options = 'bind' };
	            my $shared_dir_value = text_tag($shared_dir);
	            $shared_dir_value = get_abs_path($shared_dir_value);
	#            if (! -d $shared_dir_value) {
	#            	$execution->execute( $logp, "mkdir -p $shared_dir_value" );
	#            }            
	            $root = $vm_lxc_rootfs . "/" . $root;
	            if (! -d $root) {
	                $execution->execute( $logp, "mkdir -p $root" );
	            }            
	            $execution->execute( $logp, "lxc.mount.entry = $shared_dir_value $root none $options 0 0", *CONFIG_FILE );
	        }
	        
	        unless ($platform[0] eq 'Linux' && ( $platform[1] eq 'Debian') || ( $platform[1] eq 'Debian-VyOS') ) {
		        # Set lxc.mount: lxc.mount = $vm_lxc_dir/fstab
		        $execution->execute( $logp, "lxc.mount.fstab = $vm_lxc_dir/fstab", *CONFIG_FILE );
		        $execution->execute( $logp, "touch $vm_lxc_dir/fstab" ) unless (-f "$vm_lxc_dir/fstab");
	        }
	
	        # Configure CPU related attributes
	        my $vcpu = $vm->getAttribute("vcpu");
	        if (defined($vcpu) and $vcpu ne '') {
	            $execution->execute( $logp, "lxc.$cgr_vers.cpuset.cpus = $vcpu", *CONFIG_FILE );
	        }        
	        my $vcpu_quota = $vm->getAttribute("vcpu_quota");
	        if (defined($vcpu_quota)) {
	        	my $PERIOD = 50000;
	        	$vcpu_quota =~ s/%//;
	            $execution->execute( $logp, "lxc.$cgr_vers.cpu.cfs_quota_us = " . int($PERIOD*$vcpu_quota/100), *CONFIG_FILE );
	            $execution->execute( $logp, "lxc.$cgr_vers.cpu.cfs_period_us = $PERIOD", *CONFIG_FILE );
	        }        
	        
	        # Configure Memory
	        if( $vm->exists("/create_conf/vm/mem") ){
	            my $mem = $vm->findnodes("/create_conf/vm/mem")->[0]->getFirstChild->getData;
	            $mem = $mem/1024;
	            $execution->execute( $logp, "memory.limit_in_bytes = ${mem}M", *CONFIG_FILE );
	            # Ex: lxc.$cgr_vers.memory.limit_in_bytes = 256M        
	        }        
	        
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
	            my $id       = $if->getAttribute("id");
	            my $net      = $if->getAttribute("net");
	            my $net_type = $dh->get_net_type($net);
	            my $net_mode = $dh->get_net_mode($net);
	            my $mac      = $if->getAttribute("mac");
	            $mac =~ s/,//; # TODO: why is there a comma before mac addresses?
	
	            if ( str($net) eq "lo" ) { next }
	            $execution->execute( $logp, "", *CONFIG_FILE );
	            $execution->execute( $logp, "# interface eth$id", *CONFIG_FILE );
	
	            if ( $net_mode eq "veth") {
		            $execution->execute( $logp, "lxc.net.$id.type=phys", *CONFIG_FILE );
	            } else {
		            $execution->execute( $logp, "lxc.net.$id.type=veth", *CONFIG_FILE );
		            $execution->execute( $logp, "# ifname on the host", *CONFIG_FILE );
		            $execution->execute( $logp, "lxc.net.$id.veth.pair=$vm_name-e$id", *CONFIG_FILE );              
	            }
		        $execution->execute( $logp, "# ifname inside VM", *CONFIG_FILE );
		        $execution->execute( $logp, "lxc.net.$id.name=eth$id", *CONFIG_FILE );
	
	            $execution->execute( $logp, "# if mac address", *CONFIG_FILE );
	            $execution->execute( $logp, "lxc.net.$id.hwaddr=$mac", *CONFIG_FILE );
	            if ($id != 0) {
	            	if ($net_mode eq "virtual_bridge" and $net ne 'unconnected') {
		                $execution->execute( $logp, "# name of bridge interface connects to", *CONFIG_FILE );
		                $execution->execute( $logp, "lxc.net.$id.link=$net", *CONFIG_FILE );
	            	} elsif ($net_mode eq "veth") {
	                    $execution->execute( $logp, "# veth link endpoint name", *CONFIG_FILE );
	                    $execution->execute( $logp, "lxc.net.$id.link=${net}_${vm_name}", *CONFIG_FILE );            		
	            	}
	            } 
	#            else {
	#
	#                my $ipv4_tag = $if->getElementsByTagName("ipv4")->item(0);
	#                my $mask    = $ipv4_tag->getAttribute("mask");
	#                my $ip      = $ipv4_tag->getFirstChild->getData;
	#
	#                my $ip_addr = NetAddr::IP->new($ip, $mask);
	#	            $execution->execute( $logp, "lxc.network.ipv4=" . $ip_addr->cidr(), *CONFIG_FILE );
	#            }
	            
	            $execution->execute( $logp, "lxc.net.$id.flags=up", *CONFIG_FILE );
	
	            #
	            # Add interface to /etc/network/interfaces
	            #
	            #$execution->execute( $logp, "echo 'iface lo inet loopback' >> $vm_etc_net_ifs" );
	
	        }                       
	
	        # Change to unconfined mode to avoid problems with apparmor if configured in /etc/vnx.conf
	        if ( $aa_unconfined eq 'yes' ){
		        $execution->execute( $logp, "", *CONFIG_FILE );
		        $execution->execute( $logp, "# Set unconfined to avoid problems with apparmor", *CONFIG_FILE );
		        $execution->execute( $logp, "lxc.apparmor.profile =unconfined", *CONFIG_FILE );
	            $execution->execute( $logp, "lxc.$cgr_vers.devices.allow = b 7:* rwm", *CONFIG_FILE );
	            $execution->execute( $logp, "lxc.$cgr_vers.devices.allow = c 10:237 rwm", *CONFIG_FILE );
	        }
	        
	        if ($nested_lxc eq 'yes') {
		        $execution->execute( $logp, "lxc.mount.auto = $cgr_vers", *CONFIG_FILE );        
		        #$execution->execute( $logp, "lxc.aa_profile=lxc-container-default-with-nesting", *CONFIG_FILE );        
		        $execution->execute( $logp, "lxc.apparmor.profile=lxc-container-default-with-netns", *CONFIG_FILE );        
	        }
	
			# Allow access to /dev/net/tun
            $execution->execute( $logp, "lxc.$cgr_vers.devices.allow = c 10:200 rwm", *CONFIG_FILE );		
	
	        close CONFIG_FILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );

			# End of new format configuration
			
		} else {
			
	        # Delete lines with "lxc.utsname" 
	        $execution->execute( $logp, "sed -i -e '/lxc\.utsname/d' $vm_lxc_config" ); 
	        # Delete lines with "lxc.rootfs" 
	        $execution->execute( $logp, "sed -i -e '/lxc\.rootfs/d' $vm_lxc_config" ); 
	        # Delete lines with "lxc.mount...fstab" 
	        $execution->execute( $logp, "sed -i -e '/lxc\.mount.*fstab/d' $vm_lxc_config" ); 
	        # Delete lines with "lxc.network" 
	        $execution->execute( $logp, "sed -i -e '/lxc\.network/d' $vm_lxc_config" ); 
	
	        # Open LXC vm config file
	        open CONFIG_FILE, ">> $vm_lxc_config" 
	            or  $execution->smartdie("cannot open $vm_lxc_config file $!" ) 
	            unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
	                          
	        # Set vm name: lxc.utsname = $vm_name
	        $execution->execute( $logp, "", *CONFIG_FILE );
	        $execution->execute( $logp, "lxc.utsname = $vm_name", *CONFIG_FILE );
	        
	        # Set lxc.rootfs: lxc.rootfs = $vm_lxc_dir/rootfs
	        $execution->execute( $logp, "lxc.rootfs = $vm_lxc_dir/rootfs", *CONFIG_FILE );
	        
	        # Create lxc.mount.entry's for shared directories
	        foreach my $shared_dir ($vm->getElementsByTagName("shareddir")) {
	            my $root    = $shared_dir->getAttribute("root");
	            my $options = $shared_dir->getAttribute("options");
	            if ($options) { $options .= ',bind' } else { $options = 'bind' };
	            my $shared_dir_value = text_tag($shared_dir);
	            $shared_dir_value = get_abs_path($shared_dir_value);
	#            if (! -d $shared_dir_value) {
	#            	$execution->execute( $logp, "mkdir -p $shared_dir_value" );
	#            }            
	            $root = $vm_lxc_rootfs . "/" . $root;
	            if (! -d $root) {
	                $execution->execute( $logp, "mkdir -p $root" );
	            }            
	            $execution->execute( $logp, "lxc.mount.entry = $shared_dir_value $root none $options 0 0", *CONFIG_FILE );
	        }
	        
	        unless ($platform[0] eq 'Linux' && ( $platform[1] eq 'Debian') || ( $platform[1] eq 'Debian-VyOS') ) {
		        # Set lxc.mount: lxc.mount = $vm_lxc_dir/fstab
		        $execution->execute( $logp, "lxc.mount = $vm_lxc_dir/fstab", *CONFIG_FILE );
		        $execution->execute( $logp, "touch $vm_lxc_dir/fstab" ) unless (-f "$vm_lxc_dir/fstab");		        
	        }
	        
	
	        # Configure CPU related attributes
	        my $vcpu = $vm->getAttribute("vcpu");
	        if (defined($vcpu) and $vcpu ne '') {
	            $execution->execute( $logp, "lxc.$cgr_vers.cpuset.cpus = $vcpu", *CONFIG_FILE );
	        }        
	        my $vcpu_quota = $vm->getAttribute("vcpu_quota");
	        if (defined($vcpu_quota)) {
	        	my $PERIOD = 50000;
	        	$vcpu_quota =~ s/%//;
	            $execution->execute( $logp, "lxc.$cgr_vers.cpu.cfs_quota_us = " . int($PERIOD*$vcpu_quota/100), *CONFIG_FILE );
	            $execution->execute( $logp, "lxc.$cgr_vers.cpu.cfs_period_us = $PERIOD", *CONFIG_FILE );
	        }        
	        
	        # Configure Memory
	        if( $vm->exists("/create_conf/vm/mem") ){
	            my $mem = $vm->findnodes("/create_conf/vm/mem")->[0]->getFirstChild->getData;
	            $mem = $mem/1024;
	            $execution->execute( $logp, "memory.limit_in_bytes = ${mem}M", *CONFIG_FILE );
	            # Ex: lxc.$cgr_vers.memory.limit_in_bytes = 256M        
	        }        
	        
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
	            my $id       = $if->getAttribute("id");
	            my $net      = $if->getAttribute("net");
	            my $net_type = $dh->get_net_type($net);
	            my $net_mode = $dh->get_net_mode($net);
	            my $mac      = $if->getAttribute("mac");
	            $mac =~ s/,//; # TODO: why is there a comma before mac addresses?
	
	            if ( str($net) eq "lo" ) { next }
	            $execution->execute( $logp, "", *CONFIG_FILE );
	            $execution->execute( $logp, "# interface eth$id", *CONFIG_FILE );
	
	            if ( $net_mode eq "veth") {
		            $execution->execute( $logp, "lxc.network.type=phys", *CONFIG_FILE );
	            } else {
		            $execution->execute( $logp, "lxc.network.type=veth", *CONFIG_FILE );
		            $execution->execute( $logp, "# ifname on the host", *CONFIG_FILE );
		            $execution->execute( $logp, "lxc.network.veth.pair=$vm_name-e$id", *CONFIG_FILE );              
	            }
		        $execution->execute( $logp, "# ifname inside VM", *CONFIG_FILE );
		        $execution->execute( $logp, "lxc.network.name=eth$id", *CONFIG_FILE );
	
	            $execution->execute( $logp, "# if mac address", *CONFIG_FILE );
	            $execution->execute( $logp, "lxc.network.hwaddr=$mac", *CONFIG_FILE );
	            if ($id != 0) {
	            	if ($net_mode eq "virtual_bridge" and $net ne 'unconnected') {
		                $execution->execute( $logp, "# name of bridge interface connects to", *CONFIG_FILE );
		                $execution->execute( $logp, "lxc.network.link=$net", *CONFIG_FILE );
	            	} elsif ($net_mode eq "veth") {
	                    $execution->execute( $logp, "# veth link endpoint name", *CONFIG_FILE );
	                    $execution->execute( $logp, "lxc.network.link=${net}_${vm_name}", *CONFIG_FILE );            		
	            	}
	            } 
	#            else {
	#
	#                my $ipv4_tag = $if->getElementsByTagName("ipv4")->item(0);
	#                my $mask    = $ipv4_tag->getAttribute("mask");
	#                my $ip      = $ipv4_tag->getFirstChild->getData;
	#
	#                my $ip_addr = NetAddr::IP->new($ip, $mask);
	#	            $execution->execute( $logp, "lxc.network.ipv4=" . $ip_addr->cidr(), *CONFIG_FILE );
	#            }
	            
	            $execution->execute( $logp, "lxc.network.flags=up", *CONFIG_FILE );
	
	            #
	            # Add interface to /etc/network/interfaces
	            #
	            #$execution->execute( $logp, "echo 'iface lo inet loopback' >> $vm_etc_net_ifs" );
	
	        }                       
	
	        # Change to unconfined mode to avoid problems with apparmor if configured in /etc/vnx.conf
	        if ( $aa_unconfined eq 'yes' ){
		        $execution->execute( $logp, "", *CONFIG_FILE );
		        $execution->execute( $logp, "# Set unconfined to avoid problems with apparmor", *CONFIG_FILE );
		        $execution->execute( $logp, "lxc.aa_profile=unconfined", *CONFIG_FILE );
	            $execution->execute( $logp, "lxc.$cgr_vers.devices.allow = b 7:* rwm", *CONFIG_FILE );
	            $execution->execute( $logp, "lxc.$cgr_vers.devices.allow = c 10:237 rwm", *CONFIG_FILE );
	        }
	        
	        if ($nested_lxc eq 'yes') {
		        $execution->execute( $logp, "lxc.mount.auto = $cgr_vers", *CONFIG_FILE );        
		        #$execution->execute( $logp, "lxc.aa_profile=lxc-container-default-with-nesting", *CONFIG_FILE );        
		        $execution->execute( $logp, "lxc.aa_profile=lxc-container-default-with-netns", *CONFIG_FILE );        
	        }
			
			# Allow access to /dev/net/tun	
            $execution->execute( $logp, "lxc.$cgr_vers.devices.allow = c 10:200 rwm", *CONFIG_FILE );		

	        close CONFIG_FILE unless ( $execution->get_exe_mode() eq $EXE_DEBUG );

			# End of old format configuration
		}

        # Check that cgroup tags in config file all agree with the version used 
        if ( $cgr_vers eq 'cgroup2' ){
            system "sed -i 's/\\\.cgroup\\\./.cgroup2./' $vm_lxc_config" 
        } else {
            system "sed -i 's/\\\.cgroup2\\\./.cgroup./' $vm_lxc_config" 
        }

        # Call the VM autoconfiguration function
        if ($platform[0] eq 'Linux'){
            if    ($platform[1] eq 'Ubuntu')      { autoconfigure_debian_ubuntu ($vm_doc, $rootfs_mount_dir, 'ubuntu') }           
            elsif ($platform[1] eq 'Debian')      { autoconfigure_debian_ubuntu ($vm_doc, $rootfs_mount_dir, 'debian') }           
            elsif ($platform[1] eq 'Fedora')      { autoconfigure_redhat ($vm_doc, $rootfs_mount_dir, 'fedora') }
            elsif ($platform[1] eq 'CentOS')      { autoconfigure_redhat ($vm_doc, $rootfs_mount_dir, 'centos') }
            elsif ($platform[1] eq 'Debian-VyOS') { autoconfigure_vyos ($vm_doc, $rootfs_mount_dir, 'debian') }           
        } else {
            return "Platform not supported. LXC can only be used to start Linux images (Ubuntu, Debian, Fedora, CentOS or VyOS).";
        }

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
# Undefines a LXC virtual machine, deleting all associated state and files 
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

    my $self      = shift;
    my $vm_name   = shift;
    my $type      = shift;

    my $logp = "lxc-undefine_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;
    my $con;

    #
    # undefine_vm for lxc
    #
    if ($type eq "lxc") {

        my $vm_lxc_dir = $dh->get_vm_dir($vm_name) . "/mnt";

        # Remove symlink to VM in /var/lib/lxc/ if existant  
        if ( -l "$lxc_dir/$vm_name") {
            #my $a = `stat -c "%d:%i" $lxc_dir/$vm_name`; my $b = `stat -c "%d:%i" $vm_lxc_dir`;
            #wlog (VVV, "a=$a, b=$b");
            if ( `stat -c "%d:%i" $lxc_dir/$vm_name/` eq `stat -c "%d:%i" $vm_lxc_dir/`) {
                $execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " $lxc_dir/$vm_name" );
            } else {
                $error="A directory $lxc_dir/$vm_name exists but does not point to VM $vm_name directories. Remove it manually if not used."
            }
        } elsif ( -d "$lxc_dir/$vm_name") {
            $error="A directory $lxc_dir/$vm_name exists but does not point to VM $vm_name directories. Remove it manually if not used."
        }

        # Umount the overlay filesystem
        $execution->execute( $logp, $bd->get_binaries_path_ref->{"umount"} . " " . $vm_lxc_dir );
        
        # Delete COW files directory
        my $vm_cow_dir = $dh->get_vm_dir($vm_name);
        $execution->execute( $logp, $bd->get_binaries_path_ref->{"rm"} . " -rf " . $vm_cow_dir . "/fs/*" );

change_to_root();
        # Delete a link in /var/run/netns if it exists
        if ( -l "/var/run/netns/$vm_name" ) {      
	        $execution->execute( $logp, "rm /var/run/netns/$vm_name" );
        }  
back_to_user(); 

        return $error;
    }

    else {
        $error = "undefine_vm for type $type not implemented yet.\n";
        return $error;
    }
}

#---------------------------------------------------------------------------------------
#
# start_vm
#
# Starts a LXC virtual machine. The VM should already be in 'defined' state. 
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

    my $logp = "lxc-start_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;
    my $con;
    
    #
    # start_vm for lxc
    #
    if ($type eq "lxc") {

        # Check that the filesystem is mounted (it could be the case that the scenario
        # was in 'defined' state and the host has been rebooted)
        


        # Load and parse VM XML config file
#        my $parser = XML::LibXML->new();
#        my $doc = $parser->parse_file( $dh->get_vm_dir($vm_name) . "/${vm_name}_conf.xml");
        my $doc = $dh->get_vm_doc($vm_name,'dom');
        my $vm  = $doc->getElementsByTagName("vm")->item(0);
        my $filesystem_type   = $vm->getElementsByTagName("filesystem")->item(0)->getAttribute("type");
        my $filesystem        = $vm->getElementsByTagName("filesystem")->item(0)->getFirstChild->getData;
        my $vm_lxc_dir = $dh->get_vm_dir($vm_name) . "/mnt";

        if ( $filesystem_type eq "cow" ) {
            
            # Check if $vm_lxc_dir is mounted
            system "mount | cut -d ' ' -f 3 | grep '^$vm_lxc_dir' > /dev/null";
            if ( $? != 0 ) {  # overlay filesystem is not mounted

                wlog (V, "overlay filesystem of VM $vm_name not mounted; remounting", $logp);
	            # Directory where COW files are going to be stored (upper dir in terms of overlayfs) 
	            my $vm_cow_dir = $dh->get_vm_fs_dir($vm_name);
	
	            # Mount the overlay filesystem
	            if ($union_type eq 'overlayfs') {
			        my $workdir;
            		if ($overlayfs_workdir_option eq 'yes') {
                		$workdir = $dh->get_vm_dir($vm_name) . "/tmp/workdir";
                		$execution->execute( $logp, "mkdir -p $workdir" );
                		$workdir = ",workdir=$workdir";
            		}
	                # Ex: mount -t overlayfs -o upperdir=/tmp/lxc1,lowerdir=/var/lib/lxc/vnx_rootfs_lxc_ubuntu-13.04-v025/ none /var/lib/lxc/lxc1
	                $execution->execute( $logp, $bd->get_binaries_path_ref->{"mount"} . " -t $overlayfs_name -o upperdir=" . $vm_cow_dir . 
                                             ",lowerdir=" . $filesystem . $workdir . " none " . $vm_lxc_dir );
	            } elsif ($union_type eq 'aufs') {
	                # Ex: mount -t aufs -o br=/tmp/lxc1-rw:/var/lib/lxc/vnx_rootfs_lxc_ubuntu-12.04-v024/=ro none /tmp/lxc1
	                $execution->execute( $logp, $bd->get_binaries_path_ref->{"mount"} . " -t aufs -o ${aufs_options}br=" . $vm_cow_dir . 
	                                     ":" . $filesystem . "/=ro none " . $vm_lxc_dir );
	            }
            }
        }        


        my $res = $execution->execute( $logp, $bd->get_binaries_path_ref->{"lxc-start"} . " -d -l 5 -n $vm_name -f $vm_lxc_dir/config");
        if ($res) { 
            wlog (N, "$res", $logp)
        }
        
        # Start the active consoles, unless options -n|--no_console were specified by the user
        unless ($no_consoles eq 1){
            Time::HiRes::sleep(0.5);
            VNX::vmAPICommon->start_consoles_from_console_file ($vm_name);
        }

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
                    my %net = get_admin_address( 'file', $vm_name );
                    # Add it to hostlines file
                    open HOSTLINES, ">>" . $dh->get_sim_dir . "/hostlines"
                        or $execution->smartdie("can not open $dh->get_sim_dir/hostlines\n")
                        unless ( $execution->get_exe_mode() eq $EXE_DEBUG );
                    print HOSTLINES $net{'vm'}->addr() . " " . $etchosts_prefix . $vm_name . "\n";
                    close HOSTLINES;
                }               
            }
        }
change_to_root();
       # Create a link un /var/run/netns to make the network namespace of the container visible
        $res = $execution->execute( $logp, "mkdir -p /var/run/netns/" );
        if ( -l "/var/run/netns/$vm_name" ) {      
	        $res = $execution->execute( $logp, "rm /var/run/netns/$vm_name" );
        }  
        $res = $execution->execute( $logp, "ln -s /proc/\$( lxc-info -n $vm_name -H --pid )/ns/net /var/run/netns/$vm_name" );
        if ($res) { 
            wlog (N, "$res", $logp)
        }
back_to_user(); 
        
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
# Stops a LXC virtual machine. The VM should be in 'running' state. If $kill is not defined,
# an ordered shutdown request is sent to VM; if $kill is defined, a power-off is issued.  
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

    my $self    = shift;
    my $vm_name = shift;
    my $type    = shift;
    my $kill    = shift;

    my $logp = "lxc-shutdown_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;

    #
    # shutdown_vm for lxc
    #
    if ($type eq "lxc") {

        if (defined($kill)) {
        	# Kill the VM
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"lxc-stop"} . " -k -n $vm_name");
        } else {
        	# Shutdown the VM
            $execution->execute( $logp, $bd->get_binaries_path_ref->{"lxc-stop"} . " -W -n $vm_name");
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
# suspend_vm
#
# Stops a LXC virtual machine and saves its status to memory
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

    my $logp = "lxc-suspend_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;

    #
    # suspend_vm for lxc
    #
    if ($type eq "lxc") {

        # Suspend the VM to memory
        $execution->execute( $logp, $bd->get_binaries_path_ref->{"lxc-freeze"} . " -n $vm_name");

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

    my $logp = "lxc-resume_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;

    #
    # resume_vm for lxc
    #
    if ($type eq "lxc") {

        # resume the VM from memory
        $execution->execute( $logp, $bd->get_binaries_path_ref->{"lxc-unfreeze"} . " -n $vm_name");

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

    my $logp = "lxc-save_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;


    if ( $type eq "lxc" ) {
        $error = "save_vm not implemented for $type";
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

    my $logp = "lxc-restore_vm-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$type ...)", $logp);

    my $error;

    #
    # restore_vm for lxc
    #
    if ($type eq "lxc") {

        $error = "save_vm not implemented for $type";
        return $error;

    }
    else {
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

    my $error = '';

    $$ref_vstate = "--";
    $$ref_hstate = `lxc-info -n $vm_name -s | awk '{print \$2}'`;
    chomp ($$ref_hstate); 
    
    if    ($$ref_hstate eq 'RUNNING') { $$ref_vstate = 'running'}
    elsif ($$ref_hstate eq 'STOPPED') { $$ref_vstate = 'defined'}
    wlog (VVV, "state=$$ref_vstate, hstate=$$ref_hstate, error=$error");
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

    my $logp = "lxc-execute_cmd-$vm_name> ";
    my $sub_name = (caller(0))[3]; wlog (VVV, "$sub_name (vm=$vm_name, type=$merged_type, seq=$seq ...)", $logp);

    my $random_id  = &generate_random_string(6);

    if ($merged_type eq "lxc")    {

        my $user   = get_user_in_seq( $vm, $seq );
        # exec_mode should always be 'lxc-attach' 
        my $exec_mode   = $dh->get_vm_exec_mode($vm);
        wlog (VVV, "---- vm_exec_mode = $exec_mode", $logp);

        if ($exec_mode ne "lxc-attach") {
            return "execution mode $exec_mode not supported for VM of type $merged_type";
        }       
       
        # We create the command.xml file. It is not needed for LXC, as the commands are 
        # directly executed o the VM using lxc-attach. But we create it anyway for 
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
        wlog (VVV, "execute_cmd: number of plugin <exec> = " . scalar(@{$plugin_exec_list_ref}), $logp);
        
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
            wlog (VVV, "shell: $shell", $logp);
            wlog (VVV, "original command: $command", $logp);
            wlog (VVV, "scaped command: $command", $logp);
            wlog (V, "executing user defined exec command '$command'", $logp);
        	my $cmd_output = $execution->execute_getting_output( $logp, $bd->get_binaries_path_ref->{"lxc-attach"} . " --clear-env -n $vm_name -- $shell -l -c '$command'");
            wlog (N, "---\n$cmd_output---", '') if ($cmd_output ne '');
        	
        }

        # 2 - User defined <exec> tags
        wlog (VVV, "execute_cmd: number of user-defined <exec> = " . scalar(@{$exec_list_ref}), $logp);
        
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
            wlog (VVV, "shell: $shell", $logp);
            wlog (VVV, "original command: $command", $logp);
            wlog (VVV, "scaped command: $command", $logp);
            wlog (V, "executing user defined exec command:", $logp);
            my @lines = split /\n/, $command;
            foreach my $line (@lines) { wlog (V, "    $line", $logp) if $line };  
            	       
            $command =~ s/\n//;           
        	my $cmd_output = $execution->execute_getting_output( $logp, $bd->get_binaries_path_ref->{"lxc-attach"} . " --clear-env -n $vm_name -- $shell -l -c '$command'");
            wlog (N, "---\n$cmd_output---", '') if ($cmd_output ne '');            
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


    my $logp = "lxc-execute_filetree-$vm_name> ";

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
        wlog (VVV, "   Destination is a directory ($host_root)", $logp);
        unless (-d $host_root){
            wlog (VVV, "   creating unexisting dir '$host_root'...", $logp);
            system "mkdir -p $host_root";
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
                my $res = $execution->execute_getting_output( $logp, $bd->get_binaries_path_ref->{"lxc-attach"} . " --clear-env -n $vm_name -- $shell -l -c '$cmd'");
                wlog (N, "---\n$res---", '') if ($res ne '');                
            }
            if ( $perms ne '' ) {
                my $cmd="chmod -R $perms $root/$fname"; 
                my $res = $execution->execute_getting_output( $logp, $bd->get_binaries_path_ref->{"lxc-attach"} . " --clear-env -n $vm_name -- $shell -l -c '$cmd'");
                wlog (N, "---\n$res---", '') if ($res ne '');                
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
            my $res = $execution->execute_getting_output( $logp, $bd->get_binaries_path_ref->{"lxc-attach"} . " --clear-env -n $vm_name -- $shell -l -c '$cmd'");
            wlog (N, "---\n$res---", '') if ($res ne '');                
        }
        if ( $perms ne '' ) {
            $cmd="chmod -R $perms $root";
            my $res = $execution->execute_getting_output( $logp, $bd->get_binaries_path_ref->{"lxc-attach"} . " --clear-env -n $vm_name -- $shell -l -c '$cmd'");
            wlog (N, "---\n$res---", '') if ($res ne '');                
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

=BEGIN


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
=END
=cut

1;

