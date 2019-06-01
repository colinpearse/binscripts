#!/usr/bin/perl
#!/usr/bin/perl -d

# Author:      Colin Pearse
# Name:        readexcel.pl
# Description: Read an Excel spreadsheet (97-2003) using Spreadsheet::ParseExcel


our $VERSION = "0.1";

our $Myname = $0; { $Myname =~ s,.*/,,; } # bug in grep means I can't strip dir this outside these brackets

use strict;
use warnings;
no warnings 'uninitialized';

use lib qw(/usr/local/lib/perl/5.005);

use Getopt::Std;
use Spreadsheet::ParseExcel;

#############
#############
sub usage
{
	our $Myname;

	print STDERR qq{
usage: $Myname [-d <char>] <xls filename OR - for stdin> [sheet no]

       -d <char>     set delimiter character (default is a TAB character)

   Eg: cat File.xls |$Myname -d',' - 0

};
	exit 2;
}

#############
#############
sub create_tmpfile
{
	our $Myname;
	my $TmpFilename = "/tmp/$Myname.$$";

	open (TmpFD, "> $TmpFilename");
	while(<STDIN>)
	{
		print TmpFD $_;
	}
	close(TmpFD);
	return $TmpFilename;
}

#############
#############
sub ShowSpreadSheet
{
	my ($Filename, $Sheet, $Delimiter) = @_;
	my $RetValue = 0;

	my $TmpFilename;
	if ($Filename eq "-")
	{
		$TmpFilename = create_tmpfile;
		$Filename = $TmpFilename;
	}

	if (-r $Filename)
	{
		$Delimiter = "\t" unless defined $Delimiter;

		my $e = new Spreadsheet::ParseExcel;
		my $eBook = $e->Parse($Filename);

		my $Sheets = $eBook->{SheetCount};
		my $eSheet = $eBook->{Worksheet}[$Sheet];  # default is sheet 0
		my $SheetName = $eSheet->{Name};           # Sheet should be called "Servers" but I won't check this for now

		print STDERR "Sheet: $eSheet->{Name}\n";
		#printf "Worksheet %d: %s (MaxRow = %d, MaxCol = %d\n", "$Sheet", "$SheetName", "$eSheet->{MaxRow}", "$eSheet->{MaxCol}";

		foreach my $row ($eSheet->{MinRow} .. $eSheet->{MaxRow})
		{
			foreach my $col ($eSheet->{MinCol} .. $eSheet->{MaxCol})
			{
				my $val = "";
				$val = $eSheet->{Cells}[$row][$col]->Value() if (defined $eSheet->{Cells}[$row][$col]);
				$val =~ s/[$Delimiter\r\n]/ /g;  # make sure cell doesn't have $Delimiter or CR or NL
				print "$val$Delimiter";
			}
			print "\n";
		}
		$RetValue = 1;
	}
	else
	{
		print STDERR qq{$0: Cannot read file "$Filename" (Error=$!)\n};
	}

	if (defined $TmpFilename)
	{
		if (!unlink ($TmpFilename))
		{
			print STDERR qq{$0: Cannot remove temporary file "$TmpFilename" (Error=$!)\n};
		}
	}

	return $RetValue;
}

########
# Main
########
my %options = ();
getopts("d:h:",\%options) or usage;
my $Filename = shift || usage;
my $Sheet    = shift || 0;

exit 0 if ShowSpreadSheet $Filename, $Sheet, $options{d};
exit 1;

