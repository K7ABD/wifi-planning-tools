#!/usr/bin/perl

use strict;

my $DEBUG      = 0;
my $ITERATIONS = 10000;

my @aps = ('Basement', 'Kitchen', 'Living Room', 'Master', 'Office', 'Guest Room');
my @channels = ('1', '6', '11');
my @attenuations = (0, -4, -8, -12, -16, -200); # Effictively: H, H/M, M, M/L, L, Off

my %observations; # Measured RSSI of every access point at a handful of lcoations throughout the house.
                  # The order of these in the array should align with the order of the @aps array above.
                  # This would probably be more clear if it was a hash..
$observations{'Living Room'} = [-66, -79, -41, -70, -54, -91];
$observations{'Dining Room'} = [-75, -58, -60, -63, -55, -68];
$observations{'Office'}      = [-80, -62, -70, -60, -44, -85];
$observations{'Sunroom'}     = [-91, -61, -89, -72, -78, -84];
$observations{'Kitchen'}     = [-83, -47, -72, -55, -53, -73];


my %noises; # The measured noise level (aka neighbors) on each of channels (1, 6, 11);
$noises{'Living Room'} = [-93, -94, -90];
$noises{'Dining Room'} = [-90, -96, -90];
$noises{'Office'}      = [-94, -94, -84];
$noises{'Sunroom'}     = [-92, -87, -89];
$noises{'Kitchen'}     = [-93, -85, -82];


my %channel_indexes;
for (my $i = 0; $i < scalar(@channels); $i++)
{
    # reverse lookup for channel_index to channel name
    $channel_indexes{$channels[$i]} = $i;
}



my $best_worst_snr = 0;
my $best_avg_snr   = 0;
my $best_plan      = '';
my $best_report    = '';
for (my $i = 0; $i < $ITERATIONS; $i++)
{
    my %ap_chans;
    my @obs_snr;
    my $report = '';

    # randomly assign channels to APs (a smarter person would iterate through all possible permutations):
    foreach my $ap (@aps)
    {
        $ap_chans{$ap} = set_channel_and_attenuation($channels[int(rand(scalar(@channels)))],
                                               $attenuations[int(rand(scalar(@attenuations)))]);
    }

    # foreach observation, find the strongest AP, then then the highest interference:
    foreach my $obs (keys %observations)
    {
        debug("Looking at Location '$obs':\n");


        # find the strongest AP for this observation:
        my $best_rssi = -200;
        my $best_ap_index = -1;
        debug("    Looking for strongest AP...\n");
        for (my $ap_index = 0; $ap_index < scalar(@aps); $ap_index++)
        {
            my $obs_ap_rssi = get_rssi($ap_chans{$aps[$ap_index]}, $observations{$obs}[$ap_index]);

            debug("        AP '" . $aps[$ap_index] . "' has RSSI of $obs_ap_rssi\n");
            if ($obs_ap_rssi > $best_rssi)
            {
                $best_rssi = $obs_ap_rssi;
                $best_ap_index = $ap_index;
            }
        }

        debug("        ** Best AP is '" . $aps[$best_ap_index] . "' at $best_rssi\n");
        
        my $best_ap_channel      = get_channel($ap_chans{$aps[$best_ap_index]});
        my $highest_noise        = $noises{$obs}[$channel_indexes{$best_ap_channel}];
        my $highest_noise_source = 'Neighbors';

        # find the noise level (either from external noise, or from other APs)
        for (my $ap_index = 0; $ap_index < scalar(@aps); $ap_index++)
        {
            my $ch = get_channel($ap_chans{$aps[$ap_index]});
            if ($ch eq $best_ap_channel && $ap_index != $best_ap_index)
            {
                my $rssi = get_rssi($ap_chans{$aps[$ap_index]}, $observations{$obs}[$ap_index]);
                if ($rssi > $highest_noise)
                {
                    $highest_noise = $rssi;
                    $highest_noise_source = "Local-AP (" . $aps[$ap_index] . ")";
                }
            }
        }

        # caluclate the SnR at this observation
        my $snr = $best_rssi - $highest_noise;

        push (@obs_snr, $snr);

        # create an entry in the "Report" for this observation... it's kinda silly to generate this report everyt time
        # since we gonna throw away all but the best of them, but it's easier to creat it now...
        my $rep = sprintf("%-20s %-20s %10s %8s %17s %-32s\n", $obs, $aps[$best_ap_index], $best_rssi, $snr, $highest_noise, $highest_noise_source);

        debug($rep);
        $report .= $rep;
    }

    # Find the observation with the worst SnR///
    my $worst_snr = $obs_snr[0];
    my $sum = 0;
    foreach my $snr (@obs_snr)
    {
        $sum += $snr;

        if ($snr < $worst_snr)
        {
            $worst_snr = $snr;
        }
    }
    my $avg_snr = $sum / scalar(@obs_snr);

    # Create the wifi (which APs are on which channel and at what attenuation)
    my $plan = '';
    foreach my $ap_ch (keys %ap_chans)
    {
        my $ch = get_channel($ap_chans{$ap_ch});
        my $at = get_atten  ($ap_chans{$ap_ch});
        $plan .= sprintf("%-20s %8s %12d\n", $ap_ch, $ch, $at);
    }

    # If this is the best one yet, let's capture that...
    if ($worst_snr > $best_worst_snr || ($worst_snr == $best_worst_snr && $avg_snr > $best_avg_snr))
    {
        $best_worst_snr = $worst_snr;
        $best_plan      = $plan;
        $best_report    = $report;
        $best_avg_snr   = $avg_snr;
    }
}

# Print the results:
print "\n****** Access Point and Channel Configuration ****** \n\n";
printf ("%-20s %8s %12s\n", "Access Point", "Channel", "Attenuation");
printf ("%-20s %8s %12s\n", "------------", "-------", "-----------");
print $best_plan;

print "\n\n****** Location - predicted best AP and SnR\n\n";
printf("%-20s %-20s %10s %8s %17s %-32s\n", 'Location', 'Best AP', 'RSSI (dBm)', 'SnR (dB)', 
        'Noise Level (dBm)', 'Noise Source');
printf("%-20s %-20s %10s %8s %17s %-32s\n", '--------', '-------', '----------', '--------', 
        '-----------------', '------------');
print $best_report;

print "\nWorst SNR: $best_worst_snr\n";
print "Average SNR: $best_avg_snr\n";


### Helpers
sub get_channel
{
    my ($ch_atten) = @_;

    my ($ch,$atten) = split('\t', $ch_atten);

    return $ch;
}

sub get_atten
{
    my ($ch_atten) = @_;
  
    my ($ch, $atten) = split('\t', $ch_atten);

    return $atten;
}

sub get_rssi
{
    my ($ch_atten, $high_rssi) = @_;

    my ($ch,$atten) = split('\t', $ch_atten);

    return $high_rssi + $atten;
}

sub set_channel_and_attenuation
{
    my ($channel, $attenuation) = @_;

    return "$channel\t$attenuation";
}

sub debug
{
    my ($str) = @_;

    if ($DEBUG == 1)
    {
        print $str;
    }
}
