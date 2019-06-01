#!/usr/bin/perl
#!/usr/bin/perl -d

# File:         writeexcel.pl
# Description:  Write an Excel spreadsheet (97-2003) from a csv file using Spreadsheet::WriteExcel


our $VERSION = "1.2";

our $Myname = $0; { $Myname =~ s,.*/,,; } # bug in grep means I can't strip dir this outside these brackets

use strict;
use warnings;
no warnings 'uninitialized';

# /usr/local/lib/perl/5.005 - for WriteExcel
# /opt/perl5/lib/site_perl/5.8.5 - has Parse::RecDecent (used by WriteExcel's autofilter function)
use lib qw(/usr/local/lib/perl/5.005);

use POSIX;
use Getopt::Std;
#use Spreadsheet::ParseExcel;
use Spreadsheet::WriteExcel;

# Excel maximums
our $ExcelRowMax          = 65536;
our $ExcelColMax          = 256;
our $ExcelStringMax       = 32767;
#our $ExcelSheetNameMax    = 31;   # sheet names are currently hardcoded
#our $ExcelHeaderFooterMax = 254;  # don't use this

our $Delimiter = ',';
our $VerbosityLevel = 1;
our $FormattingScript = "";
our $CreateColourSheet = 0;
our $TempfileStdin = "/tmp/$Myname.$$.stdin";
our $OutputFile;
our $Sheet0 = "sheet0";
our $Sheet1 = "sheet1";

#######################
#######################
our @Tempfiles = ();
$SIG{INT} = sub {};
END
{
	foreach(@Tempfiles)
	{
		unlink($_) if -e $_;
#		printf STDERR "Removed $_\n";
	}
}

###############
###############
sub verbose
{
	my ($Level, $Format, @Args) = @_;
	my $Str = sprintf "$Format", @Args;
	print STDERR "$Str\n" if $VerbosityLevel >= $Level;
}

###############
###############
sub error
{
	our ($Myname);
	my ($ExitValue, $Format, @Args) = @_;
	verbose(1, "$Myname: ERROR: $Format", @Args);
	exit $ExitValue;
}

###############
###############
sub uniq
{
	my (@arr) = @_;
	my %h = ();
	foreach (@arr) { $h{$_} = ""; } 
	return keys %h;
}

###############
###############
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

###############
###############
sub arrayinarray
{
	my ($a1, @a2) = @_;
	foreach my $s (@{$a1})
	{
		return 1 if inarray $s, @a2;
	}
	return 0;
}

###############
###############
# Ignore non-existant files
# Returns $string. For arrays do: @a = split /\n/, ReadFiles $File1, $File2;
sub ReadFiles
{
	my @a;
	foreach(@_)
	{
		next if not (-e $_);
		open(my $fd, "<", $_);
		@a = (@a, <$fd>);
		close($fd);
	}
	return join("",@a);
}

#############
#############
sub GetPath
{
	my ($File) = @_;
	foreach my $Dir (split(':',$ENV{'PATH'}))
	{
		return "$Dir/$File" if (-f "$Dir/$File");
	}
	return "";
}

#############
#############
sub usage
{
	our $Myname;

	print STDERR qq{
 usage: $Myname <xlsfile>

 -d char       Set delimiter character (default: , character)
 -v level      Change verbosity level
 -f script     Format \%Xls according to script (PATH used to find file)
 -C            Add a sheet with colour and pattern codes on it

 Read stdin (csv format default) and write an xls file.

};
	exit 2;
}

###############
###############
sub GetOptions
{
	our %options;
	our ($InputFile, $OutputFile, $VerbosityLevel, $FormattingScript, $CreateColourSheet);

	getopts("d:v:f:Ch",\%options) or usage;
	usage if defined $options{h};
	$Delimiter         = $options{d} if defined $options{d};
	$VerbosityLevel    = $options{v} if defined $options{v};
	$FormattingScript  = $options{f} if defined $options{f};
	$CreateColourSheet = 1           if defined $options{C};

	if ($FormattingScript ne "")
	{
		my $FormattingScriptWithPath = (-e $FormattingScript) ? $FormattingScript : GetPath $FormattingScript;
		error 1, "Cannot find file %s", $FormattingScript if $FormattingScriptWithPath eq "";
		error 1, "Cannot read file %s", $FormattingScriptWithPath if not (-r $FormattingScriptWithPath);
		$FormattingScript = $FormattingScriptWithPath;
		error 1, "There is a Perl error with the formatting script %s - please investigate", $FormattingScript if TestFormattingScript() == 0;
	}
	usage if not defined $ARGV[0];
	usage if defined $ARGV[1];
	$OutputFile = $ARGV[0];
}

