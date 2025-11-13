#!/usr/bin/perl
use strict;
use warnings;
use Getopt::Long;

$ENV{'PATH'} = "/usr/bin:/usr/sbin";
my $DEBUG = $ENV{'DEBUG'};

# BT MAC address of device to query
my $BT = "00:00:00:00:00:00";

# Friendly name for this device
# (used for the MQTT topic)
my $BT_friendly = "KG140F";

# set to 0 to disable MQTT completely
my $mqtt_enabled = 1;
my $mqtt_server  = "localhost";

my $mqtt_retain = 0;

# basename for the MQTT topics,
#  topics are ${mqtt_topic_base}/${BT_friendly}/key name
my $mqtt_topic_base = "junctek";

# leave empty if your mqtt server doesn't require auth
my $mqtt_username = "";
my $mqtt_passwd   = "";

# set to 1 to skip over all the values for the
# battery protection settings
my $skip_protection_stats = 1;

my $help = 0;
my $quiet;

GetOptions(
    'help|?'   => \$help,
    'quiet'    => \$quiet,
    'device=s' => \$BT,
    'mqtt'     => \$mqtt_enabled,
    'server=s' => \$mqtt_server,
    'name=s'   => \$BT_friendly,
    'retain'   => \$mqtt_retain
);

&help if $help;

sub help {
    print "\nUsage: $0 [OPTION?]\n\n";
    print "Options:\n";
    print "\t-d, --device=MAC\t\tSpecify remote Bluetooth address\n";
    print "\t-q, --quiet\t\t\tDon't print output\n";
    print "\t-m, --mqtt\t\t\tEnable (1) or disable (0) publishing to MQTT\n";
    print "\t-s, --server\t\t\tHostname of MQTT server\n";
    print
"\t-n, --name\t\t\t'Friendly' name of Junctek device, MQTT topic becomes junctek/[name]/... \n";
    print "\t-r, --retain\t\t\tPublish MQTT messages with retain flag\n";
    print "\t-h, --help\t\t\t<-- You are here\n";
    print "\n\n";

    exit(0);

}

my $mqtt;
if ($mqtt_enabled) {
    use Net::MQTT::Simple;
    $mqtt = Net::MQTT::Simple->new($mqtt_server);
}

my $val;
my %stats;
my $i = 0;

# how many packets to listen for, 40 seems to be one complete set
my $max_pkts = 40;

# These are all the data types I've been able to identify,
# there's a bucnh more still but I'm mainly interested in V/A/SoC/state
my %key = (
    "b0", "Battery capacity",
    "b1", "Over-temp protection",
    "b7", "Relay mode",
    "c0", "Volts",
    "c1", "Amps",
    "c2", "Protection delay sec",
    "c3", "Protection recovery sec",
    "c5", "Over-voltage protection",
    "c6", "Under-voltage protection",
    "c7", "Over-current protection",
    "c8", "Over-current charge protection",
    "c9", "Over-power protection",
    "d0", "Relay state",
    "d1", "Charge state",
    "d2", "Ah remaining",
    "d3", "KWh discharged",
    "d4", "KWh charged",
    "d5", "Total run time",
    "d6", "Time remaining",
    "d7", "Impedance",
    "d8", "Watts",
    "d9", "Temperature",
    "e3", "Under-temp protection"
);

# First, request the device to send all values once,
# otherwise it only sends values as they change so some
# will never be sent, e.g. battery capacity etc.
# Note: this won't actually send the values, just
# trigger them to be sent once something starts listening to
# the datastream on handle 0x22.
my $rv = system(
"gatttool -b $BT --char-write-req --handle=0x0025 --value=0xbb9aa90cee >/dev/null"
);
if ( $rv > 0 ) { die "Connection failed\n"; }

# Next, request the datastream to start.
# The device will initially send all ~40 values once,
# then send values as they change.
open my $gatt,
  "gatttool -b $BT  --char-write-req --handle=0x0022 --value=0100 --listen|"
  or die "failed to read from gatttool\n";

