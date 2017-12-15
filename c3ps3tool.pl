#!/usr/bin/perl

use strict;
use warnings;

# non-core modules:
use Net::FTP::Recursive;
use Text::CSV::Hashify;
use String::ShellQuote;
# core modules:
use File::Temp ':mktemp';
use File::Path;
use File::Spec;
use Cwd;
use POSIX qw(strftime);
use Getopt::Long;
use Pod::Usage;
use Text::Balanced qw(extract_bracketed);
use Time::HiRes qw(usleep);

# constants/default values
use constant VERSION     => "0.2.0";
use constant SONGFILE    => "songs.dta";
use constant SONGDIR     => "songs";
use constant UPGRADEFILE => "upgrades.dta";
use constant UPGRADEDIR  => "songs_upgrades";
use constant ORIGEXT     => ".orig";
use constant ENCREXT     => ".edat";
use constant SONGIDFMT   => "%d%d%05d";

# program mode types
use constant NONE        => "NONE";
use constant INSTALL     => "INSTALL";
use constant UPGRADE     => "UPGRADE";
use constant UNINSTALL   => "UNINSTALL";
use constant UNUPGRADE   => "UNUPGRADE";
use constant DTAPARSE    => "DTAPARSE";
use constant ENCRYPT     => "ENCRYPT";

# debug print levels.
use constant QUIET       => 0; # only print on error
use constant NORMAL      => 1; # normal run output
use constant DEBUG       => 2; # extra debug output
use constant VERYVERBOSE => 3; # even more extra debug output

# constants used throughout
my $backupext   = "." . strftime("%Y%m%d%H%M%S", localtime(time));

# command-line configurable options:
my $custombase  = "/dev_hdd0/game/BLUS30463/USRDIR/HMX0756/";
#my $dtalist     = "PS3_DTA_LIST.csv";
my $dtalist     = "/work/rb3custom/tools/perl/PS3_DTA_LIST.csv";
my $mididir     = "";
my $ip          = "192.168.1.30";
#my $ip          = "localhost";
my $port        = 21;
my $user        = "anonymous";
my $pass        = '-anonymous@';
my $searchpath  = "";
my $logfile     = "";
#my $c3config    = "ps3.config";
my $c3config    = "/work/rb3custom/tools/perl/ps3.config";
my $configfile  = File::Spec->catfile($ENV{'HOME'}, ".c3ps3toolrc");

# options for building a make_npdata command to encrypt a mid to mid.edat:
my $npdataPath  = "/work/rb3custom/tools/npdata/make_npdata-master/Linux/make_npdata";
my $npdataOpts  = "1 1 2 0 16 3 00 UP8802-BLUS30463_00-RBHMXBANDCCFF0D6 8 0B72B62DABA8CAFDA3352FF979C6D5C2";
my $npdataCmdFmt = $npdataPath . " -v -e %s %s " . $npdataOpts;
my $npdataCmd   = sprintf($npdataCmdFmt, "infile", "infile" . ENCREXT);

my $verbose     = NORMAL;
my $quiet       = 0;
my $debug       = 0;
my $noorig      = 0;
my $nobackup    = 0;
my $reinstall   = 0;
my $readonly    = 0;
my $ftpsleep    = 100000; # microseconds, so = 100ms or 0.1s
my $ftptimeout  = 120;
my $logfh;
my $tmptemplate = "/tmp/c3ps3toolXXXXXX";
my $mode        = NONE;

# global vars
my @filesToRemove;
my @dirsToRemove;

my @midiuploadlist;
my @uploadlist;
my %songupgradelist;
my $needupload    = 0;
my $lastpath      = "";
my $nummidi       = 0;
my $numdta        = 0;
my $configUpdated = 0;

# function prototypes
sub myprint($@);
sub findExistingSong($$);
sub printdir($);
sub rget_dir($$$);
sub rput_dir($$$);
sub doesFileExist($$);
sub ftpcopy($$$);
sub searchForUpgrades($$);
sub readConfig();
sub writeConfig($);
sub checkSetMode($);
sub setSearchPath(@);

#
# #############################################################################
Getopt::Long::Configure ("bundling", "ignorecase_always");
GetOptions("custombase=s"  => \$custombase,
           "dtalist=s"     => \$dtalist,
           "mididir=s"     => \$mididir,
           "ip=s"          => \$ip,
           "port=i"        => \$port,
           "user=s"        => \$user,
           "pass=s"        => \$pass,
           "ftpsleep=i"    => \$ftpsleep,
           "ftptimeout=i"  => \$ftptimeout,
           "c3config=s"    => \$c3config,
           "cofigfile=s"   => \$configfile,
           "veryverbose"   => sub { $verbose = VERYVERBOSE; },
           "verbose|debug" => sub { $verbose = DEBUG; },
           "quiet"         => sub { $verbose = QUIET; },
           "noorig"        => \$noorig,
           "nobackup"      => \$nobackup,
           "reinstall"     => \$reinstall,
           "readonly"      => \$readonly,
           "tmptemplate=s" => \$tmptemplate,
           "search=s"      => \&setSearchPath,
           "logfile=s"     => \$logfile,
           "install"       => sub { checkSetMode(INSTALL); },
           "upgrade"       => sub { checkSetMode(UPGRADE); },
           "uninstall"     => sub { checkSetMode(UNINSTALL); },
           "unupgrade"     => sub { checkSetMode(UNUPGRADE); },
           "dtaparse"      => sub { checkSetMode(DTAPARSE); },
           "encrypt"       => sub { checkSetMode(ENCRYPT); },
           "version"       => sub { print "version " . VERSION . "\n"; exit(0); },
           "help"          => sub { pod2usage( -verbose => 1, -exitval => 0 ); },
           "man"           => sub { pod2usage( -verbose => 2, -exitval => 0 ); },
          ) or pod2usage(-verbose => 1) && exit;

if ($logfile)
{
   open($logfh, ">", $logfile) or die "cannot open $logfile for writing!\n: $!";
}

myprint DEBUG, "mode=$mode, search=$searchpath\n";
die unless $mode ne NONE;


my $config = readConfig();
foreach my $key (sort keys %{$config})
{
   myprint DEBUG, $key . "=" . $config->{$key} . "\n";
}

myprint DEBUG, "backupext=$backupext\n";


#die "dying\n";

if ($mode eq UPGRADE)
{
   upgradeFiles();
}
elsif ($mode eq INSTALL)
{
   installFiles();
}
elsif ($mode eq UNUPGRADE)
{
   die "unupgrade not yet implimented.\n";
}
elsif ($mode eq UNINSTALL)
{
   die "uninstall not yet implimented.\n";
}
elsif ($mode eq DTAPARSE)
{
   dtaparse();
}
elsif ($mode eq ENCRYPT)
{
   encryptFiles();
}
else
{
   die "unexpected mode!\n";
}



# this should always fire, even on a die, and clean up any temp files we
# created.
END
{
   if ($@)
   {
      myprint DEBUG, "died on $lastpath\n";
   }
   foreach my $file (@filesToRemove)
   {
      unlink $file;
   }
   foreach my $dir (@dirsToRemove)
   {
      rmtree $dir;
   }
   if ($logfile)
   {
      close $logfh;
   }
}


# #############################################################################
# main functions
# #############################################################################