#################
#################
# This will test the formatting script file with 'strict' + expected variables to check that no extra
# variables have been added or syntax errors introduced which will make the eval fail
# later on. Eval fails silently so I need this check.
sub TestFormattingScript
{
	my $Commands = ReadFiles $FormattingScript;
	my $Tempfile = "/tmp/$Myname.$$.check_formatting";
	my $Tempfile2 = "/tmp/$Myname.$$.check_formatting.xls";
	push @Tempfiles, $Tempfile;
	push @Tempfiles, $Tempfile2;
	open(my $fd, ">", $Tempfile);
	# Insert all on line 1 so Perl errors that refer to $Tempfile can also refer to $FormattingScript
	# At a minimum I need to instantiate WriteExcel so that functions used legitimately are not
	# flagged as an error.
	printf $fd 'use strict; use lib qw(/usr/local/lib/perl/5.005); use Spreadsheet::WriteExcel; my (%s); $Xls->{Book}{Object} = Spreadsheet::WriteExcel->new("%s");  ', '$Xls', $Tempfile2;
	printf $fd "%s\n", $Commands;
	close ($fd);

	my $AllOutput = `perl $Tempfile 2>&1`;
	my $PerlExit = WEXITSTATUS($?);
	unlink $Tempfile;
	unlink $Tempfile2;
	if ($PerlExit ne 0)
	{
		$AllOutput =~ s/$Tempfile/$FormattingScript/g;   # ensure Perl errors appear to reference $FormattingScript
		$AllOutput =~ s/\nExecution.*//;                 # don't keep summary line as it refers to execution of script
		printf "\n%s\n", $AllOutput;
		return 0;
	}
	return 1;
}

#############
#############
# Set columns wider if necessary
sub SetColWidth
{
	my ($Xls, $sheet, $row) = @_;
	my $MinWidth = 5;
	foreach my $col (keys %{$Xls->{Sheet}{$sheet}{Data}{$row}})
	{
		$Xls->{Sheet}{$sheet}{ColWidth}{$col} = $MinWidth if not defined $Xls->{Sheet}{$sheet}{ColWidth}{$col};
		my $Data = $Xls->{Sheet}{$sheet}{Data}{$row}{$col};
		my $CurrentLength = $Xls->{Sheet}{$sheet}{ColWidth}{$col};
		my $NewLength = length($Data);
		$NewLength += 3 if $Data =~ /[A-Z]{3}/;    # if it has 3 or more uppercase letters then increase size
		$Xls->{Sheet}{$sheet}{ColWidth}{$col} = $NewLength if $NewLength > $CurrentLength;
	}
}

#############
#############
# %Format passed to add_format(). Don't need set_bold(), set_align() since everything
# is done when add_format is called, eg.
#  add_format( border => 1, bg_color => 43, bold => 1, text_wrap => 1, valign => 'vcenter', indent  => 1 );
# Other egs.
#  size => 12, color => 'blue', underline => 0x01, align => 'left', num_format => '#,##0', align => 'left',
#  num_format => '[Green]0.0%;[Red]-0.0%;0.0%',
# (see 5.005/Spreadsheet/WriteExcel/Format.pm)
#
# NOTE: Creating many Spreadsheet::WriteExcel::Format objects causes problems (see note in SetCell below)
#       so I save all the formats and reuse them where necessary.
sub samehash
{
	my ($h1, $h2) = @_;
	return 0 if keys %$h1 != keys %$h2;
	foreach my $key (keys %$h1)
	{
		return 0 if not (defined $h2->{$key} && $h1->{$key} eq $h2->{$key});
	}
	return 1;
}
sub SetCellFormat
{
	my ($Xls, $sheet, $row, $col, %Format) = @_;
	our %SavedFormats;
	my $FoundFormat = "";
	foreach my $SavedFormat (keys %{$SavedFormats{Hash}})
	{
		if(samehash \%{$SavedFormats{Hash}{$SavedFormat}}, \%Format)
		{
			$FoundFormat = $SavedFormats{Object}{$SavedFormat};
			last;
		}
	}
	if ($FoundFormat eq "")
	{
		$FoundFormat = $Xls->{Book}{Object}->add_format(%Format);
		$SavedFormats{Hash}{\%Format} = \%Format;    # need this because dereferencing doesn't work for the key - Perl sees it as a string only
		$SavedFormats{Object}{\%Format} = $FoundFormat;
	}
	$Xls->{Sheet}{$sheet}{CellFormat}{$row}{$col} = $FoundFormat;
}