while (<$gatt>) {
    chomp;
    if ( $_ =~ m/value: (.*)$/ ) {
        my $data = $1;
        my @d    = split /\s/, $data;
        foreach my $v (@d) {
            next if ( $v eq 'ee' );    # end of record byte
            if ( $v eq 'bb' ) {

                # start of record byte, flush buffer
                $val = '';
                next;
            }
            if ( $v =~ m/^\d+$/ ) {
                $val .= $v;
            }
            else {
                if    ( $v eq 'c0' ) { $val = $val / 100; }
                elsif ( $v eq 'c1' ) {
                    $val = $val / 100;
                    no warnings;
                    if ( $stats{ $key{'d1'} } eq 'Discharging' ) {
                        $val = $val * -1;
                    }
                    use warnings;
                }
                elsif ( $v eq 'c5' ) { $val = $val / 100; }
                elsif ( $v eq 'c6' ) { $val = $val / 100; }
                elsif ( $v eq 'c7' ) { $val = $val / 100; }
                elsif ( $v eq 'c8' ) { $val = $val / 100; }
                elsif ( $v eq 'c9' ) { $val = $val / 100; }
                elsif ( $v eq 'd0' ) {
                    if   ( $val > 0 ) { $val = "off"; }
                    else              { $val = "on"; }
                }
                elsif ( $v eq 'd1' ) {
                    if ( $val > 0 ) { $val = "Charging"; }
                    else {
                        $val = "Discharging";
                        if ( $stats{ $key{'c1'} } > 0 ) {
                            $stats{ $key{'c1'} } *= -1;
                        }
                    }
                }
                elsif ( $v eq 'b7' ) {
                    if   ( $val > 0 ) { $val = "N/C"; }
                    else              { $val = "N/O"; }
                }
                elsif ( $v eq 'd2' ) { $val = $val / 1000; }
                elsif ( $v eq 'd3' ) { $val = $val / 100000; }
                elsif ( $v eq 'd4' ) { $val = $val / 100000; }
                elsif ( $v eq 'd5' ) {
                    $val = formatSeconds( { seconds => $val } );
                }
                elsif ( $v eq 'd6' ) {
                    $val = formatSeconds( { seconds => ( $val * 60 ) } );
                }
                elsif ( $v eq 'd7' ) { $val = $val / 100; }
                elsif ( $v eq 'd8' ) {
                    $val = $val / 100;
                    no warnings;
                    if ( $stats{ $key{'d1'} } eq 'Discharging' ) {
                        $val = $val * -1;
                    }
                    use warnings;
                }
                elsif ( $v eq 'd9' ) { $val = $val - 100; }
                elsif ( $v eq 'b0' ) { $val = $val / 10; }
                elsif ( $v eq 'b1' ) { $val = $val - 100; }
                elsif ( $v eq 'e3' ) { $val = $val - 100; }

                if ( $stats{ $key{'b0'} } && $stats{ $key{'d2'} } ) {

                    # calculate state of charge if we have values
                    # for both battery capacity and Ah remaining
                    my $SoC =
                      ( $stats{ $key{'d2'} } / $stats{ $key{'b0'} } ) * 100;
                    $stats{'SoC'} = $SoC;
                }

                $DEBUG && print $key{$v} . " [$v]" . ": " . $val . "\n";

                if ( $key{$v} ) {
                    $stats{ $key{$v} } = $val;
                }
                if ( $i < $max_pkts ) {
                    $i++;
                }
                else {

                    foreach my $k_ ( sort keys %stats ) {
                        next unless ($k_);
                        if ($skip_protection_stats) {
                            next if ( $k_ =~ m/rotection/ );
                        }
                        unless ($quiet) { print "$k_: $stats{$k_}\n"; }
                        if     ($mqtt_enabled) {
                            my $topic = $k_;
                            $topic =~ s/\s+/_/g;
                            if ($mqtt_retain) {
                                $mqtt->retain(
                                    "$mqtt_topic_base/$BT_friendly/$topic" =>
                                      $stats{$k_} );
                            }
                            else {
                                $mqtt->publish(
                                    "$mqtt_topic_base/$BT_friendly/$topic" =>
                                      $stats{$k_} );
                            }
                        }
                    }
                    exit;
                }

                $val = '';
            }
        }
    }
}

sub formatSeconds {
    my ($args) = @_;
    my $secs = $args->{seconds};
    my ( $hours, $hourremainder ) =
      ( ( $secs / ( 60 * 60 ) ), $secs % ( 60 * 60 ) );
    my ( $minutes, $seconds ) =
      ( int $hourremainder / 60, $hourremainder % 60 );
    ( $hours, $minutes, $seconds ) = (
        sprintf( "%02d", $hours ),
        sprintf( "%02d", $minutes ),
        sprintf( "%02d", $seconds )
    );
    return $hours . ':' . $minutes . ':' . $seconds;
}
