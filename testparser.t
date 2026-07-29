#!/usr/bin/env perl

use strict;
use warnings;
use Test::More;

my %tests = (
     "2not3.dta"             => 3,
     "beethovensc.dta"       => 1,
     "coheed.dta"            => 1,
     "cruefest.dta"          => 1,
     "dontgoawaymad.dta"     => 1,
     "dontgoawaymad.dta2"    => 1,
     "facedowninthedirt.dta" => 1,
     "fijatebien.dta"        => 1,
     "foo.dta"               => 4,
     "fourdegrees.dta"       => 1,
     "funk49.dta"            => 1,
     "gthang.dta"            => 1,
     "lobotomy.dta"          => 1,
     "million.dta"           => 1,
     "moresnow.dta"          => 1,
     "orion.dta"             => 1,
     "poker.dta"             => 1,
     "runaway.dta"           => 1,
     "rush.dta"              => 7,
     "rush.dta1"             => 1,
     "silent.dta"            => 1,
     "snow.dta"              => 1,
     "songs.dta"             => 1,
     "songs.dta-noindent"    => 1,
     "songs.dta-quoted"      => 1,
     "songs.dta.orig"        => 9,
     "songs.dta.large"       => 1898,
     "starroving.dta"        => 1,
     "stayin.dta"            => 1,
     "subdiv.dta"            => 1,
     "sugarforthepill.dta"   => 1,
     "sweethome.dta"         => 1,
     "sweethome.dtamac"      => 1,
     "sweethome.dtaunix"     => 1,
     "sweethome.dtawin"      => 1,
     "tmp.dta"               => 1,
     "tuttoepossibile.dta"   => 1,
     "uberalles.dta"         => 1,
     "under.dta"             => 16,
     "upgrades.dta"          => 17,
     "upgrades.dta.bak"      => 1,
     "upgrades.dta2"         => 2,
     "wanted.dta"            => 1,
     "would.dta"             => 5,
     "zeroid.dta"            => 9
);

plan tests => scalar(keys %tests);

foreach my $dta (sort keys %tests) {
   # Capture command output
   my $output = `./c3ps3tool.pl --c3config testdta/ps3.config --dtaparse testdta/$dta`;

   # Remove the trailing newline
   chomp($output);

   $output =~ /found (\d+) songs/;

   my $actual = $1;
   my $expected = $tests{$dta};

   # Test if the output matches expectations
   is($actual, $expected, $dta);
}