#############
#############
#
# NOTE: creating many add_format objects created the most bizarre error where some but not all of the
#       formatting would be done. Sometimes formatting only 2/3 and stopping halfway on a line!!
#           
#       I noticed that fewer lines corrected the problem (because it used less memory?) so tried to force
#       WriteExcel to use temporary file. But compatibility_mode(0) and set_tempdir("/tmp/zztest") didn't
#       seem to do this - I couldn't see any temp files before I called close().
#
#       However, without SetCellFormat for every cell (30000 cells roughly) it halved the xls size
#       and now takes a second to open instead of 20 seconds!
#
#       A couple of functions still call SetCell with a hash, not object so check which is which and
#       act accordingly.
#
sub SetCell
{
	my ($Xls, $sheet, $row, $col, $Format, $value) = @_;
	if (ref($Format) eq "HASH")
	{
		SetCellFormat \%{$Xls}, $sheet, $row, $col, %{$Format};
	}
	else # ref($Format) will be "Spreadsheet::WriteExcel::Format"
	{
		$Xls->{Sheet}{$sheet}{CellFormat}{$row}{$col} = $Format;
	}
	$Xls->{Sheet}{$sheet}{MaxRow} = $row if $row > $Xls->{Sheet}{$sheet}{MaxRow};
	$Xls->{Sheet}{$sheet}{MaxCol} = $col if $col > $Xls->{Sheet}{$sheet}{MaxCol};
	$Xls->{Sheet}{$sheet}{Data}{$row}{$col} = $value;

	error 9, "Excel maximum string size has been exceeded: %s", $ExcelStringMax if (length($value) > $ExcelStringMax);
	error 9, "Excel maximum row size has been exceeded: %s",    $ExcelRowMax    if ($row           > $ExcelRowMax);
	error 9, "Excel maximum col size has been exceeded: %s",    $ExcelColMax    if ($col           > $ExcelColMax);
}

#############
#############
sub FillSpreadsheetData
{
	verbose 9, "%s()", (caller(0))[3];
	our ($Delimiter);
	my ($Xls, $sheet) = @_;
	my $FormatHeading = $Xls->{Book}{Object}->add_format( bold => 1, bottom => 1, right => 1, text_wrap => 1, bg_color => 42, color => "white" );
	my $Format        = $Xls->{Book}{Object}->add_format( bg_color => 51 );
	my $Heading = <STDIN>;
	chomp $Heading;
	my @Heading = split($Delimiter, $Heading);
	my $colsNumber= scalar @Heading; ## Number of cols taken from $Heading
	my $row = 0;
	my $col = 0;
	foreach my $Cell (@Heading)
	{
		SetCell \%{$Xls}, $sheet, $row, $col++, $FormatHeading, $Cell;
	}
	$row++;
	while (my $Line = <STDIN>)
	{
		chomp $Line;
		$col = 0;
        my @Line = split($Delimiter, $Line);
        
		foreach my $Cell (@Line)
		{
			SetCell \%{$Xls}, $sheet, $row, $col++, $Format, $Cell;
		}
        ## if cells are empty or row has less then cols then heading setup the formating
        for (my $i= scalar @Line; $i < $colsNumber; $i++) {
            SetCell \%{$Xls}, $sheet, $row, $col++, $Format, "";
        }

		SetColWidth \%{$Xls}, $sheet, $row;
		$row++;
	}
}

