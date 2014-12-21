#!/usr/bin/perl
#
# Made by Linus Wang 2014.
#


#
# This file reverts all the VMs to the specific snapshot indicated in the input file.
#
#

use lib qw{ blib/lib blib/auto blib/arch blib/arch/auto/VMware blib/arch/auto };

use strict;

use VMware::Vix::Simple;
use VMware::Vix::API::Constants;

my $shapshotToRevert;
my %vmData;

my $hostname = "192.168.0.1";	#Please change this ip address to your vSphere host
my $hostport = 0;
my $username = "username";	#Please change the user name
my $password = "password";	#Please change the password
my $connType = VIX_SERVICEPROVIDER_VMWARE_VI_SERVER;	#Be sure that you select the right connection type

my $err;
my $hostHandle = VIX_INVALID_HANDLE;;

my $num_args = $#ARGV + 1;
if ($num_args != 1) {
	print "\nUsage: SnapshotRevert.pl inputFIle\n";
	exit;
}

#read in file
$shapshotToRevert = $ARGV[0];
open(IF, $shapshotToRevert) or die "Cannot open input file\n";
while (my $inline = <IF>) {
	chomp($inline);
	my @keyValue = split("\t", $inline);
	print $keyValue[0] . " => " . $keyValue[1] . "\n";
	$vmData{$keyValue[0]} = $keyValue[1];
}
close(IF);


#connect to vSphere
($err, $hostHandle) = HostConnect(VIX_API_VERSION, 
                                  $connType,
                                  $hostname, $hostport, $username, $password,
                                  0, VIX_INVALID_HANDLE);
die "Connect failed, $err ", GetErrorText($err), "\n" if $err != VIX_OK;

my $count = 0;
my $totalVM = keys %vmData;
foreach my $vmpath (sort keys %vmData){
	my $vmHandle = VIX_INVALID_HANDLE;
	my $snapshotHandle = VIX_INVALID_HANDLE;
	
	++$count;
	print  $count . '/' . $totalVM . "\t" . $vmpath . "\n";
	($err, $vmHandle) = VMOpen($hostHandle, $vmpath);
	if($err != VIX_OK){
		print "Failed to open VM $vmpath\n" . GetErrorText($err);
		next;
	}
	
	
	($err, $snapshotHandle) = VMGetNamedSnapshot($vmHandle, $vmData{$vmpath});
	if($err != VIX_OK){
		print "Failed to locate snapshot $vmData{$vmpath} for VM: $vmpath\n" . GetErrorText($err);
		ReleaseHandle($vmHandle);
		next;
	}
	
	$err = VMRevertToSnapshot($vmHandle, 
							$snapshotHandle,
							VIX_VMPOWEROP_SUPPRESS_SNAPSHOT_POWERON,		# options
	                        VIX_INVALID_HANDLE);		# property handle
	if($err != VIX_OK){
		print "Failed to revert snapshot $vmData{$vmpath} for VM: $vmpath\n" . GetErrorText($err);
		ReleaseHandle($snapshotHandle);
		ReleaseHandle($vmHandle);
		next;
	}

	ReleaseHandle($snapshotHandle);
	
	$err = VMPowerOn($vmHandle,
                 VIX_VMPOWEROP_NORMAL, # powerOnOptions
                 VIX_INVALID_HANDLE);  # propertyListHandle
	if($err != VIX_OK){
		print "Failed to power on VM: $vmpath\n" . GetErrorText($err);
		ReleaseHandle($vmHandle);
		next;
	}
	
	ReleaseHandle($vmHandle);
}


HostDisconnect($hostHandle);
print "all done!\n";

sub revertsnapshot($$) {
   my ($vm, $name) = @_;
   my $err;
   my $ss;

   ($err, $ss) = VMGetNamedSnapshot($vm, $name);
   die("Getting snapshot handle", $err) if $err != VIX_OK;
   $err = VMRevertToSnapshot($vm, $ss, 0, VIX_INVALID_HANDLE);
   die("Reverting to snapshot", $err) if $err != VIX_OK;
   ReleaseHandle($ss);
}
