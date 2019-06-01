#!/usr/bin/perl
#!/usr/bin/perl -d

# File:         diffdirs.pl
# Description:  Compare directories contents


our $VERSION = "0.1";

our $Myname = $0; { $Myname =~ s,.*/,,; } # bug in grep means I can't strip dir this outside these brackets

use strict;
use warnings;
no warnings 'uninitialized';

use Getopt::Std;
use Time::Local;
use Time::HiRes qw(gettimeofday usleep);


#######################
our $UserName = getpwuid($>);  # $< = realuser, $> = effective user
our $Hostname = $ENV{HOSTNAME};  # if blank then filled with uname -n


###############
our $VerbosityLevel = 1;
our $VerbosityString = "$VerbosityLevel";
our @Dirs = ();
our $MasterDir;


#############
sub verbose
{
	my ($Level, $Format, @Args) = @_;
	my $Str = (@Args ? sprintf("$Format", @Args) : $Format);
	print STDERR "$Str\n" if (($Level =~ /^\d+$/ && $VerbosityLevel >= $Level) || (",$VerbosityString," =~ /,$Level,/));
}
sub verbose_arr
{
	my ($Level, $Prefix, @Arr) = @_;
	foreach (@Arr) { verbose $Level, "$Prefix:$_"; }
}
sub error
{
	my ($ExitValue, $Format, @Args) = @_;
	our ($Myname);
	verbose 1, "$Myname: ERROR: $Format", @Args;
	exit $ExitValue;
}
sub SetVerbosity
{
	if ($VerbosityString =~ /^(\d+),(.*)/)
	{
		($VerbosityLevel, $VerbosityString) = ($1, $2);
	}
	elsif ($VerbosityString =~ /^(\d+)$/)
	{
		($VerbosityLevel, $VerbosityString) = ($1, "");
	}
}

###############
###############
sub MyDateTime
{
	my ($ss, $mm, $hh, $d, $m, $y, $w, $yd, $dst) = localtime(time);
	my $DateTimeStamp = sprintf "%02d/%02d/%02d %02d:%02d:%02d",$d,++$m,$y-100,$hh,$mm,$ss;
	chomp $DateTimeStamp;
	return $DateTimeStamp;
}

###############
###############
sub TidyValue
{
	my ($Value) = @_;
	chomp $Value;
	$Value =~ s/[\n\r\t]//;
	$Value =~ tr/\x20-\x7f//cd;
	$Value =~ s/^ *//;
	$Value =~ s/ *$//;
	return $Value;
}
sub TidyValues
{
	my (@Values) = @_;
	foreach my $Value (@Values)
	{
		$Value = TidyValue $Value;
	}
	return @Values;
}

###############
###############
sub usage
{
	our $Myname;
	print STDERR qq{
 usage: $Myname dir dir

 -v str     <level|tag>[,tag,tag,...] or tag[,tag,...] and level is $VerbosityLevel (default: $VerbosityLevel)

 Compare dirs.

 eg. $Myname /opt/DBpb /opt/DBpb.save

};
	exit 2;
}


###############
sub GetOptions
{
	our %options;
	our ($VerbosityLevel, $MasterDir, @Dirs);
	getopts("hv:",\%options) or usage;
	usage   if defined $options{h};
	$VerbosityString = $options{v} if defined $options{v};
	SetVerbosity;
	@Dirs = @ARGV;
	$MasterDir = $Dirs[0];
	usage if scalar @Dirs == 0;
}


############
sub inarray
{
	my ($f, @a) = @_;
	foreach my $af (@a)
	{
		if ($f eq $af)
		{
			return 1;
		}
	}
	return 0;
}


###########################
sub PrintRecursiveHashLong
{
	my ($fd, $t, %hash) = @_;
	my $Colon = ":"; $Colon = "" if ($t eq "");
	my $Text = "$t";
	while (my ($key, $value) = each(%hash))
	{
		$key   =~ s/:/<colon>/g; # if delimiter is : then put the word <colon> in all fields
		$value =~ s/:/<colon>/g; # if delimiter is : then put the word <colon> in all fields
		if (ref($value) eq "HASH")
		{
			printf $fd "k:${Text}${Colon}%s\n", $key;
			PrintRecursiveHashLong($fd, "$Text${Colon}$key", %{$value});
		}
		else
		{
			printf $fd "v:${Text}${Colon}%s:%s\n", $key, $value              if (ref($value) ne "ARRAY");
			printf $fd "v:${Text}${Colon}%s:%s\n", $key, join " ", @{$value} if (ref($value) eq "ARRAY");
		}
	}
}
sub PrintRecursiveHashDebug
{
	my (%hash) = @_;
	my $stderr_fd = *STDERR;
	PrintRecursiveHashLong($stderr_fd, "", %hash);
}


