#!/usr/bin/perl

use strict;
use warnings;

# use DTALib;
use MIDI;

my $quiet = 0;
if ($ARGV[0] && $ARGV[0] eq "-q")
{
   $quiet = 1;
   shift @ARGV;
}

sub debug
{
   if (!$quiet)
   {
      print @_;
   }

   return;
}


foreach my $one (@ARGV)
{
   my %songinfo;
   my @empties;
   my $opus = MIDI::Opus->new({ 'from_file' => $one });
   debug "$one has " . scalar( $opus->tracks ) . " tracks\n";
   my $i = 0;
   foreach my $track ( $opus->tracks )
   {
      my @ar = $track->events();
      if ($ar[0][0] eq 'track_name')
      {
         my $trackname = $ar[0][2];
         debug "track $i name: $trackname\n";
         if ($trackname eq "HARM1")
         {
            $songinfo{'HARM1'} = 1;
            $songinfo{'num_harm'}++;
         }
         elsif ($trackname eq "HARM2")
         {
            $songinfo{'HARM2'} = 1;
            $songinfo{'num_harm'}++;
         }
         elsif ($trackname eq "HARM3")
         {
            $songinfo{'HARM3'} = 1;
            $songinfo{'num_harm'}++;
         }
         elsif ($trackname eq "PART DRUMS")
         {
            $songinfo{'DRUMS'} = 1;
         }
         elsif ($trackname eq "PART BASS")
         {
            $songinfo{'BASS'} = 1;
         }
         elsif ($trackname eq "PART GUITAR")
         {
            $songinfo{'GUITAR'} = 1;
         }
         elsif ($trackname eq "PART KEYS")
         {
            $songinfo{'KEYS'} = 1;
         }
         elsif ($trackname eq "PART REAL_GUITAR")
         {
            $songinfo{'PRO_GUITAR'} = 1;
         }
         elsif ($trackname eq "PART REAL_BASS")
         {
            $songinfo{'PRO_BASS'} = 1;
         }
         elsif ($trackname eq "PART REAL_KEYS_E")
         {
            $songinfo{'PRO_KEYS_E'} = 1;
            $songinfo{'PRO_KEYS'} = 1;
         }
         elsif ($trackname eq "PART REAL_KEYS_M")
         {
            $songinfo{'PRO_KEYS_M'} = 1;
            $songinfo{'PRO_KEYS'} = 1;
         }
         elsif ($trackname eq "PART REAL_KEYS_H")
         {
            $songinfo{'PRO_KEYS_H'} = 1;
            $songinfo{'PRO_KEYS'} = 1;
         }
         elsif ($trackname eq "PART REAL_KEYS_X")
         {
            $songinfo{'PRO_KEYS_X'} = 1;
            $songinfo{'PRO_KEYS'} = 1;
         }
         elsif ($trackname eq "PART KEYS_ANIM_RH")
         {
            $songinfo{'KEYS_ANIM_RH'} = 1;
         }
         elsif ($trackname eq "PART KEYS_ANIM LH")
         {
            $songinfo{'KEYS_ANIM_LH'} = 1;
         }
         elsif ($trackname eq "PART VOCALS")
         {
            $songinfo{'VOCALS'} = 1;
         }
         elsif ($trackname eq "EVENTS")
         {
            $songinfo{'EVENTS'} = 1;
         }
         elsif ($trackname eq "BEAT")
         {
            $songinfo{'BEAT'} = 1;
         }
         elsif ($trackname eq "VENUE")
         {
            $songinfo{'VENUE'} = 1;
         }
         else
         {
            $songinfo{'shortname'} = $trackname;
         }

         if (! defined($ar[1][0]))
         {
            print "Warning: track $i has no events!\n";
            push @empties, $i;
         }

         $i++;
      }
   }

   if ($songinfo{'shortname'})
   {
      debug "song has shortname " . $songinfo{'shortname'} ."\n";
   }
   if ($songinfo{'DRUMS'})
   {
      debug "song has drums\n";
   }
   if ($songinfo{'PRO_DRUMS'})
   {
      debug "song has pro drums\n";
   }
   if ($songinfo{'GUITAR'})
   {
      debug "song has guitar\n";
   }
   if ($songinfo{'PRO_GUITAR'})
   {
      debug "song has pro guitar\n";
   }
   if ($songinfo{'BASS'})
   {
      debug "song has bass\n";
   }
   if ($songinfo{'PRO_BASS'})
   {
      debug "song has pro bass\n";
   }
   if ($songinfo{'KEYS'})
   {
      debug "song has keys\n";
   }
   if ($songinfo{'PRO_KEYS'})
   {
      debug "song has pro keys\n";
   }
   if ($songinfo{'num_harm'})
   {
      if ($songinfo{'num_harm'} > 1)
      {
         debug "song has $songinfo{'num_harm'} part harmonies\n";
      }
      else
      {
         debug "song has standard vocals (no harmonies)\n";
      }
   }
   if (@empties)
   {
      print "$one has " . scalar( $opus->tracks ) . " tracks\n";
      print "song has empty tracks. deleting...\n";

      while (@empties)
      {
         $i = pop(@empties);
         print "deleting track $i\n";
         my $tracks_r = $opus->tracks_r();
         splice(@$tracks_r, $i, 1);
      }
#      $opus->write_to_file("new.mid");
   }
}




