#!/usr/bin/perl
use strict;
use warnings;
use 5.024;
no warnings 'experimental';

my $CurrPack = 'nameofcurrentpackage';
my $Owner = 'user:group';

my $WD = `pwd`;
chomp($WD);
my $Program = GetProgram();


if ( !@ARGV ) {
    InitF();
    exit;
}

given ( shift @ARGV ) {
    when (/^-*p$/) {
        PrepF( @ARGV );
    }
    when (/^-*i$/) {
        InitF( $ARGV[0] );
    }
    when (/^-*s$/) {
        SOPM( @ARGV );
    }
    when (/^-*c$/) {
        CleanF( $ARGV[0] );
    }
    when (/^-*h$/) {
        Usage();
    }
    default {
        if ( -e $_ && -d $_ ) {
            InitF( $_ );
        }
        else {
            PrepF( $_, @ARGV );
        }
    }
}


#+~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~+#

sub Usage {
    print "Usage: ./pp [command] [file(s)]\n".
          "\ti\t- Initialize files of cloned package repo (default command for directories)\n".
          "\tp\t- Prepare files (default command for file)\n".
          "\ts\t- Create sopm file\n".
          "\tc\t- Clean files or whole repo\n".
          "\th\t- Show this usage explanation\n";

    exit 0;
}

#+~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~+#

sub InitF {

    my $Pack = $_[0] || $CurrPack;
    if ( !$Pack ) {
        die "Package directory needed.\n";
    }
    if ( !-e $Pack ) {
        Usage() if !@_;
        die "'$Pack' does not exist or is not a directory.\n";
    }

    # needed for correct links
    $Pack = $Pack =~ /^\// ? $Pack : "$WD/$Pack";
    if ( !-d $Pack ) {
        die "'$Pack' is not a directory.\n";
    }

    my @FileList = `find $Pack -path $Pack/.git -prune -o -type f -print`;

    FILE:
    for my $File ( @FileList ) {
        chomp($File);
        $File =~ s/^\.?\/?$Pack\/+//;

        if ( -e $File ) {
            if ( -e "$File.pp_backup" ) {
                die "$File.pp_backup already exists! Aborting the whole process. Directory is not cleaned!\n";
            }

            print "Preparing backup of '$File' and linking it.\n";
            system "mv $File $File.pp_backup; ln -s $Pack/$File $File";
        }

        print "Linking '$File'.\n";
        
        my $Dir = $File;
        if ( $Dir =~ s/\/[^\/]+$// ) {
            system "mkdir -p $Dir";
        }
        system "ln -s $Pack/$File $File";
    }

    if ( $Owner ) {
        print "Setting Ownership to $Owner\n";
        system "chown -R $Owner $Pack";
    }
    print "To complete this step, you probably want to run:\nbin/otobo.Console.pl Maint::Config::Rebuild\n";

    return 1;
}

#+~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~+#