# 
# #############################################################################
sub upgradeFiles
{

   # Read in the CSV file generated by C3 Con Tools >= 3.60 that contains info
   # on all files on the ps3.
   #
   # Note: there's a bug in 3.60 where if a song name contains quotes, they
   #       aren't escaped correctly. Fall Out Boy's A Little Less Sixteen
   #       Candles has this, so if you exported your csv on this version you'll
   #       have to manually edit this line and double up the quotes around
   #       "Touch Me" to ""Touch Me"".
   # ##########################################################################
   my $obj = Text::CSV::Hashify->new( { 'file' => $dtalist, 'format' => 'aoh' }, );
   my $csv = $obj->all;


   # If the user passed in a search path, scan through it looking for possible
   # upgrades, cross referencing with the CSV above. This will compose a list of
   # paths to install.
   # -----------------------------------------------------------------------------
   if ($searchpath)
   {
      push @ARGV, @{searchForUpgrades($csv, $searchpath)};
   }


   # Process the list of directories given.
   if (@ARGV)
   {

      # make the connection to the ps3 ftp server.
      # ##########################################################################
      my $ftp = Net::FTP::Recursive->new(Host    => $ip,
                                         Port    => $port,
                                         Debug   => ($verbose > 1 ? 1 : 0),
                                         Timeout => $ftptimeout)
         or die "Cannot connect to $ip: $@";

      $ftp->login($user, $pass)
         or die "Cannot login ", $ftp->message;

      $ftp->binary()
         or die "Cannot set mode to binary ", $ftp->message;

      # fetch current RBHP upgrades.dta into a temp file.
      # ##########################################################################
      my $upgradedta = mktemp($tmptemplate);
      push @filesToRemove, $upgradedta;
      myprint DEBUG, "upgradedta=$upgradedta\n";
      my $existingupgraderef = {};

      if ( doesFileExist($ftp, $custombase . UPGRADEDIR) )
      {
         myprint DEBUG, "upgrade directory exists\n";

         myprint DEBUG, "upgradedta=$upgradedta\n";
         $ftp->cwd($custombase . UPGRADEDIR)
            or die "Cannot change working directory to $custombase", $ftp->message;

         if ( doesFileExist($ftp, $custombase . UPGRADEDIR . "/" . UPGRADEFILE) )
         {
            $ftp->get( UPGRADEFILE, $upgradedta)
               or die "Cannot get " . UPGRADEFILE, $ftp->message;
            if ($ftpsleep) { usleep($ftpsleep); }

            $existingupgraderef = parseDTA($upgradedta, 1);
            my $numexisting = @{$existingupgraderef};
            myprint DEBUG, "initial upgrade.dta has " . $numexisting . " upgrades\n";

            if (! $numexisting)
            {
               die "existing dta has no songs!\n";
            }
         }
         else
         {
            $existingupgraderef = [];
         }
      }
      else
      {
         # upgrade directory doesn't exist, create it.
         myprint DEBUG, "upgrade directory doesn't exist, creating it\n";
	 if (!$readonly) {
            $ftp->mkdir(UPGRADEDIR)
               or die "Cannot create upgrade directory " . $custombase . UPGRADEDIR, $ftp->message;
         }
      }

      foreach my $upgrade (@ARGV)
      {
         myprint DEBUG, "processing $upgrade\n";

         $lastpath = $upgrade;
         my %upgradeinfo;
         $upgradeinfo{'path'} = $upgrade;

         # read new song upgrade info and append/replace in existing upgrade info
         # #######################################################################
         $upgradeinfo{'upgradedta'} = File::Spec->catfile($upgrade, UPGRADEFILE);
         $upgradeinfo{'newsongdta'} = File::Spec->catfile($upgrade, SONGFILE);

         $upgradeinfo{'upgradeparsed'} = parseDTA($upgradeinfo{'upgradedta'});
         $upgradeinfo{'newsongparsed'} = parseDTA($upgradeinfo{'newsongdta'});

         my $numup = @{$upgradeinfo{'upgradeparsed'}};
         if (! $numup)
         {
            die "upgrades.dta has no songs!\n";
         }

         my $numnew = @{$upgradeinfo{'newsongparsed'}};
         if (! $numnew)
         {
            die "upgrade songs.dta dta has no songs!\n";
         }

         if ($numnew != $numup)
         {
            die "number of songs in upgrades.dta and songs.dta must match!\n";
         }

         # $newupgrade == entry from new upgrades.dta
         # $newsongdta == entry from new songs.dta
         foreach my $newsongdta (@{$upgradeinfo{'newsongparsed'}})
         {
            my $newupgrade = findkey($upgradeinfo{'upgradeparsed'}, $newsongdta->{'shortname'})
               or die "could not find song $newsongdta->{'shortname'} in $upgradeinfo{'upgradeparsed'}!\n";

            # we need the new songs.dta to replace the existing stock one.
            #
            # when we alter the original songs.dta file, we must update them all
            # the same way (for cases where the user has multiple copies of the
            # same song).
            # ####################################################################
            $upgradeinfo{'originfo'} = findExistingSong($csv, $newsongdta->{'shortname'});
            foreach my $match (@{$upgradeinfo{'originfo'}})
            {

               # If we haven't seen this target dta before, create an entry for
               # it. This will allow us to do multiple updates to the same file
               # with only one read+write as opposed to one for each song.
               if (! $songupgradelist{ $match->{'DTA Path'} })
               {
                  my %newentry;
                  $newentry{'local'}  = mktemp($tmptemplate);
                  push @filesToRemove, $newentry{'local'};
                  myprint DEBUG, "local=$newentry{'local'}\n";
                  $newentry{'remote'} = $match->{'DTA Path'};

                  myprint DEBUG, "oldsongdta=" . $newentry{'remote'} . "\n";
                  $ftp->get( $newentry{'remote'}, $newentry{'local'})
                     or die "Cannot get " . $newentry{'remote'}, $ftp->message;
                  if ($ftpsleep) { usleep($ftpsleep); }

                  $newentry{'dta'} = parseDTA($newentry{'local'});
                  myprint DEBUG, "newentry=" . $newentry{'dta'} . "\n";

                  my $newsanity = findkey($newentry{'dta'}, $newsongdta->{'shortname'})
                     or die "could not find song $newsongdta->{'shortname'} in $newentry{'dta'}!\n";

                  $songupgradelist{ $match->{'DTA Path'} } = \%newentry;
               }
               my $upgradedta = $songupgradelist{ $match->{'DTA Path'} };

               # find the entry we want to change within the newly-read stock
               # songs.dta
               my $oldsong = findkey($upgradedta->{'dta'}, $newsongdta->{'shortname'});

               # sanity checking between stock+new
               if (!$oldsong)
               {
                  die "new shortname " . $newsongdta->{'shortname'} . " not found "
                      . "in existing dta!\n";
               }
               elsif ($newsongdta->{'shortname'} ne $oldsong->{'shortname'})
               {
		  # unquoted name will be treated as lowercase - unless it is quoted.
		  # so having an unquoted name match a quoted one only works if the
		  # unquoted one is also lowercase.
                  if (   (   $newsongdta->{'shortname'} =~ /^['"]+.+['"]+$/
                          && lc(substr($newsongdta->{'shortname'}, 1, -1)) eq lc($oldsong->{'shortname'}))
                      || (   $oldsong->{'shortname'} =~ /^['"]+.+['"]+$/
                          && lc(substr($oldsong->{'shortname'}, 1, -1)) eq lc($newsongdta->{'shortname'})))
                  {
                     myprint DEBUG, "new shortname " . $newsongdta->{'shortname'} . " and old shortname "
                         . $oldsong->{'shortname'} . " approximate match. equalizing...\n";

                     my $tmpnew = $oldsong->{'shortname'};
                     $newsongdta->{'_raw'} =~ s/^(\(\s*)(['"]?)([a-zA-Z0-9_-]+)(['"]?)(\s*)/$1$tmpnew$5/s;
                     $newsongdta->{'shortname'} = $tmpnew;
                     myprint VERYVERBOSE, "fixed dta (" . $newsongdta->{'shortname'} . "):\n";
                     myprint VERYVERBOSE, $newsongdta->{'_raw'} . "\n";
                     
                  }
                  else
                  {
                     die "new shortname " . $newsongdta->{'shortname'} . " and old shortname "
                         . $oldsong->{'shortname'} . " do not match!\n";
                  }
               }

               # cut the old version out of the dta, then insert our new one.
               # Use $oldsong since it's the one guaranteed to match.
               @{$upgradedta->{'dta'}} = grep { $_->{'shortname'} ne $oldsong->{'shortname'} } @{$upgradedta->{'dta'}};
               push @{$upgradedta->{'dta'}}, $newsongdta;
            }

            # Sanity tests on upgrades.dta + new songs.dta combo
            #
            # if we find mismatches, we'll trust the songs.dta over the
            # upgrades.dta and make it match songs.dta.
            if ($newsongdta->{'shortname'} ne $newupgrade->{'shortname'})
            {
               my $tmpnew = $newsongdta->{'shortname'};
               my $tmpold = $newupgrade->{'shortname'};
               if ($newsongdta->{'shortname'} =~ /^['"]+.+['"]+$/)
               {
                  $tmpnew = substr($newsongdta->{'shortname'}, 1, -1);
               }
               if ($newupgrade->{'shortname'} =~ /^['"]+.+['"]+$/)
               {
                  $tmpold = substr($newupgrade->{'shortname'}, 1, -1);
               }

               # case mismatch, and maybe quotes. correct it and continue.
               if (lc($tmpnew) eq lc($tmpold))
               {
                  myprint DEBUG,   "songs.dta shortname "
                                 . $newsongdta->{'shortname'}
                                 . " and upgrades.dta shortname "
                                 . $newupgrade->{'shortname'}
                                 . " do not match! fixing upgrades.dta\n";
                  $tmpnew = $newsongdta->{'shortname'};
                  $newupgrade->{'_raw'} =~ s/^(\(\s*)(['"]?)([a-zA-Z0-9_-]+)(['"]?)(\s*)/$1$tmpnew$5/s;
                  $newupgrade->{'shortname'} = $tmpnew;
                  myprint VERYVERBOSE, "fixed dta (" . $newupgrade->{'shortname'} . "):\n";
                  myprint VERYVERBOSE, $newupgrade->{'_raw'} . "\n";
               }
               else
               {
                  die "songs.dta shortname " . $newsongdta->{'shortname'} . " and upgrades.dta shortname "
                      . $newupgrade->{'shortname'} . " do not match!\n";
               }
            }

            if (   $newsongdta->{'song_id'} && $newupgrade->{'song_id'}
                && $newsongdta->{'song_id'} ne $newupgrade->{'song_id'})
            {
               die "songs.dta song_id " . $newsongdta->{'song_id'} . " and upgrades.dta song_id "
                   . $newupgrade->{'song_id'} . " do not match!\n";
            }

            # If the song already exists in the upgrades.dta, by default we won't
            # install unless the upgrade we're processing is newer. The
            # --reinstall flag can be used to force removal and re-upload of an
            # upgrade, to cover cases where we want to replace the existing info.
            my $found = findkey($existingupgraderef, $newupgrade->{'shortname'});
            if ($found)
            {
               if ($found->{'upgrade_version'} < $newupgrade->{'upgrade_version'})
               {
                  myprint NORMAL, "song " . $newupgrade->{'shortname'} . " exists but will be upgraded.\n";
                  @$existingupgraderef = grep { $_->{'shortname'} ne $newupgrade->{'shortname'} } @{$existingupgraderef};
               }
               elsif ($reinstall)
               {
                  myprint NORMAL, "song " . $newupgrade->{'shortname'} . " exists but will be reinstalled.\n";
                  @$existingupgraderef = grep { $_->{'shortname'} ne $newupgrade->{'shortname'} } @{$existingupgraderef};
               }
               else
               {
                  myprint NORMAL, "song " . $newupgrade->{'shortname'} . " already installed! skipping...\n";
                  next;
               }
            }
            else
            {
               myprint NORMAL, "song " . $newupgrade->{'shortname'} . " will be installed.\n";
            }

            my $numexisting = @{$existingupgraderef};
            myprint DEBUG, "after checking for existing, upgrade.dta has " . $numexisting . " upgrades\n";


            # Now find the midi file associated with this upgrade. Not all
            # songs.dta files have a midi_file field, but they seem to always be
            # present in an upgrade file, so use this to create the filename. Look
            # for the file in this directory first.
            #
            # Since C3 Con Tools can do a bulk encryption for all files in a
            # directory, also have an option for a dedicated "encrypted midi
            # directory" that has all of them. Check here second.
            $upgradeinfo{'midi'} = $newupgrade->{'midi_file'};
            $upgradeinfo{'midi'} =~ s|songs_upgrades/||;
            $upgradeinfo{'midi_unenc'} = $upgradeinfo{'midi'};
            $upgradeinfo{'midi'} .= ".edat";

            if (-f (File::Spec->catfile($upgrade, $upgradeinfo{'midi'})))
            {
               # song exists in upgrade path
               $upgradeinfo{'midi'} = File::Spec->catfile($upgrade, $upgradeinfo{'midi'});
            }
            elsif (   $mididir
                   && (-f (File::Spec->catfile($mididir, $upgradeinfo{'midi'}))))
            {
               # song exists in separate midi path
               $upgradeinfo{'midi'} = File::Spec->catfile($mididir, $upgradeinfo{'midi'});
            }
            elsif (-f (File::Spec->catfile($upgrade, lc($upgradeinfo{'midi'}))))
            {
               # song exists in upgrade path, but case is wrong - fix it.
               myprint DEBUG, "midi file " . File::Spec->catfile($upgrade, lc($upgradeinfo{'midi'}))
                     . " is wrong case, fixing.\n";
               my $tmpfile = File::Spec->catfile($upgrade, $upgradeinfo{'midi'} . "tmp");
               rename(File::Spec->catfile($upgrade, lc($upgradeinfo{'midi'})), $tmpfile);
               rename($tmpfile, File::Spec->catfile($upgrade, $upgradeinfo{'midi'}));
               $upgradeinfo{'midi'} = File::Spec->catfile($upgrade, $upgradeinfo{'midi'});
            }
            elsif (   $mididir
                   && (-f (File::Spec->catfile($mididir, lc($upgradeinfo{'midi'})))))
            {
               # song exists in separate midi path, but case is wrong - fix it.
               myprint DEBUG, "midi file " . File::Spec->catfile($mididir, lc($upgradeinfo{'midi'}))
                     . " is wrong case, fixing.\n";
               my $tmpfile = File::Spec->catfile($mididir, $upgradeinfo{'midi'} . "tmp");
               rename(File::Spec->catfile($mididir, lc($upgradeinfo{'midi'})), $tmpfile);
               rename($tmpfile, File::Spec->catfile($mididir, $upgradeinfo{'midi'}));
               $upgradeinfo{'midi'} = File::Spec->catfile($mididir, $upgradeinfo{'midi'});
            }
            elsif (-f (File::Spec->catfile($upgrade, $upgradeinfo{'midi_unenc'})))
            {
               # unencrypted midi file exists in upgrade path, try to encrypt
               # it
               my $res = encryptFile(File::Spec->catfile($upgrade, $upgradeinfo{'midi_unenc'}));
               if ($res ne File::Spec->catfile($upgrade, $upgradeinfo{'midi'}))
               {
                  die "unable to encrypt $upgradeinfo{'midi_unenc'} to $upgradeinfo{'midi'}!\n";
               }
            }
            else
            {
               die "upgrade file $upgradeinfo{'midi'} not found!\n";
            }

            myprint DEBUG, "upgrade midi file found at $upgradeinfo{'midi'}\n";


            # Append the upgrade.dta info to the existing file.
            push @{$existingupgraderef}, $newupgrade;

            $numexisting = @{$existingupgraderef};
            myprint DEBUG, "after appending, new upgrade.dta has " . $numexisting . " upgrades\n";

            # add the current midi file to the upload list.
            push @midiuploadlist, $upgradeinfo{'midi'};
            $needupload = 1;

         }
      }



      # we've done all the processing of input files, now we need to upload the
      # new content back to the ps3.

      if ($needupload)
      {
         $ftp->cwd($custombase . UPGRADEDIR)
            or die "Cannot change working directory to $custombase", $ftp->message;

         # phase 1: upload the new midi files
         # -----------------------------------------------------------------------
         foreach my $upfile (@midiuploadlist)
         {
            myprint NORMAL, "uploading $upfile\n";
	    if (!$readonly) {
               $ftp->put($upfile);
            }
            if ($ftpsleep) { usleep($ftpsleep); }
            $nummidi++;
         }

         # phase 2: upload the new upgrades.dta
         # -----------------------------------------------------------------------
         # make backup of current upgrades.dta
         if (   ! $nobackup
             && doesFileExist($ftp, $custombase . UPGRADEDIR . "/". UPGRADEFILE) )
         {
	    if (!$readonly) {
               ftpcopy($ftp, UPGRADEFILE, UPGRADEFILE . $backupext);
            }
            myprint DEBUG, "backing up " . UPGRADEFILE . "\n";
            if ($ftpsleep) { usleep($ftpsleep); }
         }
         writeDTA($existingupgraderef, $upgradedta);

         myprint NORMAL, "uploading new " . UPGRADEFILE . " to " . $custombase . UPGRADEDIR . "\n";
	 if (!$readonly) {
            $ftp->put( $upgradedta, UPGRADEFILE )
               or die "Cannot put " . UPGRADEFILE, $ftp->message;
         }
         if ($ftpsleep) { usleep($ftpsleep); }
         $numdta++;

         # phase 3: upload the updated songs.dta files
         # -----------------------------------------------------------------------
         foreach my $dta (sort keys %songupgradelist)
         {
            my $upgradedta = $songupgradelist{ $dta };

            # before we touch a stock songs.dta for the first time, save it as
            # .orig.
            if (   ! $noorig
                && ! doesFileExist($ftp, $upgradedta->{'remote'} . ORIGEXT) )
            {
               myprint DEBUG, "saving original " . SONGFILE . "\n";
	       if (!$readonly) {
                  ftpcopy($ftp, $upgradedta->{'remote'},
                          $upgradedta->{'remote'} . ORIGEXT);
               }
               if ($ftpsleep) { usleep($ftpsleep); }
            }
            # make backup of current songs.dta on the ps3
            elsif (! $nobackup)
            {
               myprint DEBUG, "backing up " . SONGFILE . "\n";
	       if (!$readonly) {
                  ftpcopy($ftp, $upgradedta->{'remote'},
                          $upgradedta->{'remote'} . $backupext);
               }
               if ($ftpsleep) { usleep($ftpsleep); }
            }

            # write the updated one to disc locally
            writeDTA($upgradedta->{'dta'}, $upgradedta->{'local'});

            # upload it to the server
            myprint NORMAL, "uploading new " . SONGFILE . " to $upgradedta->{'remote'}\n";
	    if (!$readonly) {
               $ftp->put($upgradedta->{'local'}, $upgradedta->{'remote'})
                  or die "Failed to rename " . SONGFILE . " to "
                         . SONGFILE . $backupext, $ftp->message;
            }
            if ($ftpsleep) { usleep($ftpsleep); }
            $numdta++;

         }

         myprint NORMAL, "successfully uploaded $nummidi upgraded midis and $numdta upgraded dtas\n";
      }









      $ftp->quit;
   }

   return;
}

# 
# #############################################################################
sub installFiles
{

   # Process the list of packages given.
   if (@ARGV)
   {
      my %installinfo;

      # make the connection to the ps3 ftp server.
      # ##########################################################################
      my $ftp = Net::FTP::Recursive->new(Host    => $ip,
                                         Port    => $port,
                                         Debug   => ($verbose > 1 ? 1 : 0),
                                         Timeout => $ftptimeout)
         or die "Cannot connect to $ip: $@";

      $ftp->login($user, $pass)
         or die "Cannot login ", $ftp->message;

      $ftp->binary()
         or die "Cannot set mode to binary ", $ftp->message;

      $ftp->cwd($custombase)
         or die "Cannot change working directory to $custombase", $ftp->message;

      printdir($ftp);

      # fetch current customs songs.dta into a temp file.
      my $songdta = mktemp($tmptemplate);
      push @filesToRemove, $songdta;

      myprint DEBUG, "songdta=$songdta\n";
      $ftp->cwd($custombase . SONGDIR)
         or die "Cannot change working directory to $custombase", $ftp->message;
      $ftp->get( SONGFILE, $songdta)
         or die "Cannot get " . SONGFILE, $ftp->message;

      my $existingsongref = parseDTA($songdta, 0, 0);
      my $numexisting = @{$existingsongref};
      myprint DEBUG, "existing custom dir has " . $numexisting . " songs\n";

      if (! $numexisting)
      {
         die "existing dta has no songs!\n";
      }

      foreach my $rar (@ARGV)
      {
         $installinfo{'rar'}    = $rar;
         $installinfo{'rardir'} = mktemp($tmptemplate);
         push @dirsToRemove, $installinfo{'rardir'};
         mkdir $installinfo{'rardir'};
         myprint DEBUG, "rar = $installinfo{'rar'}\n";
         myprint DEBUG, "rardir = $installinfo{'rardir'}\n";

         # read new song upgrade info and append/replace in existing upgrade
         # info
         # ####################################################################

         # fetch current customs songs.dta into a temp file.

         # EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE
         # BIG FAT HACK
         # only works on linux with unrar command...unless windows has one too?
         # EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE
	 my @updirs;
	 if ($installinfo{'rar'} =~ /\.rar$/i) {
            my $unrarcmd = "unrar x " . shell_quote($installinfo{'rar'}) . " " . $installinfo{'rardir'};
            my $res = `$unrarcmd`;
            myprint DEBUG, $res unless ($res =~ /All OK/);

            # should be exactly two creates - one for base, one for base/gen. this is a
            # hacky way to skip the first despite it being what we want and just cut it
            # off the gen line should the order be pathological.
            @updirs = map { /Creating\s+(\S+)\/gen\s+OK/ ? $1 : () } split(/\n/, $res);
            foreach my $updir (@updirs)
            {
               myprint DEBUG, "updir = $updir\n";
            }

	 } elsif ($installinfo{'rar'} =~ /\.zip$/i) {
            my $unzipcmd = "unzip -n -d " . $installinfo{'rardir'} . " " . shell_quote($installinfo{'rar'});
            my $res = `$unzipcmd`;
            myprint DEBUG, $res if ($res =~ /cannot find zipfile directory/);

            # should be exactly two creates - one for base, one for base/gen. this is a
            # hacky way to skip the first despite it being what we want and just cut it
            # off the gen line should the order be pathological.
            @updirs = map { /creating:\s+(\S+)\/gen/ ? $1 : () } split(/\n/, $res);
            foreach my $updir (@updirs)
            {
               myprint DEBUG, "updir = $updir\n";
            }
	 }

         my $newsong = File::Spec->catfile($installinfo{'rardir'}, "songs.dta");

         my $newsongref = parseDTA($newsong);
         my $numnew = @{$newsongref};

         if (! $numnew)
         {
            die "new dta has no songs!\n";
         }

         foreach my $song ( @{ $newsongref } )
         {
            if (findkey($existingsongref, $song->{'shortname'}))
            {
               if ($reinstall) {
                  myprint NORMAL, "song " . $song->{'shortname'} . " already installed - reinstalling!\n";
                  @{$existingsongref} = grep { $_->{'shortname'} ne $song->{'shortname'} } @{$existingsongref};
               } else {
                  myprint NORMAL, "song " . $song->{'shortname'} . " already installed - skipping!\n";
		  next;
               }
            }

            my $closematches = findByClosename($existingsongref, $song->{'closename'});
	    foreach my $closematch (@{$closematches}) {
               myprint NORMAL, "WARNING: song " . $song->{'shortname'} . " has near match with existing song $closematch->{'shortname'}!\n";
            }

            # check whether the song has a non-numeric song_id, and if so it
            # will replace it with a proper numeric one. PS3 will work OK with
            # a non-numeric ID, but scores won't save correctly unless it is
            # numeric.
            checkAndFixSongid($song, $config);

            # we need to do a couple of things here:
            # 1) merge the new song into existing
            push @{$existingsongref}, $song;

            # 2) put the directory on the upload list
            my $songpath = $song->{'song_path'};
            if ($songpath)
            {
               # the songpath looks like songs/<songname>/<songname> and we
               # just want one of those <songname>s
               if ($songpath =~ m|songs/([^\/]+)/.+|)
               {
                  $songpath = File::Spec->catfile($installinfo{'rardir'}, $1);
                  # now we need the corresponding upload directory, which should
                  # be $rardir/$songpath. check that this is in @updirs
                  if (grep( /^\Q$songpath\E$/, @updirs))
                  {
                     myprint DEBUG, "adding $songpath to uploadlist\n";
                     # upload dir found! push it onto the list
                     push @uploadlist, $songpath;
                  }
                  else
                  {
                     die "song directory not in list!\n";
                  }
               }
               else
               {
                  die "songpath did not match format!\n";
               }
            }
            else
            {
               die "song_path not found in dta!\n";
            }

            # 3) set flag to indicate we'll need to write the new dta + upload stuff.
            $needupload = 1;
         }
      }

      # installs are simpler than upgrades - just one master dta to write and
      # the song directory to upload.
      if ($needupload)
      {
         my $abssongdir = File::Spec->catdir($custombase, SONGDIR);
         $ftp->cwd($abssongdir)
            or die "Cannot change working directory to $abssongdir", $ftp->message;

         # phase 1: upload the new song directories
         # -----------------------------------------------------------------------
         foreach my $updir (@uploadlist)
         {
            myprint NORMAL, "uploading song from " . $updir . "\n";
	    if (!$readonly) {
               rput_dir($ftp, $updir, $abssongdir);
            }
         }


         # phase 2: upload the new songs.dta
         # -----------------------------------------------------------------------
         # before we touch a stock songs.dta for the first time, save it as
         # .orig.
         my $origfile = File::Spec->catfile($abssongdir, SONGFILE . ORIGEXT);
         if (   ! $noorig
             && ! doesFileExist($ftp, $origfile) )
         {
            myprint DEBUG, "saving original " . SONGFILE . "\n";
	    if (!$readonly) {
               ftpcopy($ftp, SONGFILE, SONGFILE . ORIGEXT);
            }
            if ($ftpsleep) { usleep($ftpsleep); }
         }
         # make backup of current songs.dta
         elsif (! $nobackup)
         {
            myprint DEBUG, "backing up existing " . SONGFILE . "\n";
	    if (!$readonly) {
               ftpcopy($ftp, SONGFILE, SONGFILE . $backupext);
            }
            if ($ftpsleep) { usleep($ftpsleep); }
         }
         writeDTA($existingsongref, $songdta);

         myprint NORMAL, "uploading new " . SONGFILE . "\n";
	 if (!$readonly) {
            $ftp->put( $songdta, SONGFILE )
               or die "Cannot put " . SONGFILE, $ftp->message;
         }
         if ($ftpsleep) { usleep($ftpsleep); }
         $numdta++;





      }









      $ftp->quit;


      if ($configUpdated)
      {
         writeConfig($config);
      }

   }





   return;
}


# short name.
# 
# #############################################################################
sub dtaparse
{
   foreach my $infile (@ARGV)
   {
      my $arref = parseDTA($infile);
      dumpDTA($arref);
      myprint DEBUG, "\n";

#      writeDTA($arref, "tmp.dta");
   }

   return;
}


# short name.
# 
# #############################################################################
sub encryptFiles
{
   foreach my $infile (@ARGV)
   {
      encryptFile($infile);
   }

   return;
}

# short name.
# 
# #############################################################################
sub encryptFile
{
   my $infile    = shift;
   my $outfile   = $infile . ENCREXT;
   my $npdataCmd = sprintf($npdataCmdFmt, shell_quote($infile), shell_quote($outfile));

   myprint NORMAL, "encrypting " . $infile . " to " . $outfile . "...\n";
   my $res = `$npdataCmd`;
   if (   $res =~ /File successfully encrypted/
       && $res =~ /File successfully forged/)
   {
      myprint NORMAL, "succeeded.\n";
   }
   else
   {
      myprint NORMAL, "failed!\n";
      myprint DEBUG, $npdataCmd;
      myprint DEBUG, $res;
      $outfile = "";
   }

   return $outfile;
}


# 
# #############################################################################

# 
# #############################################################################


# #############################################################################
# helper functions
# #############################################################################

# short name.
# 
# #############################################################################
sub checkSetMode($)
{
   my $newmode = shift;

   if ($mode ne NONE && $mode ne $newmode)
   {
      die "mode already set to $mode, can't change to $newmode!\n";
   }
   elsif ($mode ne $newmode)
   {
      $mode = $newmode;
   }
}

# short name.
# 
# #############################################################################
sub setSearchPath(@)
{
   my ($opt_name, $opt_value) = @_;
   $searchpath = $opt_value;
   checkSetMode(UPGRADE);
}

# short name.
# 
# #############################################################################
sub myprint($@)
{
   my $level = shift;
   my @args  = @_;
   my $line  = ( caller )[2];

   # print to stdout if message is above selected verbosity level
   if ($verbose >= $level) { print $line, ": ", @args; }

   # print to log file if one was specified, regardless of verbosity level
   if ($logfile) { print $logfh $line, ": ", @args; }
}

# short name.
# 
# #############################################################################
sub checkAndFixSongid($$)
{
   my $song = shift;
   my $cfg  = shift;

   if (   $song->{'song_id'}
       && $song->{'song_id'} !~ /^\d+$/)
   {
      my $newid = sprintf(SONGIDFMT, $cfg->{'SongIDPrefix'},
                          $cfg->{'AuthorID'}, $cfg->{'CurrentSongNumber'});
      $cfg->{'CurrentSongNumber'}++;
      $configUpdated++;

      myprint DEBUG, "song_id '" . $song->{'song_id'} . "' is not numeric. replacing with $newid\n";

      $song->{'song_id'} = $newid;
      $song->{'_raw'} =~ s/(\(['"]?song_id['"]?\s+)[a-zA-Z0-9_-]+(\s*\))/$1$newid$2/s;

      my $foo = parseDTAString($song->{'_raw'}, "testfile", 0, 0);
      if (   ! $foo
          || $foo->[0]->{'song_id'} ne $newid)
      {
         die "error fixing song_id!\n";
      }
   }
}


# searches a Text::CSV::Hashify object in AOH format for entries with a given
# short name.
# 
# #############################################################################
sub findExistingSong($$)
{
   my $csvinfo = shift;
   my $search  = shift;

   if ($search =~ /^['"]+.+['"]+$/)
   {
      $search = substr $search, 1, -1;
   }
   $search = lc($search);

   my $arref = [ grep { lc($_->{'Short Name'}) eq $search } @{$csvinfo} ];
   return $arref;
}

# 
# #############################################################################
sub searchForUpgrades($$)
{
   my $csvinfo    = shift;
   my $searchpath = shift;
   my @upgrades   = ();
   my %sources;

   opendir TOPDIR, $searchpath or die "can't open directory $searchpath! $!\n";
   my @maindirs = grep { (/Rock Band/ || /AC DC/) && !/Drums/ } readdir(TOPDIR);
   closedir TOPDIR;

   foreach my $dir (@maindirs)
   {
      my $searchdir = File::Spec->catdir($searchpath, $dir);
      opendir DIR, $searchdir or die "can't open directory $searchdir! $!\n";
      my @songdirs = grep { !/^\./ } readdir(DIR);
      closedir DIR;

      foreach my $songdir (@songdirs)
      {
         my $dta = File::Spec->catfile($searchdir, $songdir, SONGFILE);
         my $parsed = parseDTA($dta);
         foreach my $song ( @{$parsed} )
         {
            if (scalar @{findExistingSong($csvinfo, $song->{'shortname'})})
            {
               push @upgrades, File::Spec->catdir($searchdir, $songdir);
               $sources{$song->{'shortname'}} = File::Spec->catdir($searchdir, $songdir);
            }
         }
      }
   }

   my $matches = scalar(keys %sources);
   myprint NORMAL, "found $matches song upgrades\n";
   foreach my $key (sort keys %sources)
   {
      myprint DEBUG, "$key: " . $sources{$key} . "\n";
   }

   return \@upgrades;
}

# read the C3 ps3 config file.
# #############################################################################
sub readConfig()
{
   my $line    = "";
   my %cfg;

   open INFILE, $c3config or die "can't open config file \"$c3config\": $!\n";
   while($line = <INFILE>)
   {
      chomp($line);
      if ($line =~ /^([^=]+)=(.+)$/)
      {
         my $key   = $1;
         my $value = $2;
         $cfg{$key} = $value;
      }
   }
   close INFILE;

   return \%cfg;
}


# write the C3 ps3 config file.
# #############################################################################
sub writeConfig($)
{
   my $cfg     = shift;
   my @orderedKeys = qw(SongIDPrefix AuthorID CurrentSongNumber);

   open OUTFILE, ">$c3config" or die "can't open output file \"$c3config\": $!\n";
   foreach my $key ( @orderedKeys )
   {
      # should be all or nothing... if we've got a file to read, we should have
      # exactly the keys listed above.
      if (! defined $cfg->{$key})
      {
         die "undefined config key!\n";
      }
      print OUTFILE $key . "=" . $cfg->{$key} . "\r\n";
   }
   close OUTFILE;

   return;
}

# 
# #############################################################################
sub doesFileExist($$)
{
   my $ftp     = shift;
   my $path    = shift;
   my $current = $ftp->pwd();
   my $exists  = 0;

   my @splitdirs = File::Spec::Unix->splitdir($path);
   my $file = pop @splitdirs;
   my $parent = File::Spec::Unix->catdir(@splitdirs);

   if ($path =~ /^[^\/]/)
   {
      die "path must be absolute! $path\n";
   }

   $ftp->cwd($parent)
      or die "Cannot change working directory to $parent", $ftp->message;

   my @dirs = grep { $_ eq $file } $ftp->ls();
   if ($dirs[0])
   {
      $exists = 1;
   }

   $ftp->cwd($current)
      or die "Cannot change working directory to $current", $ftp->message;

   myprint DEBUG, "$path exists=$exists\n";
   return $exists;
}

# 
# #############################################################################
sub ftpcopy($$$)
{
   my $ftp = shift;
   my $src = shift;
   my $dst = shift;

   my $tmp = mktemp($tmptemplate);
   push @filesToRemove, $tmp;
   myprint DEBUG, "tmp=$tmp\n";

   $ftp->get( $src, $tmp)
      or die "Cannot get $src to $tmp! ", $ftp->message;
   if ($ftpsleep) { usleep($ftpsleep); }

   if (!$readonly) {
      $ftp->put($tmp, $dst)
         or die "Failed to put $tmp to $dst! ", $ftp->message;
   }
}

# 
# #############################################################################
sub printdir($)
{
   my $ftp = shift;

   myprint DEBUG, "contents of " . ($ftp->pwd()) . "\n";
   my @list = grep !/^\.+$/, $ftp->ls();
   foreach my $item (@list)
   {
      myprint DEBUG, $item . "\n";
   }
}

# 
# #############################################################################
sub rget_dir($$$)
{
   my $ftp        = shift;
   my $sdir       = shift;
   my $ddir       = shift || ".";

   my $origdir    = cwd();
   my $origftpdir = $ftp->pwd();
   my $crdir      = $sdir;

   # if sdir isn't the name of a dir in our current directory, we need to
   # resolve it and pluck off the last directory.
   if ($crdir =~ m|/([^/]+)$|)
   {
      $crdir = $1;
   }
   $crdir = File::Spec->catdir($ddir, $crdir);
   mkdir $crdir;
   chdir $crdir;

   $ftp->cwd($sdir);
   $ftp->rget();

   chdir $origdir;
   $ftp->cwd($origftpdir);
}

# 
# #############################################################################
sub rput_dir($$$)
{
   my $ftp        = shift;
   my $sdir       = shift;
   my $ddir       = shift || ".";

   my $origdir    = cwd();
   my $origftpdir = $ftp->pwd();
   my $crdir      = $sdir;

   # if sdir isn't the name of a dir in our current directory, we need to
   # resolve it and pluck off the last directory.
   if ($crdir =~ m|/([^/]+)$|)
   {
      $crdir = $1;
   }
   $crdir = $ddir . "/" . $crdir;

   if (!$readonly) {
      $ftp->mkdir($crdir);
   }
   $ftp->cwd($crdir);

   chdir($sdir);
   if (!$readonly) {
      $ftp->rput();
   }

   chdir $origdir;
   $ftp->cwd($origftpdir);
}



# #############################################################################
# #############################################################################
# DTALib - functions for reading/writing/parsing/searching DTA files.
# #############################################################################
# #############################################################################
#package DTALib;

#use strict;
#use warnings;
#use Exporter;

#use Text::Balanced qw (
#         extract_delimited
#         extract_bracketed
#         extract_quotelike
#         extract_codeblock
#         extract_variable
#         extract_tagged
#         extract_multiple
#         gen_delimited_pat
#         gen_extract_tagged
#             );

#use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

#$VERSION     = 1.00;
#@ISA         = qw(Exporter);
#@EXPORT      = qw(findkey dumpDTA writeDTA parseDTA parseDTAString);
#@EXPORT_OK   = qw(findkey dumpDTA writeDTA parseDTA parseDTAString);
#%EXPORT_TAGS = ( DEFAULT => [qw(&findkey &dumpDTA &writeDTA &parseDTA &parseDTAString)] );



# #############################################################################
# findkey
#   - search for a particular song by name, returning the hashref for its
#     contents if found and undef if not.
#
#     matching on shortname is case-insensitive.
# #############################################################################
sub findkey
{
   my $arref     = shift;
   my $searchkey = shift;
   my $res       = undef;

   if ($searchkey =~ /^['"]+.+['"]+$/)
   {
      $searchkey = substr $searchkey, 1, -1;
   }
   $searchkey = lc($searchkey);
   my $singlequotes = "'" . $searchkey . "'";
   my $doublequotes = '"' . $searchkey . '"';

   my @results   = grep {    lc($_->{'shortname'}) eq $searchkey
                          || lc($_->{'shortname'}) eq $singlequotes
                          || lc($_->{'shortname'}) eq $doublequotes } @{$arref};

   if (scalar(@results) == 0)
   {
      # not found
      $res = undef;
   }
   elsif (scalar(@results) == 1)
   {
      # single result
      $res = $results[0];
   }
   else
   {
      # multiple results - error!
      myprint QUIET, "searchkey = $searchkey\n";
      myprint QUIET, "singlequotes = $singlequotes\n";
      myprint QUIET, "doublequotes = $doublequotes\n";
      my $resstr = "";
      foreach my $href (@results)
      {
         $resstr .= " " . $href->{'shortname'};
      }
      myprint QUIET, "results =$resstr\n";
      die "duplicate song $searchkey found in dta!\n";
   }

   return $res;
}

# #############################################################################
# findByClosename
#   - search for a particular song by its closename (simplified artist/song
#     combination), returning the list of matching songs.
# #############################################################################
sub findByClosename
{
   my $arref     = shift;
   my $searchkey = shift;

   my @results   = grep { lc($_->{'closename'}) eq $searchkey } @{$arref};

   return \@results;
}

# #############################################################################
# dumpDTA
#   - search for a particular song by name, returning the hashref for its
#     contents if found and undef if not.
# #############################################################################
sub dumpDTA
{
   my $tree = shift;

   my $num = @{$tree};
   myprint NORMAL, $num . " songs\n";
   foreach my $child ( @{ $tree } )
   {
      myprint NORMAL, "shortname=\"" . $child->{"shortname"} . "\"\n";
      foreach my $key ( sort { ($a =~ /^_/ && $b =~ /^_/) ? $a cmp $b : $a =~ /^_/ ? 1 : $b =~ /^_/ ? -1 : $a cmp $b } keys %{ $child })
      {
         if (($key ne "_raw") && ($key ne "_comment") && ($key ne "shortname"))
         {
            myprint NORMAL, "$key=\"" . $child->{$key} . "\"\n";
         }
         elsif ($key ne "shortname")
         {
            # unescape any delimiters within comments
            my $song = $child->{$key};
            $song =~ s/ESCAPEOPENBRACKET/\(/gs;
            $song =~ s/ESCAPECLOSEBRACKET/\)/gs;
            $song =~ s/ESCAPESINGLEQUOTE/'/gs;
            $song =~ s/ESCAPEDOUBLEQUOTE/"/gs;
            myprint NORMAL, "$key=\"" . $song . "\"\n";
         }
      }
   }
}



# #############################################################################
# writeDTA
#   - Write out the given parsed dta array to the specified filename.
# #############################################################################
sub writeDTA
{
   my $tree    = shift;
   my $outfile = shift;

   open OUTFILE, ">$outfile" or die "can't open output file \"$outfile\": $!\n";
   foreach my $entry ( @{ $tree } )
   {
      # if song had leading comment, write it
      if ($entry->{"_comment"}) {
         my $comment = $entry->{"_comment"};
         $comment =~ s/ESCAPEOPENBRACKET/\(/gs;
         $comment =~ s/ESCAPECLOSEBRACKET/\)/gs;
         $comment =~ s/ESCAPESINGLEQUOTE/'/gs;
         $comment =~ s/ESCAPEDOUBLEQUOTE/"/gs;
         print OUTFILE $comment;
      }

      # unescape any delimiters within comments
      my $song = $entry->{"_raw"};
      $song =~ s/ESCAPEOPENBRACKET/\(/gs;
      $song =~ s/ESCAPECLOSEBRACKET/\)/gs;
      $song =~ s/ESCAPESINGLEQUOTE/'/gs;
      $song =~ s/ESCAPEDOUBLEQUOTE/"/gs;
      print OUTFILE $song . "\n";
   }
   close OUTFILE;
}



# #############################################################################
# parseDTA
#   - parses a given filename, returning an array reference to a list of its
#     songs.
# #############################################################################
sub parseDTA
{
   my $filename  = shift;
   my $isUpgrade = shift;
   my $fixErrors = shift;
   my $s         = "";
   my $line      = "";

   if (not defined($fixErrors))
   {
      $fixErrors = 1;
   }
   if (not defined($isUpgrade))
   {
      if ($filename =~ /upgrades\.dta$/)
      {
         $isUpgrade = 1;
      }
      else
      {
         $isUpgrade = 0;
      }
   }

   # slurp up the input file, throwing away comments
   open INFILE, $filename or die "can't open input file \"$filename\": $!\n";
   my $file_content = do { local $/; <INFILE> };
   $file_content =~ s/(\015\012?)/\012/gs;

   foreach my $line (split(/\n/, $file_content))
   {
      chomp $line;

      # If we find a comment, we need to give it some special handling. First
      # split the line into a pre-comment part and the comment itself, then
      # go through the comment and escape any delimiters with a leading
      # backslash. later when print or dump the raw dta we'll un-escape these
      # fields.
      # -----------------------------------------------------------------------
      if ($line =~ /([^;]*);(.*)/)
      {
         # comments are annoying - they sometimes have typos and unbalanced
         # brackets. escape brackets and quotes within the comment.
         my $precom = $1;
         my $com    = $2;
         $com =~ s/\(/ESCAPEOPENBRACKET/g;
         $com =~ s/\)/ESCAPECLOSEBRACKET/g;
         $com =~ s/'/ESCAPESINGLEQUOTE/g;
         $com =~ s/"/ESCAPEDOUBLEQUOTE/g;
         $s .= $precom . ";" . $com . "\n";
      }
      else
      {
         $s .= $line . "\n";
      }
   }
   close INFILE;

   # returns an array of hash references, where each hash represents a single
   # song in the .dta file.
   # --------------------------------------------------------------------------
   return parseDTAString($s, $filename, $isUpgrade, $fixErrors);
}

sub getTokens($) {
   my $s            = shift;
   my $startcomment = "";

   # extracts a set of bracket-balanced entries from the input. Since our input
   # is a .dta file, each should represent a song.
   my $expr = '(")';
   my $pre  = '[\s\n\r]*';
   my ($token, $remainder) = extract_bracketed($s, $expr, $pre );

#   myprint DEBUG, "token=\"$token\"\n";
#   myprint DEBUG, "remainder=\"$remainder\"\n";

   # check for a broken parse due to comments mixed in between entries.
   # if we find token is empty, but remainder doesn't and starts with a
   # comment, strip it out and reparse.
   if (!$token && $remainder && ($remainder =~ /^\s*;+/gs)) {
#      myprint DEBUG, "comment outside song, save it\n";
      $remainder =~ s/^([^;]+)//gs;
      $remainder =~ s/^([^\(]+)//gs;
      $startcomment = $1;
      ($token, $remainder) = extract_bracketed($remainder, $expr, $pre);
#      myprint DEBUG, "startcomment=\"$startcomment\"\n";
#      myprint DEBUG, "token=\"$token\"\n";
#      myprint DEBUG, "remainder=\"$remainder\"\n";
   }

   return ($token, $remainder, $startcomment);
}

sub buildCloseName($$) {
   my $artist = shift;
   my $song = shift;
   my $closename = "";

   $artist = lc($artist);
   $artist =~ s/[\.\?\!\_\-\(\)\:\'\"\&\+]+//gs;
   $song = lc($song);
   $song =~ s/[\.\?\!\_\-\(\)\:\'\"\&\+]+//gs;
   $closename = $artist . " " . $song;

   return $closename;
}

# #############################################################################
# parseDTAString
#   - parses contents of given string, returning an array reference to a list
#     of its songs.
# #############################################################################
sub parseDTAString
{
   my $s         = shift;
   my $filename  = shift;
   my $isUpgrade = shift;
   my $fixErrors = shift;

   # returns an array of hash references, where each hash represents a single
   # song in the .dta file.
   # --------------------------------------------------------------------------
   my @retarray;

   # for debugging, build simplified artist+song combos to find duplicates with
   # different shortnames or paths
   my %closenames;

#   myprint DEBUG, "tokenize...\n";

   my ($token, $remainder, $startcomment) = getTokens($s);
#   myprint DEBUG, "startcomment=\"$startcomment\"\n";
#   myprint DEBUG, "token=\"$token\"\n";
#   myprint DEBUG, "remainder=\"$remainder\"\n";

   while ($token)
   {
#      myprint DEBUG, "next iter\n";
#      myprint DEBUG, "token: \"$token\"\n";
      if ($token =~ /^\(/)
      {
#         myprint DEBUG, "subtree\n";
         my %tmphash;

         # a top level block should start with an opening bracket, the name,
         # and then the rest of the data. Pull out the name as our primary key,
         # cache the rest in the _raw key, then pick out a few more interesting
         # fields.
         # --------------------------------------------------------------------
         if ($token =~ /^\(\s*(['"]?[a-zA-Z0-9_\-!]+['"]?)\s*/s)
         {
            $tmphash{"shortname"} = $1;
            if ($tmphash{"shortname"} ne lc($tmphash{"shortname"}))
            {
               if ($tmphash{"shortname"} =~ /^['"][^'"]+['"]$/)
               {
#                  myprint DEBUG, "shortname " . $tmphash{"shortname"} . "is not lower case, but is quoted\n";
               }
               else
               {
                  if ($fixErrors)
                  {
                     myprint DEBUG, "Warning: fixing non-lowercase shortname " . $tmphash{"shortname"} . " error\n";
                     $token =~ s/^(\(\s*)([a-zA-Z0-9_\-!]+)(\s*)/$1\L$2\E$3/s;
                     $tmphash{"shortname"} = lc($tmphash{"shortname"});
                  }
                  else
                  {
                     myprint DEBUG, "Warning: shortname " . $tmphash{"shortname"} . " is not lower case\n";
                  }
               }
            }
         }
         else
         {
            die "ERROR: missing shortname field in $filename\n";
         }
         if ($token =~ /\(\s*['"]?midi_file['"]?\s+['"]?([^)'"]+)['"+]?\s*\)/s)
         {
            $tmphash{"midi_file"} = $1;
         }
         else
         {
            if ($token =~ /midi_file/s)
            {
               die "ERROR: midi_file half match in $filename\n";
            }
            else
            {
#               myprint DEBUG, "ERROR: missing midi_file field in $filename\n";
            }
         }
         if ($token =~ /\(['"]?song_id['"]?\s+([a-zA-Z0-9_\-!]+)\s*\)/s)
         {
            $tmphash{"song_id"} = $1;
            if ($tmphash{"song_id"} =~ /\D+/)
            {
               myprint DEBUG, "Warning: song_id " . $tmphash{"song_id"} . " is non-numeric\n";
            }
         }
         else
         {
            if ($token =~ /song_id/s)
            {
               die "ERROR: song_id half match in $filename\n";
            }
            else
            {
#               myprint DEBUG, "ERROR: missing song_id field in $filename\n";
            }
         }
         if ($token =~ /\(\s*['"]?artist['"]?\s+(['"]?[a-zA-Z0-9öüÿÆ'_\-!\.\&\?\/,\s\(\)\:]+['"]?)\s*\)/s)
         {
            $tmphash{"artist"} = $1;
            myprint DEBUG, "found artist " . $tmphash{"artist"} . "\n";
         }
         else
         {
            myprint NORMAL, "ERROR: missing artist field in $filename\n";
         }
         if ($token =~ /^\(\s*(['"]?[a-zA-Z0-9_\-!]+['"]?)\s+\(\s*['"]?name['"]?\s+(['"]?[a-zA-Z0-9öüÿÆ+'_\-!\.\&\?\/,\s\(\)\:]+['"]?)\s*\)/s)
         {
            $tmphash{"songname"} = $2;
            myprint DEBUG, "found songname " . $tmphash{"songname"} . "\n";
         }
         else
         {
            myprint NORMAL, "ERROR: missing songname field in $filename\n";
            myprint NORMAL, $s;
         }
         if ($token =~ /\(['"]?rating['"]?\s+([0-9]+)\s*\)/s)
         {
            $tmphash{"rating"} = $1;
            if (   $tmphash{"rating"} < 1
                || $tmphash{"rating"} > 3)
            {
               if ($fixErrors)
               {
                  myprint DEBUG, "Warning: fixing rating " . $tmphash{"rating"} . " error\n";
                  $token =~ s/(\(['"]?rating['"]?\s+)([0-9]+)(\s*\))/${1}1${3}/s;
                  $tmphash{"rating"} = 1;
               }
               else
               {
                  myprint DEBUG, "Warning: rating is " . $tmphash{"rating"} . "\n";
               }
            }
         }
         else
         {
            if ($token =~ /rating/s)
            {
               die "ERROR: rating half match in $filename\n";
            }
            else
            {
#               myprint DEBUG, "ERROR: missing rating field in $filename\n";
            }
         }
         if ($token =~ /\(\s*['"]?song['"]?\s+\(\s*['"]?name['"]?\s+['"]?([a-zA-Z0-9_\-\/\.!]+)['"]?\s*\)/s)
         {
            $tmphash{"song_path"} = $1;
         }
         elsif (!$isUpgrade)
         {
            if (   $token =~ /song/s
                && $token =~ /name/s)
            {
               die "ERROR: song_path half match in $filename\n";
            }
            else
            {
               die "ERROR: missing song_path field in $filename\n";
            }
         }
         if ($token =~ /\(['"]?vocal_parts['"]?\s+([0-9]+)\s*\)/s)
         {
            $tmphash{"vocal_parts"} = $1;
         }
         else
         {
            if ($token =~ /vocal_parts/s)
            {
               die "ERROR: vocal_parts half match in $filename\n";
            }
            else
            {
#               myprint DEBUG, "ERROR: missing vocal_parts field in $filename\n";
            }
         }
         if ($token =~ /\(['"]?upgrade_version['"]?\s+([0-9]+)\s*\)/s)
         {
            $tmphash{"upgrade_version"} = $1;
         }
         else
         {
            if ($token =~ /upgrade_version/s)
            {
               die "ERROR: upgrade_version half match in $filename\n";
            }
            elsif ($isUpgrade)
            {
               die "ERROR: missing upgrade_version field in $filename\n";
            }
         }
         $tmphash{"_comment"} = $startcomment;
	 $startcomment = "";
         $tmphash{"_raw"} = $token;
#         myprint DEBUG, "name=$1\n";
	 my $closename = buildCloseName($tmphash{'artist'}, $tmphash{'songname'});
	 my $closematch = $closenames{$closename};
	 if ($closematch) {
            myprint NORMAL, "duplicate closename found with $closematch and $tmphash{'shortname'} while parsing dta\n";
         } else {
            myprint DEBUG, "new closename $closename for $tmphash{'shortname'}\n";
	    $closenames{$closename} = $tmphash{'shortname'};
         }
	 $tmphash{'closename'} = $closename;

         push @retarray, \%tmphash;
      }
      elsif ($token =~ /^\s+/gs)
      {
#         myprint DEBUG, "whitespace\n";
         # ignore it
      }
      else
      {
         # should be something stringy
#         $token =~ s/(\s+)$//gs;
         die "shouldn't be here...$token\n";
#         Tree::Simple->new($token, $tree);
      }
      ($token, $remainder, $startcomment) = getTokens($remainder);
#      myprint DEBUG, "startcomment=\"$startcomment\"\n";
#      myprint DEBUG, "token=\"$token\"\n";
#      myprint DEBUG, "remainder=\"$remainder\"\n";
   }

   return \@retarray;
}



1;

# #############################################################################

=head1 NAME

c3ps3tool.pl - Install C3 songs or RBHP upgrades to a PS3.

=head1 SYNOPSIS

c3ps3tool.pl [options] [files]

Install song:   c3ps3tool.pl --install songname.rar

Upgrade song:   c3ps3tool.pl --upgrade path/to/rbhp/upgradedir

=head1 OPTIONS

Upgrade:    --search <searchpath>
            --dtalist <DTA CSV list>
            --mididir <encrypted midi directory>

Help:       --help | --man

Functional: --custombase <PS3 custom base directory (default /dev_hdd0/game/BLUS30463/USRDIR/HMX0756/)>
            --ip <PS3 IP address (default 192.168.1.222)>
            --port <PS3 FTP port (default 21)>
            --user <PS3 FTP user (default anonymous)>
            --pass <PS3 FTP password (default anonymous)>
            --ftpsleep <microseconds to sleep between ftp operations (default 100000 or 100ms)>
            --ftptimeout <seconds to timeout on ftp operations (default 120)>
            --noorig
            --nobackup
            --reinstall
            --readonly
            --tmptemplate <temporary filename template (default /tmp/c3ps3toolXXXXXX)>

Output:     --verbose
            --quiet
            --logfile <log filename>

=head1 DESCRIPTION

Extracts and installs C3 songs to a jailbroken Playstation 3 running an ftp
server. Can install harmonies from the Rock Band Harmonies Project.

=head1 USAGE

c3ps3tool.pl --install song1.rar ... songN.rar

c3ps3tool.pl --upgrade path/to/rbhp/upgradedir

c3ps3tool.pl --dtaparse song.dta

c3ps3tool.pl --uninstall songtoremove

c3ps3tool.pl --unupgrade songtodowngrade

c3ps3tool.pl [--help | --man]

=over 4

=item C<--custombase>

Base path on the Playstation where C3 customs are installed. Default: /dev_hdd0/game/BLUS30463/USRDIR/HMX0756/

=item C<--dtalist>

Path to PS3_DTA_LIST.csv generated by C3 Con Tools >= 3.60. Only used for upgrades.

=item C<--mididir>

Path to encrypted RBHP midi files (if not in the same directory as the upgrade files). Only used for upgrades.

=item C<--ip>

IP address of the Playstation. Default 192.168.1.222.

=item C<--port>

FTP port number on the Playstation. Default 21.

=item C<--user>

FTP user on the Playstation. Default anonymous.

=item C<--pass>

FTP password on the Playstatoin. Default anonymous.

=item C<--verbose>

Turn on verbose output.

=item C<--logfile>

File to log debug information to.

=item C<--noorig>

By default, before touching a "stock" songs.dta file, the program will make a backup copy, named songs.dta.orig. This option will disable this feature. This is not recommended as it is required should anything go wrong during the upgrade process and if the user wants to be able to unupgrade in the future.

=item C<--backup>

Before modifying the songs.dta or upgrades.dta files, the program will make a backup copy called <filename>.YYMMDDHHMMSS using the current timestamp. This may be useful if a particular install/upgrade does not work correctly and the user wants to go back to an earlier version.

=item C<--reinstall>

By default the program will not overwrite an existing song/upgrade. This option will force it to overwrite the existing song, which may be useful if the program crashed or if a newer version of the upgrade is released.

=item C<--readonly>

By default the program will perform write operations to the destination PS3. This option will force it to only read from the PS3, allowing you to test and make sure everything will work OK before committing to the changes.

=item C<--tmptemplate>

By default the program will create temporary files and directories in /tmp/c3perlXXXXXX format. Users can change this destination/naming here. You can probably safely ignore this.

=item C<--search>

This is an enhancement to the base upgrade support by having it search the RBHP and cross-referencing it with your song list (PS3_DTA_LIST.csv) to upgrade all songs at once. If using --search, you don't need to explicitly specify --upgrade. The directory specified should be the base RBHP directory - the one that contains a directory for each game plus optional upgrades. This will only install harmony upgrades currently.

=item C<--version>

Display version number and exit

=item C<--help>

Brief help message.

=item C<--man>

Manual page for script.

=item C<--quiet>

Print no messages to STDOUT while running.

=back

=head1 TODO

-uninstall support
-upgrades for more than just harmonies (works already, but not via --search)
-windows testing
-auto-abort if something fails (undoing partial uploads, etc)


=head1 AUTHOR

grubextrapolate http://pksage.com/ccc/forums/memberlist.php?mode=viewprofile&u=1408

=cut


