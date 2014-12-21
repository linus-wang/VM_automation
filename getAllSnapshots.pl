#!/usr/bin/perl
#
# Made by Linus Wang 2014.
#


#
# This file gets all the shapshots's name from the VMs
#
#
use lib qw{ blib/lib blib/auto blib/arch blib/arch/auto/VMware blib/arch/auto };

use strict;
use JSON;
use warnings;

use VMware::Vix::Simple;

# all constants are exported
use VMware::Vix::API::Constants;

my $hostname = "192.168.0.1";	#Please change this ip address to your vSphere host
my $hostport = 0;
my $username = "username";	#Please change the user name
my $password = "password";	#Please change the password
my $connType = VIX_SERVICEPROVIDER_VMWARE_VI_SERVER;	#Be sure that you select the right connection type

my $err;
my $hostHandle = VIX_INVALID_HANDLE;;
my $vmHandle = VIX_INVALID_HANDLE;
my $snapshotRootHandle = VIX_INVALID_HANDLE;
my $snapshotChildHandle = VIX_INVALID_HANDLE;
my $numRootSnapshots;
my $numChildren;

my $outJsonFile = 'allVMSnapshots.json';

my $vmName;

my @vms;
my %vmList;

($err, $hostHandle) = HostConnect(VIX_API_VERSION, 
                                  $connType,
                                  $hostname, $hostport, $username, $password,
                                  0, VIX_INVALID_HANDLE);

die "Connect failed, $err ", GetErrorText($err), "\n" if $err != VIX_OK;

#@vms = FindRunningVMs($hostHandle, 100);
@vms = FindItems($hostHandle, VIX_FIND_REGISTERED_VMS, 100);

$err = shift @vms;
die "Error $err finding running VMs ", GetErrorText($err),"\n" if $err != VIX_OK;

for my $vmpath (@vms){
#	my $selectThisVM = selectVM($vmpath);
	$vmHandle = VIX_INVALID_HANDLE;
	($err, $vmHandle) = VMOpen($hostHandle, $vmpath);
	die("Failed to open VM $vmpath", $err) if $err != VIX_OK;
	
	($err, my $powerState) = GetProperties($vmHandle, VIX_PROPERTY_VM_POWER_STATE);
	die "Get VM Power State failed, $err ", GetErrorText($err), "\n" if $err != VIX_OK;
	if($powerState == VIX_POWERSTATE_POWERED_ON){	
		($err, $vmName) = VMReadVariable($vmHandle,
												VIX_VM_CONFIG_RUNTIME_ONLY,
												"Displayname",
												0); # options
		die "VMReadVariable() failed, $err ", GetErrorText($err), "\n" if $err != VIX_OK;
		print $vmName . "\n";
	
	
		($err,$numRootSnapshots) = VMGetNumRootSnapshots($vmHandle);
		die "VMGetNumRootSnapshots() failed, $err ", GetErrorText($err), "\n" if $err != VIX_OK;
		
		my @allSnapshots;
		for (my $i = 0; $i < $numRootSnapshots; $i++) {
			$snapshotRootHandle = VIX_INVALID_HANDLE;
			($err, $snapshotRootHandle) = VMGetRootSnapshot($vmHandle, $i); # index
			die "VMGetRootSnapshot() failed, $err ", GetErrorText($err), "\n" if $err != VIX_OK;
			
			($err, my $snapshotName) = GetProperties($snapshotRootHandle, VIX_PROPERTY_SNAPSHOT_DISPLAYNAME);
			die "Get Sanpshot Name failed, $err ", GetErrorText($err), "\n" if $err != VIX_OK;
			push(@allSnapshots, $snapshotName);
			
			($err, $numChildren) = SnapshotGetNumChildren($snapshotRootHandle);
			die "Get number of Children Sanpshot failed, $err ", GetErrorText($err), "\n" if $err != VIX_OK;
			
			if ($numChildren > 0) {
				my @moreChild = getChildSnapshots($snapshotRootHandle);
				push(@allSnapshots, @moreChild);
			}
			ReleaseHandle($snapshotRootHandle);
		}
		my %thisVMSnapshots;
	    $thisVMSnapshots{'-vmx'} = $vmpath;
		$thisVMSnapshots{'snapshots'} = '[' . join(', ', @allSnapshots) . ']';
			
		$vmList{$vmName} = \%thisVMSnapshots;
			
		ReleaseHandle($vmHandle);
	}
#    revertsnapshot($vmhandle, $snapshotName);
}
HostDisconnect($hostHandle);

open(OF, ">$outJsonFile") or die "Connot create json file\n";

my $json = encode_json \%vmList;
print OF $json;
close OF;

print "done\n";

sub getChildSnapshots{
	my ($vmHandle) = @_;
	my @allChildSnapshots;
	#Get the amount of children snapshots
	($err, my $numChildren) = SnapshotGetNumChildren($vmHandle);
	die "Get number of Children Sanpshot failed, $err ", GetErrorText($err), "\n" if $err != VIX_OK;
	
	#Access all the children snapshots and get it's name
	for(my $i = 0; $i < $numChildren; $i++){
		my $snapshotChildHandle = VIX_INVALID_HANDLE;
		($err, $snapshotChildHandle) = SnapshotGetChild($vmHandle, $i); #Get child snapshot handler
		die "Get Child Sanpshot failed, $err ", GetErrorText($err), "\n" if $err != VIX_OK;
		
		#Get snapshot name
		($err, my $snapshotName) = GetProperties($snapshotChildHandle, VIX_PROPERTY_SNAPSHOT_DISPLAYNAME);
		die "Get Sanpshot Name failed, $err ", GetErrorText($err), "\n" if $err != VIX_OK;
		
		#Store the snapshot name
		push(@allChildSnapshots, $snapshotName);
		
		#recursive check for more sub children
		($err, my $numChildrenChild) = SnapshotGetNumChildren($snapshotChildHandle);
		die "Get number of Sub Children Sanpshot failed, $err ", GetErrorText($err), "\n" if $err != VIX_OK;
		
		if ($numChildrenChild > 0) {
			my @moreChild = getChildSnapshots($snapshotChildHandle);
			push(@allChildSnapshots, @moreChild);
		}
		ReleaseHandle($snapshotChildHandle);
	}
	
	return @allChildSnapshots;
}