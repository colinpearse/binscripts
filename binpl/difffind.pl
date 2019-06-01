#!/usr/bin/perl
#!/usr/bin/perl -d

# File:         difffind.pl
# Description:  Compare the output of two finds


our $VERSION = "0.1";

our $Myname = $0; { $Myname =~ s,.*/,,; } # bug in grep means I can't strip dir this outside these brackets

use strict;
use warnings;
no warnings 'uninitialized';

use lib q(/home/pearcolb/lib/perl5);

use Getopt::Std;
use Algorithm::Diff;


###############
our $VerbosityLevel = 1;
our $UsualIgnoreFilesExpr = "^/opt/beyondtrust/|^/proc/|^/var/spool/";
our $IgnoreFilesExpr = "do not ignore any files";
our $File1 = "";
our $File2 = "";


#############
sub verbose
{
	my ($Level, $Format, @Args) = @_;
	my $Str = (@Args ? sprintf("$Format", @Args) : $Format);
	print STDERR "$Str\n" if ($VerbosityLevel >= $Level);
}

#########
sub usage
{
	our $Myname;
	print STDERR qq{
 usage: $Myname <file1> <file2>

 -v level    verbosity level (default: $VerbosityLevel)
 -e expr     ignore files expr; -e usual will ignore "$UsualIgnoreFilesExpr"

 Compare the output of two finds.

 eg. $Myname -e usual find.ls.pre find.ls.post

};
	exit 2;
}


###############
sub GetOptions
{
	our %options;
	our ($VerbosityLevel, $IgnoreFilesExpr, $UsualIgnoreFilesExpr, $File1, $File2);
	getopts("hv:e:",\%options) or usage;
	usage   if defined $options{h};
	$VerbosityLevel  = $options{v} if defined $options{v};
	$IgnoreFilesExpr = $options{e} if defined $options{e};
	$IgnoreFilesExpr = $UsualIgnoreFilesExpr if ($IgnoreFilesExpr eq "usual");
	$File1 = $ARGV[0];
	$File2 = $ARGV[1];
	usage if ($File1 eq "" || $File2 eq "");
}


#############
# GetDiffs @Diffs1, \@Diffs2, \@Array1, \@Array2
# - @Diffs1 will be all lines that are not in @Array2 (same as "diff f1 f2 |grep "^< " |cut -c3-")
# - @Diffs2 will be all lines that are not in @Array1 (same as "diff f1 f2 |grep "^> " |cut -c3-")
sub DiffFill
{
	my ($Diffs1Ptr, $Diffs2Ptr, $DiffObj, $DiffSep) = @_;
	@{$Diffs1Ptr} = (@{$Diffs1Ptr}, $DiffObj->Items(1));
	@{$Diffs2Ptr} = (@{$Diffs2Ptr}, $DiffObj->Items(2));
}
sub FillDiffs
{
	verbose 9, "%s()", (caller(0))[3];
	my ($Diffs1Ptr, $Diffs2Ptr, $Array1Ptr, $Array2Ptr) = @_;
	@{$Diffs1Ptr} = ();
	@{$Diffs2Ptr} = ();
	my $DiffObj = Algorithm::Diff->new(\@{$Array1Ptr}, \@{$Array2Ptr});
	$DiffObj->Base(1);   # Return line numbers, not indices
	while($DiffObj->Next())
	{
		next if $DiffObj->Same();
		if    (!$DiffObj->Items(2)) { DiffFill \@{$Diffs1Ptr}, \@{$Diffs2Ptr}, $DiffObj; }
		elsif (!$DiffObj->Items(1)) { DiffFill \@{$Diffs1Ptr}, \@{$Diffs2Ptr}, $DiffObj; }
		else                        { DiffFill \@{$Diffs1Ptr}, \@{$Diffs2Ptr}, $DiffObj; }
	}
}

#############
# "find / -ls" output differences eg:
#   136 4912 -rwxr-xr-x   1 root     root      5027584 May 16  2015 /boot/vmlinuz-3.10.0-229.7.2.el7.x86_64
#  1025    0 drwxr-xr-x  19 root     root         3160 Feb  3 16:23 /dev
# 15619    0 crw-rw----   1 root     tty        7, 134 Feb  3 16:23 /dev/vcsa6
#37626717    0 -rw-------   1 root     root            0 May 27 11:45 /proc/10/task/10/mem
#37626718    0 lrwxrwxrwx   1 root     root            0 May 27 11:45 /proc/10/task/10/cwd -> /
#37626719    0 lrwxrwxrwx   1 root     root            0 May 27 11:45 /proc/10/task/10/root -> /
#37626720    0 lrwxrwxrwx   1 root     root            0 May 27 11:45 /proc/10/task/10/exefind: /proc/10/task/10/exe: No such file or directory
sub GetFiles
{
	my ($File, $IgnoreExpr) = @_;
	verbose 9, "%s(%s)", (caller(0))[3], $File;
	my @Files = grep !/$IgnoreExpr/, `cat $File |egrep -vi "^\$|no such file or directory" |sed "s,.*[0-9][0-9] /,/,1" |awk '{print \$1}'`;
	chomp @Files;
	return sort @Files;
}


########
sub Main
{
	our ($File1, $File2, $IgnoreFilesExpr);
	verbose 9, "%s()", (caller(0))[3];
	my (@Diffs1, @Diffs2, @Lines1, @Lines2);
	@Lines1 = GetFiles $File1, $IgnoreFilesExpr;
	@Lines2 = GetFiles $File2, $IgnoreFilesExpr;
#	map { print "\@Lines1 ".$_."\n" } @Lines1;
#	map { print "\@Lines2 ".$_."\n" } @Lines2;
	FillDiffs \@Diffs1, \@Diffs2, \@Lines1, \@Lines2;
	map { print "\@Diffs1: ".$_."\n" } @Diffs1;
	map { print "\@Diffs2: ".$_."\n" } @Diffs2;
}

###########
GetOptions;
Main;
exit 0;