#############
#############
# Create objects before writing so I can use the WriteExcel functions to set attributes in other functions.
sub CreateSpreadsheet
{
	verbose 9, "%s()", (caller(0))[3];
	my ($Xls) = @_;
	verbose 1, "Creating spreadsheet \"%s\"", $OutputFile;
	$Xls->{Book}{Name} = $OutputFile;
	$Xls->{Book}{Object} = Spreadsheet::WriteExcel->new($OutputFile);
	$Xls->{Sheet}{$Sheet0}{Name} = "$Sheet0";
	$Xls->{Sheet}{$Sheet0}{Object} = $Xls->{Book}{Object}->add_worksheet( $Xls->{Sheet}{$Sheet0}{Name} );
	$Xls->{Sheet}{$Sheet0}{MaxRow} = 0;
	$Xls->{Sheet}{$Sheet0}{MaxCol} = 0;
	# $Xls->{Sheet}{$Maps}{Data}{..}{..} will contain the data

#	my $Grey1 = $Xls->{Book}{Object}->set_custom_color(40, 238, 238, 238);
#	my $Grey2 = $Xls->{Book}{Object}->set_custom_color(41, 216, 216, 216);
	my $Grey3 = $Xls->{Book}{Object}->set_custom_color(42, 70, 70, 70);
#	my $Blue1 = $Xls->{Book}{Object}->set_custom_color(45, 194, 227, 236);
#	my $Blue2 = $Xls->{Book}{Object}->set_custom_color(46, 182, 221, 232);
#	my $Green1 = $Xls->{Book}{Object}->set_custom_color(47, 201, 219, 165);
#	my $Green2 = $Xls->{Book}{Object}->set_custom_color(48, 192, 213, 151);
	my $Pink1 = $Xls->{Book}{Object}->set_custom_color(51, 253, 223, 199);
#	my $Pink2 = $Xls->{Book}{Object}->set_custom_color(52, 252, 213, 180);
#	my $Pink3 = $Xls->{Book}{Object}->set_custom_color(53, 249, 184, 131);
#	my $Pink4 = $Xls->{Book}{Object}->set_custom_color(54, 248, 169, 104);
}

#############
#############
sub CreateColourSheet
{
	verbose 9, "%s()", (caller(0))[3];
	my ($Xls) = @_;
	$Xls->{Sheet}{Colours}{Name} = "Colour Chart";
	$Xls->{Sheet}{Colours}{Object} = $Xls->{Book}{Object}->add_worksheet( $Xls->{Sheet}{Colours}{Name} );
	my $Colour = 0;
	foreach my $row (1 .. 5)
	{
		foreach my $col (1 .. 20)
		{
			$Xls->{Sheet}{Colours}{ColWidth}{$col} = 3;
			$Xls->{Sheet}{Colours}{Data}{$row}{$col} = "$Colour";
			SetCellFormat \%{$Xls}, "Colours", $row, $col, bg_color => $Colour++;
			last if $Colour > 70;
		}
		last if $Colour > 70;
	}
	my $Pattern = 0;
	foreach my $row (7 .. 11)
	{
		foreach my $col (1 .. 20)
		{
			$Xls->{Sheet}{Colours}{Data}{$row}{$col} = "$Pattern";
			SetCellFormat \%{$Xls}, "Colours", $row, $col, pattern => $Pattern++;
			last if $Pattern > 70;
		}
		last if $Pattern > 70;
	}
}

#############
#############
sub WriteTestSheet
{
	verbose 9, "%s()", (caller(0))[3];
	my (%Xls) = @_;
	my $format = $Xls{Book}{Object}->add_format(center_across => 1, bg_color => "black", color => "white", right => 9);
	$Xls{Sheet}{test}{Object} = $Xls{Book}{Object}->add_worksheet( "test" );
	$Xls{Sheet}{test}{Object}->write(2, 1, "x", $format);
	$Xls{Sheet}{test}{Object}->write_blank(2, 2, $format);
	$Xls{Sheet}{test}{Object}->write(2, 3, "x", $format);

	$format = $Xls{Book}{Object}->add_format(center_across => 1, bg_color => "black", color => "white", border => 1, right_color => 9 );
	$Xls{Sheet}{test}{Object}->write(4, 1, "x", $format);
	$Xls{Sheet}{test}{Object}->write_blank(4, 2, $format);
	$Xls{Sheet}{test}{Object}->write(4, 3, "x", $format);
}

###############
###############
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
			printf $fd "${Text}${Colon}%s\n", $key;
			PrintRecursiveHashLong($fd, "$Text${Colon}$key", %{$value});
		}
		else
		{
			printf $fd "${Text}${Colon}%s:%s\n", $key, $value              if (ref($value) ne "ARRAY");
			printf $fd "${Text}${Colon}%s:%s\n", $key, join " ", @{$value} if (ref($value) eq "ARRAY");
		}
	}
}

