#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use Data::Dumper;
use Getopt::Long;

sub read_a7105 {
    my %cmd;
    my $h = "$FindBin::Bin/../src/protocol/iface_a7105.h";
    open my $fh, "<", $h or die "Couldn't read $h\n";
    while(<$fh>) {
        if(/^enum {/ .. /^};/) {
             if(/A7105_.._(\S+)\s*=\s*(0x..)/) {
                 $cmd{hex($2)} = $1;
             }
        }
    }
    return \%cmd;
}
sub read_nrf24l01 {
    my($long) = @_;
    my %cmd = (
        WR_MASK     => 0x20, WR_MASK_VAL  => 0x20,
        CMD_MASK    => 0xC0, CMD_MASK_VAL => 0xC0,
        ADDR_MASK   => 0x1F
        );
    my $h = "$FindBin::Bin/../src/protocol/iface_nrf24l01.h";
    open my $fh, "<", $h or die "Couldn't read $h\n";
    while(<$fh>) {
        if(/^enum {/ .. /^};/) {
             if(/(NRF24L01_.._)(\S+)\s*=\s*(0x..)/) {
                 $cmd{hex($3)} = ($long ? $1 : "") . $2;
             }
        }
    }
    return \%cmd;
}

sub read_cc2500 {
    my($long) = @_;
    my %cmd = (
        WR_MASK     => 0x80, WR_MASK_VAL  => 0x00,
        CMD_MASK    => 0x70, CMD_MASK_VAL => 0x30,
        ADDR_MASK   => 0x3F
        );
    my $h = "$FindBin::Bin/../src/protocol/iface_cc2500.h";
    open my $fh, "<", $h or die "Couldn't read $h\n";
    while(<$fh>) {
        if(/^enum {/ .. /^};/) {
             if(/(CC2500_.._)(\S+)\s*=\s*(0x..)/) {
                 $cmd{hex($3)} = ($long ? $1 : "") . $2;
             }
        } elsif(/#define\s+(CC2500_)(\S+)\s+(0x3.)/) {
             $cmd{hex($3)} = ($long ? $1 : "") . $2;
        }
    }
    return \%cmd;
}
sub parse_spi {
    my($file) = @_;
    open my $fh, "<", $file or die "Couldn't read $file\n";
    my @data = ();
    my $basetime = -1;
    $_ = <$fh>;
    while(<$fh>) {
        s///;
        chomp;
        my($time, $idx, $mosi, $miso) = split(/,/, $_);
        next if ($idx eq "");
        $basetime = $time if($basetime == -1);
        $data[$idx] ||= [$time-$basetime];
        push @{$data[$idx]}, [hex($mosi), hex($miso)];
    }
    #[ [time, [mosi, miso], [mosi, miso], ...], [time, [mosi, miso], [mosi, miso], ...], ...
    return \@data;
}

sub show_full {
    my($time, $dir, $cmdstr, $mosi, $miso) = @_;
    my $format = "%-10.6f %s %s      %-40s => %s\n";
    printf $format, $time, $dir, $cmdstr, "@$mosi", "@$miso";
}
sub show {
    my($time, $dir, $cmdstr, $mosi, $miso) = @_;
    my $format = "%-10.6f %s %s      %s => %s\n";
    if ($dir eq "=" || $dir eq ">") {
        printf $format, $time, $dir, $cmdstr, "@$mosi", $miso->[1] ? $miso->[1] : $miso->[0];
    } else {
        printf $format, $time, $dir, $cmdstr, $mosi->[0], "@$miso[1..$#$miso]";
    }
}

sub display_results {
    my($data, $cmds, $long, $full) = @_;
    my $cmdlen = 5;
    foreach (values %$cmds) {
        $cmdlen = length($_) if(length($_) > $cmdlen);
    }
    foreach my $d (@$data) {
        my @d = @$d;
        my($time) = shift @d;
        my @mosi;
        my @miso;
        foreach (@d) {
            push @mosi, sprintf("%02x", $_->[0]);
            push @miso, sprintf("%02x", $_->[1]);
        }
        my $cmdbyte = hex($mosi[0]);
        my $dir = "<";
        if (($cmdbyte & $cmds->{CMD_MASK}) == $cmds->{CMD_MASK_VAL}) {
            $dir = "=";
        } elsif (($cmdbyte & $cmds->{WR_MASK}) == $cmds->{WR_MASK_VAL}) {
            $dir = ">";
        }
        my $cmdstr = sprintf("%-${cmdlen}s", $cmds->{$cmdbyte} || $cmds->{$cmdbyte & $cmds->{ADDR_MASK}} || "");
        if($full) {
            show_full($time, $dir, $cmdstr, \@mosi, \@miso);
        } else {
            show($time, $dir, $cmdstr, \@mosi, \@miso);
        }
    }
}

sub main {
    my $long;
    my $full;
    my $tx = "nrf24l01";
    GetOptions("tx=s" => \$tx, "long" => \$long, "full" => \$full);
    my $file = shift @ARGV;
    my $cmds;
    if ($tx =~ /^n/) {
        $cmds = read_nrf24l01($long);
    } elsif ($tx =~ /^a/) {
        $cmds = read_a7105($long);
    } elsif ($tx =~ /^cc/ || $tx =~ /2500/) {
        $cmds = read_cc2500($long);
    } else {
        die "Unrecognized transceiver: $tx\n";
    }
    my $data = parse_spi($file);
    display_results($data, $cmds, $long, $full);
}
main();
