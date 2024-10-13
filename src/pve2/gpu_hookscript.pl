#!/usr/bin/perl
# /var/lib/vz/snippets/gpu_hookscript.pl
# Hook script for PVE guests (hookscript config option)
# Ref:
#   https://pve.proxmox.com/pve-docs/pve-admin-guide.html#_hookscripts
#   https://forum.proxmox.com/threads/backup-vm-same-pcie-device-iommu-on-two-vm.129600/#post-567803
# Example: /usr/share/pve-docs/examples/guest-example-hookscript.pl

use strict;
use warnings;

# print "GUEST HOOK: " . join(' ', @ARGV). "\n";

my $vmid = shift;
my $phase = shift;

if ($phase eq 'pre-start') {
    # First phase 'pre-start' will be executed before the guest
    # is started. Exiting with a code != 0 will abort the start
    my $devtop = `/usr/local/bin/get_vm_id.sh devtop`;
    my $gaming = `/usr/local/bin/get_vm_id.sh gaming`;

    print "$vmid is starting, shutdown competing VMs.\n";
    if ($vmid == $devtop) {
        system("qm stop $gaming");
        system("qm wait $gaming --timeout 20");
    } elsif ($vmid == $gaming) {
        system("qm stop $devtop");
        system("qm wait $devtop --timeout 20");
    }
    # system("echo 1 > /sys/bus/pci/devices/0000:01:00.0/remove");
    # system("echo 1 > /sys/bus/pci/devices/0000:01:00.1/remove");
    # system("sleep 5");

} elsif ($phase eq 'post-start') {
    # Second phase 'post-start' will be executed after the guest
    # successfully started.
    # print "$vmid started successfully.\n";

} elsif ($phase eq 'pre-stop') {
    # Third phase 'pre-stop' will be executed before stopping the guest
    # via the API. Will not be executed if the guest is stopped from
    # within e.g., with a 'poweroff'
    # print "$vmid will be stopped.\n";

} elsif ($phase eq 'post-stop') {
    # Last phase 'post-stop' will be executed after the guest stopped.
    # This should even be executed in case the guest crashes or stopped
    # unexpectedly.
    # print "$vmid stopped. Doing cleanup.\n";

} else {
    die "got unknown phase '$phase'\n";
}

exit(0);