#############
#############
sub DisplaySpreadsheetData
{
	verbose 9, "%s()", (caller(0))[3];
	my (%Xls) = @_;
	foreach my $sheet (keys %{$Xls{Sheet}})
	{
		foreach my $col (sort { $a <=> $b } keys %{$Xls{Sheet}{$sheet}{ColWidth}})
		{
			verbose 1, "sheet %s (0, %d) width = %s", $sheet, $col, $Xls{Sheet}{$sheet}{ColWidth}{$col};
		}
		foreach my $row (sort { $a <=> $b } keys %{$Xls{Sheet}{$sheet}{Data}})
		{
			foreach my $col (sort { $a <=> $b } keys %{$Xls{Sheet}{$sheet}{Data}{$row}})
			{
				verbose 1, "sheet %s (%d, %d) %s", $sheet, $row, $col, $Xls{Sheet}{$sheet}{Data}{$row}{$col};
			}
		}
	}
}

#############
#############
# Don't need to sort to write the spreadsheet but it may help when debugging.
sub WriteSpreadsheet
{
	verbose 9, "%s()", (caller(0))[3];
	my (%Xls) = @_;
	foreach my $sheet (keys %{$Xls{Sheet}})
	{
		verbose 1, "Writing sheet \"%s\"", $Xls{Sheet}{$sheet}{Name};
		foreach my $col (sort { $a <=> $b } keys %{$Xls{Sheet}{$sheet}{ColWidth}})
		{
			$Xls{Sheet}{$sheet}{Object}->set_column($col, $col, $Xls{Sheet}{$sheet}{ColWidth}{$col});
		}
		# NOTE: Use 0..max instead of sort {$a <=> $b} keys %{$Xls{Sheet}{$sheet}{Data} because it's
		#       possible for input to not have final columns leading to the for loop exiting too soon
		for my $row (0..$Xls{Sheet}{$sheet}{MaxRow})
		{
			for my $col (0..$Xls{Sheet}{$sheet}{MaxCol})
			{
				my $Data = $Xls{Sheet}{$sheet}{Data}{$row}{$col};
				$Xls{Sheet}{$sheet}{Object}->write_blank($row, $col, $Xls{Sheet}{$sheet}{CellFormat}{$row}{$col}) if $Data eq "--merge--";
				$Xls{Sheet}{$sheet}{Object}->write($row, $col, $Data, $Xls{Sheet}{$sheet}{CellFormat}{$row}{$col}) if $Data ne "--merge--";
			}
		}
#		foreach my $row (sort { $a <=> $b } keys %{$Xls{Sheet}{$sheet}{Data}})
#		{
#			foreach my $col (sort { $a <=> $b } keys %{$Xls{Sheet}{$sheet}{Data}{$row}})
#			{
#				my $Data = $Xls{Sheet}{$sheet}{Data}{$row}{$col};
#				$Xls{Sheet}{$sheet}{Object}->write_blank($row, $col, $Xls{Sheet}{$sheet}{CellFormat}{$row}{$col}) if $Data eq "--merge--";
#				$Xls{Sheet}{$sheet}{Object}->write($row, $col, $Data, $Xls{Sheet}{$sheet}{CellFormat}{$row}{$col}) if $Data ne "--merge--";
#			}
#		}
	}
	# NOTE: Force close (and write) write of spreadsheet because...
	#       if $FormattingScript contains a subroutine then bizarrely WriteExcel's
	#       destructor isn't called (which calls close) when Main() exits!
	$Xls{Book}{Object}->close();
}

#############
#############
sub UserDefinedFormatting
{
	verbose 9, "%s()", (caller(0))[3];
	my ($Xls) = @_;
	verbose 1, "Using user script (%s) to change formatting", $FormattingScript;
	eval `cat $FormattingScript`;
}

########
########
sub Main
{
	verbose 9, "%s()", (caller(0))[3];
	my %FrameLpars;
	my %SiteLpars;
	my %Lpars;
	my %Xls;
	GetOptions;
	CreateSpreadsheet \%Xls;
	CreateColourSheet \%Xls if $CreateColourSheet;
	FillSpreadsheetData \%Xls, $Sheet0;
	UserDefinedFormatting \%Xls if $FormattingScript ne "";
	DisplaySpreadsheetData %Xls if $VerbosityLevel >= 50;
	WriteSpreadsheet %Xls;
#	WriteTestSheet %Xls;
}

########
########
Main;
exit 0;

