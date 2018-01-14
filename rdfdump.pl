#!/usr/bin/perl -w

use strict;
#eval("use diagnostics"); # not all perls provide diagnostics.

use Getopt::Std; $Getopt::Std::STANDARD_HELP_VERSION = 1;
# avoid "Name "Getopt::Std::STANDARD_HELP_VERSION" used only once: possible typo at pwl.pl line 7."
my $_x = $Getopt::Std::STANDARD_HELP_VERSION;

my %opts;
exit 1 if !getopts("d", \%opts);
my $optdbg = $opts{d};
my $rdfin = $ARGV[0] ? $ARGV[0] : "pwl.rdf";

my $vrdf;

sub VERSION_MESSAGE($) {
  my $fh = shift;
  print $fh "v1.0\n";
}

sub HELP_MESSAGE($) {
  my $fh = shift;
  print $fh <<END_USAGE;
Usage: rdfump.pl [-OPTIONS] [--] FILENAME

Dump a RIGOL rdf data file as two column text. 

  -d        Produce debug output.
  --help    Show this help text.
  --version Show program version.
END_USAGE
  exit;
}

#
# Load data from standard input into arrays and convert
# any exponential suffixes.
#
sub loadData() {
  open RDFIN, "$rdfin" or die "can't open $rdfin for input: $!";
  binmode RDFIN;
  my $bytesRd = read RDFIN, $vrdf, 8192;
  close RDFIN;
  
  ($bytesRd == 8192) or die "input file has incorrect leght: $bytesRd";
}

#
# Output data to stdout using specified formatting options.
#
sub output() {
  if ($optdbg) {
    my $val = 0;
    my $valm = 65535;
    for (my $i = 0; $i < 8192; $i += 128) {
      for (my $j = 0; $j < 128; $j += 2) {
        my $v = unpack("v", (substr $vrdf, $i+$j, 2));
        if ($v > $val) { $val = $v; }
        if ($v < $valm) { $valm = $v; }
      }

      # Display minimum/maximum values.
      # Values are from 0..65535, use about 100 chars for full range,
      # thus divide value by 656.
      my $dd = $valm/656;
      my $ee = $val/656;
      my $ss = ' ' x ($ee + 1);
      substr($ss, $dd, $ee - $dd + 1) = "." x ($ee - $dd + 1);
      #substr($ss, $ee, 1) = "+"; # max
      substr($ss, $dd, 1) = "*"; # min
      printf "%4u|%s %u, %u\n", $i/2, $ss, $valm, $val;

      $val = 0;
      $valm = 65535;
    }
  }
  
  else {
    for (my $i = 0; $i < 8192; $i += 2) {
      my $val = unpack("v", (substr $vrdf, $i, 2));
      print $i/2, "\t", $val, "\n";
    }
  }  
}

#
# MAIN
#
loadData();
output();
