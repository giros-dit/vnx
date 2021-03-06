# This file is part of EDIV package
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software Foundation
# Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
# Copyright: (C) 2008 Telefonica Investigacion y Desarrollo, S.A.U.
# Authors: Fco. Jose Martin,
#          Miguel Ferrer
#          Departamento de Ingenieria de Sistemas Telematicos, Universidad Politécnica de Madrid
#

package round_robin;

###########################################################
# Modules import
##########################################################

use strict;
use XML::DOM;
use Math::Round;

###########################################################
# Global variables 
###########################################################

my $scenario;
my @cluster_info;
my $cluster_size;
my @vms_to_split;
my %static_assignment;

###########################################################
# Subroutines
###########################################################
	###########################################################
	# Subroutine to obtain segmentation name
	###########################################################
sub name {

	my $name = "RoundRobin";

}

	###########################################################
	# Subroutine to obtain segmentation mode
	###########################################################
sub split {

	my ( $class, $rdom_tree, $rcluster_hosts, $rvms_to_split, $rstatic_assignment ) = @_;
	
	$scenario = $$rdom_tree;
	@cluster_info = @$rcluster_hosts;
	$cluster_size = @cluster_info;
	@vms_to_split = @$rvms_to_split;
	%static_assignment = %$rstatic_assignment;
	

	print("Segmentator: Cluster physical machines -> $cluster_size\n");

	my %allocation;
	
	my $static_assignment_undef = 1;
	my @keys = keys (%static_assignment);
	my $j = 0;
	while (defined(my $key = $keys[$j])) {
		 $static_assignment_undef = 0;
		$j++;
	}
		
	if ($static_assignment_undef){
		my $VMList = $scenario->getElementsByTagName("vm");		# Scenario virtual machines node list
		my $vm_number = $VMList->getLength;						# Number of virtual machines of scenario
		
		for (my $i=0; $i<$vm_number; $i++) {
			my $virtualm = $VMList->item($i);
			my $virtualm_name = $virtualm->getAttribute("name");
			my $assigned_host_index = $i % $cluster_size;
			my $assigned_host = $cluster_info[$assigned_host_index]->{_hostname};
			$allocation{$virtualm_name} = $assigned_host;
			print("Segmentator: Virtual machine $virtualm_name to physical host $assigned_host\n"); 	
		}
	} else {
		my %offset;
		my @keys = keys (%static_assignment);
		my $j = 0;
		while (defined(my $key = $keys[$j])) {
			my $hostName = $static_assignment{$key};
			$offset{$hostName}++;
			$allocation{$key} = $hostName;
			$j++;
		}
		
		my $vms_to_split_size = @vms_to_split;
		for (my $i=0; $i<$vms_to_split_size; $i++){
			my $vm = $vms_to_split[$i];
			my $selected_hostname = $cluster_info[$0]->{_hostname};
			
			for (my $j=1; $j<$cluster_size; $j++) {
				my $hostName = $cluster_info[$j]->{_hostname};
				if ($offset{$hostName} < $offset{$selected_hostname}){
					$selected_hostname = $hostName;
				}
			}
			$allocation{$vm} = $selected_hostname;
			print("Segmentator: Virtual machine $vm to physical host $selected_hostname\n");
			$offset{$selected_hostname}++;			
			
		}
		
	}
	
	return %allocation;

}
1
# Subroutines end
###########################################################