sub PrepF {
    my @Files;
    my $Pack;
    for my $File ( @_ ) {
        if ( -e $File && -d $File ) {
            if ( $Pack ) {
                die "Cannot interpret two directories given with Prepare command: Please exclude '$Pack' or '$File'.\n";
            }
            $Pack = $File;
        }
        else {
            push @Files, $File;
        }
    }

    $Pack = $Pack || $CurrPack;
    if ( !$Pack ) {
        die "Package directory needed.\n";
    }

    # needed for correct links
    $Pack = $Pack =~ /^\// ? $Pack : "$WD/$Pack";
    if ( !-d $Pack ) {
        die "'$Pack' is not a directory.\n";
    }

    FILE:
    for my $File ( @Files ) {
        if ( -e "$Pack/$File" ) {
            if ( -e $File ) {
                warn "Both, '$Pack/$File' as well as '$File' are present. Nothing to do...\n";
                next FILE;
            }
            if ( !-f "$Pack/$File" ) {
                warn "'$Pack/$File' exists, but is not a regular file. Action not defined...\n";
                next FILE;
            }

            print "Linking '$File' to existing '$Pack/$File'\n";
            my $Dir = $File;
            if ( $Dir =~ s/\/[^\/]+$// ) {
                system "mkdir -p $Dir";
            }
            system "ln -s $Pack/$File $File";
            next FILE;
        }

        if ( -e $File ) {
            if ( -l $File ) {
                warn "'$File' is already a link - check please. Skipping...\n";
                next FILE;
            }
            if ( $File =~ /^Custom\// ) {
                warn "'$File' already exists - check please. Skipping...\n";
                next FILE;
            }

            if ( $File =~ /^Kernel\// ) {
                if ( -e "Custom/$File" ) {
                    warn "'Custom/$File' already exists - check please. Skipping...\n";
                    next FILE;
                }
                
                print "Linking 'Custom/$File' to '$Pack/Custom/$File'";
                my $Dir = "Custom/$File";
                $Dir =~ s/\/[^\/]+$//;
                if ( !-e "$Pack/Custom/$File" ) {
                    print " and preparing latter from the original.\n";
                    system "mkdir -p $Pack/$Dir; mkdir -p $Dir";

                    # copy file and add $origin
                    my $Commit = `git --no-pager log -n 1 --pretty=format:%H -- $File` || '';
                    open my $in,  "< $File" or ( warn "Could not open $File to read. Skipping...\n" && next FILE );
                    open my $out, "> $Pack/Custom/$File" or ( warn "Could not open $Pack/Custom/$File to write. Skipping...\n" && next FILE );
                    while ( <$in> ) {
                        print $out $_;
                        if ( /^# Copyright/ ) {
                            until ( /^# --\s*$/ || !$_ ) {
                                $_ = <$in>;
                                print $out $_ if defined $_;
                            }
                            if ( $_ ) {
                                print $out "# \$origin: $Program - $Commit - $File\n# --\n";
                            }
                            while ( <$in> ) { print $out $_ }
                        }
                    }
                }
                else {
                    print "\n";
                }
                system "ln -s $Pack/Custom/$File Custom/$File";
                next FILE;
            }

            if ( -e "$File.pp_backup" ) {
                warn "$File.pp_backup already present. Skipping...\n";
                next FILE;
            }

            print "Creating Backup of '$File', linking '$File' to '$Pack/$File' and copying latter from original.\n";
            my $Dir = $File;
            if ( $Dir =~ s/\/[^\/]+$// ) {
                system "mkdir -p $Pack/$Dir";
            }
            system "cp $File $Pack/$File; mv $File $File.pp_backup";
            system "ln -s $Pack/$File $File";
        }

        else {
            print "Touching '$Pack/$File' and linking '$File' to '$Pack/$File'.\n";
            my $Dir = $File;
            if ( $Dir =~ s/\/[^\/]+$// ) {
                system "mkdir -p $Dir";
                system "mkdir -p $Pack/$Dir";
            }
            system "touch $Pack/$File; ln -s $Pack/$File $File";
        }
    }

    if ( $Owner ) {
        print "Setting Ownership to $Owner\n";
        system "chown -R $Owner $Pack";
    }

    return 1;
}

#+~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~+#

sub CleanF {

    my $Pack = $_[0] || $CurrPack;
    if ( !$Pack ) {
        die "Package directory needed.\n";
    }
    if ( !-e $Pack ) {
        die "'$Pack' does not exist.\n";
    }

    my @FileList = `find $Pack -path $Pack/.git -prune -o -type f -print`;

    for my $File ( @FileList ) {
        chomp($File);
        $File =~ s/^\.?\/?$Pack\/+//;
        
        print "Unlinking '$File'.\n";
        system "unlink $File";

        if ( -e "$File.pp_backup" ) {
            system "mv $File.pp_backup $File";
        }
    }

    print "To complete this step, you probably want to run:\nbin/otobo.Console.pl Maint::Config::Rebuild --cleanup\n";

    return 1;
}

#+~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~+#

sub SOPM {

    my $Name;
    my $Pack;
    for my $File ( @_ ) {
        if ( -e $File && -d $File ) {
            if ( $Pack ) {
                die "Cannot interpret two directories given with Prepare command: Please exclude '$Pack' or '$File'.\n";
            }
            $Pack = $File;
        }
        else {
            if ( $Name ) {
                die "Decide on one name please. Either '$Name' or '$File'.\n";
            }
            $Name = $File;
        }
    }
    $Pack = $Pack || $CurrPack;

    if ( !$Name ) {
        die "A Name has to be provided.\n";
    }
    if ( !$Pack ) {
        die "Package directory needed.\n";
    }
    if ( -e "$Pack/$Name.sopm" ) {
        die "$Pack/$Name.sopm already exists!\n";
    }

    my @FileList = `find $Pack -path $Pack/.git -prune -o -type f -print | sort`;

    open my $sopm, "> $Pack/$Name.sopm" or die "Could not open $Pack/$Name.sopm to write:\n$!\n";

    print $sopm 
'<?xml version="1.0" encoding="utf-8" ?>
<otobo_package version="1.0">
    <Name>'.$Name.'</Name>
    <Vendor>Rother OSS GmbH</Vendor>
    <Framework>10.0.x</Framework>
    <URL>https://rother-oss.com/</URL>
    <License>GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007</License>
    <Description Lang="en">..</Description>
    <Filelist>
';

    for my $File ( @FileList ) {
        chomp($File);
        $File =~ s/^\.?\/?$Pack\/+//;
        print $sopm "        <File Permission='644' Location='$File' />\n";
    }

    print $sopm
'    </Filelist>
</otobo_package>
';

    return 1;
}

#+~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~+#

sub GetProgram {
    open my $Rel, "< RELEASE" or return '';

    while ( <$Rel> ) {
        if ( /^\s*product\s*=\s*(otrs|otobo)/i ) { return lc $1 }
    }

    return '';
}