####################
# standard case-sensititve function for: sort { &NumInAlphaCompare } @arr
sub NumInAlphaCompare
{
	my ($s1, $s2) = ($a, $b);
	my ($f1, $f2) = ($a, $b);
	$f1 =~ s/(\d+)/%010d/g;
	$f2 =~ s/(\d+)/%010d/g;
	my (@a1, @a2);
	while ($s1 =~ /(\d+)/gs) { push @a1, $1; }
	while ($s2 =~ /(\d+)/gs) { push @a2, $1; }
	$s1 = sprintf $f1, @a1;
	$s2 = sprintf $f2, @a2;
	$s1 cmp $s2;
}

###############
# NOTE: reverse sort used here so if files have to be removed command will be
#       "rmdir test/0.1 test" - it will only matter if I find later that
#       the remove command is too long and I have to split it into multiple rmdirs
sub DirFilesArray
{
	my (%DirFiles) = @_;
	my @Arr = ();
	foreach my $Filename (reverse sort { &NumInAlphaCompare } keys %DirFiles)
	{
		push @Arr, $DirFiles{$Filename};
	}
	return @Arr;
}

###############
# warnings are expressed in terms of $Dir2
# a) not having line(s) from $Dir1           (serious error since copy $Dir1->$Dir2 failed)
# b) having line(s) that $Dir1 doesn't have  (cleanup commands are returned that can be run on $Dir2)
sub GetMissingFiles
{
	my ($Verbosity, $Dir1, $DirFilesPtr1, $Dir2, $DirFilesPtr2) = @_;
	verbose "f", "%s(%s, %s, %s)", (caller(0))[3], $Verbosity, $Dir1, $Dir2;
	my @Arr1 = DirFilesArray %{$DirFilesPtr1};
	my @Arr2 = DirFilesArray %{$DirFilesPtr2};
	my @MissingLines = ();
	foreach my $Line (@Arr1)
	{
		if (not inarray $Line, @Arr2)
		{
			push @MissingLines, $Line;
			verbose $Verbosity, "DIFF: %s does not have this cksum/perms/file (but %s does): %s", $Dir2, $Dir1, $Line;  # means copy failed so more serious
		}
	}
	return @MissingLines;
}
sub GetExtraFiles
{
	my ($Verbosity, $Dir1, $DirFilesPtr1, $Dir2, $DirFilesPtr2) = @_;
	verbose "f", "%s(%s, %s, %s)", (caller(0))[3], $Verbosity, $Dir1, $Dir2;
	my @Arr1 = DirFilesArray %{$DirFilesPtr1};
	my @Arr2 = DirFilesArray %{$DirFilesPtr2};
	my @ExtraLines = ();
	foreach my $Line (@Arr2)
	{
		if (not inarray $Line, @Arr1)
		{
			push @ExtraLines, $Line;
			verbose $Verbosity, "DIFF: %s has this cksum/perms/file (but %s does not): %s", $Dir2, $Dir1, $Line;  # this will happen when -o remove is used
		}
	}
	return @ExtraLines;
}


##################
sub MissingFiles
{
	verbose "f", "%s()", (caller(0))[3];
	our ($MasterDir);
	my ($Verbosity, %DirFiles) = @_;
	my %MissingFiles = ();
	foreach my $Dir (keys %DirFiles)
	{
		next if $Dir eq $MasterDir;
		$MissingFiles{$Dir} = GetMissingFiles $Verbosity, $MasterDir, \%{$DirFiles{$MasterDir}}, $Dir, \%{$DirFiles{$Dir}};
	}
	return %MissingFiles;
}
sub ExtraFiles
{
	verbose "f", "%s()", (caller(0))[3];
	our ($MasterDir);
	my ($Verbosity, %DirFiles) = @_;
	my %ExtraFiles = ();
	foreach my $Dir (keys %DirFiles)
	{
		next if $Dir eq $MasterDir;
		$ExtraFiles{$Dir} = GetExtraFiles $Verbosity, $MasterDir, \%{$DirFiles{$MasterDir}}, $Dir, \%{$DirFiles{$Dir}};
	}
	return %ExtraFiles;
}


################
# eg. convert: $DirFiles{host}{myfile} = "nosum lrwxr-xr-x myuser mygroup 12345 Jan 4 00:12 mylink -> myfile";
#     to:      $DirFiles{host}{myfile} = "nosum lrwxr-xr-x myuser mygroup 12345 mylink -> myfile";
sub RemoveDate
{
	verbose "f", "%s()", (caller(0))[3];
	my (%DirFiles) = @_;
	my %NewDirFiles = ();
	foreach my $Dir (sort keys %DirFiles)
	{
		foreach my $Filename (keys %{$DirFiles{$Dir}})
		{
			my $Info = $DirFiles{$Dir}{$Filename};
			if ($Info =~ /([^ ]+ [^ ]+ [^ ]+ [^ ]+ [^ ]+) [^ ]+ [^ ]+ [^ ]+ (.*)/)
			{
				$NewDirFiles{$Dir}{$Filename} = "$1 $2";
			}
			else
			{
				verbose 1, qq#WARNING: %s(): %s: %s: unexpected line "%s"#, (caller(0))[3], $Dir, $Filename, $Info;
			}
		}
	}
	return %NewDirFiles;
}


###################
#7475112    4 drwxr-xr-x   2 pearcolb pearcolb     4096 Mar 17 13:26 .
#7475154    0 -rw-r--r--   1 pearcolb pearcolb        0 Mar 17 13:26 ./zz
sub FindFilesInDir
{
	verbose "f", "%s()", (caller(0))[3];
	my ($Dir) = @_;
	my %Find = ();
	my $Cmd = "cd $Dir && find . -ls 2>/dev/null";
	verbose "sys", q#find: executing "%s"#, $Cmd;
	my $Out = `$Cmd`;
	verbose 2, "find: collected info under %s", $Dir;
	foreach my $Line (split /\n/, $Out)
	{
		verbose 9, "find: line:%s", $Line;
		if ($Line =~ /^([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+(.*)/)
		{
			my ($Inode,$Blocks,$Perms,$Links,$User,$Group,$Bytes,$Month,$Day,$YearOrTime,$Filename) = ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11);
			verbose 9, "find: vars($Inode,$Blocks,$Perms,$Links,$User,$Group,$Bytes,$Month,$Day,$YearOrTime,$Filename)";
			if ($Filename =~ /^(.*) -> (.*)/)
			{
				my ($SymLinkFrom, $SymLinkTo) = ($1, $2);
				$Find{$SymLinkFrom} = "nosum $Perms $User $Group $Bytes $Month $Day $YearOrTime $SymLinkFrom -> $SymLinkTo";
			}
			elsif ($Perms =~ /^d/)
			{
				$Find{$Filename} = "nosum $Perms $User $Group 0 $Month $Day $YearOrTime $Filename";
			}
			else
			{
				$Find{$Filename} = "nosum $Perms $User $Group $Bytes $Month $Day $YearOrTime $Filename";
			}
		}
		else
		{
			error 1, q#format of "%s" line incorrect (%s)#, $Cmd, $Line;
		}
	}
	return %Find;
}

###############
# NOTE: there will be no errors from find since it is behind a pipe - which is ok, FindFilesInDir() can take care of any problems
sub SumFilesInDir
{
	verbose "f", "%s()", (caller(0))[3];
	my ($Dir) = @_;
	my %Sum = ();
	my $Cmd =  "cd $Dir && find . -type f |xargs sum __dummy__ 2>/dev/null";  # __dummy__ file because sum does not give filename if there is only one file in the list
	verbose "sys", q#sum: executing "%s"#, $Cmd;
	my $Out = `$Cmd`;
	verbose 2, "sum: collected info (sum/size/name) on files in %s", $Dir;
	foreach my $Line (split /\n/, $Out)
	{
		verbose 9, "sum: line:%s", $Line;
		if ($Line =~ /^([^\s]+)\s+([^\s]+)\s+(.*)/)
		{
			my ($Sum,$Blocks,$Filename) = ($1,$2,$3);
			verbose 9, "sum: vars($Sum,$Blocks,$Filename)";
			$Sum{$Filename} = "$Sum";
		}
		else
		{
			error 1, q#format of sum line incorrect (%s)#, $Line;
		}
	}
	return %Sum;
}

###################
sub SumFilesInDirs
{
	verbose "f", "%s()", (caller(0))[3];
	my (@Dirs) = @_;
	my %DirFiles = ();
	my %Find = ();
	my %Sum = ();
	foreach my $Dir (@Dirs)
	{
		%Find = FindFilesInDir $Dir;
		%Sum  = SumFilesInDir  $Dir;
		foreach my $Filename (keys %Find)
		{
			$DirFiles{$Dir}{$Filename} = $Find{$Filename};
		}
		foreach my $Filename (keys %Sum)
		{
			$DirFiles{$Dir}{$Filename} =~ s/^nosum /$Sum{$Filename} /;
		}
	}
#	PrintRecursiveHashDebug %DirFiles;
	return %DirFiles;
}


########
sub Main
{
	verbose "f", "%s()", (caller(0))[3];
	our (@Dirs);

	verbose 1, "checking dirs: %s", join(',',@Dirs);
	my %DirFilesWithDate = SumFilesInDirs @Dirs;
	my %DirFiles         = RemoveDate     %DirFilesWithDate;
	my %MissingFiles = MissingFiles 1, %DirFiles;
	my %ExtraFiles   = ExtraFiles   1, %DirFiles;
}

###########
GetOptions;
Main;
exit 0;

