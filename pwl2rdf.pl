#!/usr/bin/perl -w

use strict;
#eval("use diagnostics"); # not all perls provide diagnostics.

use Getopt::Std; $Getopt::Std::STANDARD_HELP_VERSION = 1;
# avoid "Name "Getopt::Std::STANDARD_HELP_VERSION" used only once: possible typo at pwl.pl line 7."
my $_x = $Getopt::Std::STANDARD_HELP_VERSION;

my %opts;
exit 1 if !getopts("0df:ty:", \%opts);
my $optnul = $opts{0};
my $optdbg = $opts{d};
my $optfnm = $opts{f} ? $opts{f} : "pwl.rdf";
my $opttxt = $opts{t};
my $optymx = $opts{y} ? $opts{y} : 16384;

my (@t, @tx, @v, @vx);
my ($tmin, $vmin, $tmax, $vmax, $deltat, $deltav);
my (@vrdf);

sub VERSION_MESSAGE($) {
  my $fh = shift;
  print $fh "v2.0\n";
}

sub HELP_MESSAGE($) {
  my $fh = shift;
  print $fh <<END_USAGE;
Usage: pwl2rdf.pl [-OPTIONS] [--] [< FILENAME]
       pwl2rdf.pl [-OPTIONS] [--] [FILENAME ...]
       cat FILENAME | pwl2rdf.pl [-OPTIONS]

Convert a pwl formatted sequence into a RIGOL rdf data file. 

  -0        Replace all negative values with 0.
  -d        Debug output.
  -f name   Name of the rdf output file. Defaults to pwl.rdf.
  -t        Produce two columns text output, e.g. to import into a spreadsheet.
  -y value  Use range from 0..val (<= 65535).
  --help    Show this help text.
  --version Show program version.
END_USAGE
  exit;
}

#
# Convert a (SPICE) exponential suffix to an exponential value. 
# E.g. u is micro is 1e-6.
#
sub sfx2exp($) {
  # Suffixes are not case sensitive.
  my $sfx = lc shift;
  $sfx eq "" && return 1;
  $sfx eq "g" && return 1e9;
  $sfx eq "meg" && return 1e6;
  $sfx eq "k" && return 1e3;
  $sfx eq "m" && return 1e-3;
  $sfx eq "u" && return 1e-6;
  $sfx eq "n" && return 1e-9;
  $sfx eq "p" && return 1e-12;
  $sfx eq "f" && return 1e-15;
  
  die "invalid exponential suffix '$sfx', should not get there.";
}

#
# Try to tokenize a number with exponential suffix and return its
# effective value.
# If the argument is a number with suffix, the value and suffix as 
# $$vRef and $$vxRef. Otherwise these values are unchanged. 
#
sub numsfx2val($$) {
  my $vRef = shift;
  my $vxRef = shift;
  if ($$vRef =~ /([+\-0-9\.e]+)(\D+)$/m) {
    $$vRef = $1;
    $$vxRef = $2;
    return $$vRef * sfx2exp($$vxRef);
  }
  else {
    return $$vRef;
  }
}

#
# Conveniently return the effective value of a suffixed number.
# The argument may be undefined (returns undefined too).
#
sub sfxval($) {
  my $v = shift;
  my $vx; # ignored
  return $v ? numsfx2val(\$v, \$vx) : $v;
}

my $optvmax = sfxval($opts{V});
my $opttmax = sfxval($opts{T});

my $optvadd = sfxval($opts{v});
my $opttadd = sfxval($opts{t});

#
# Load data from standard input into arrays and convert
# any exponential suffixes.
#
sub loadData() {
  while (<>) {
    my ($_t, $_v) = split;
    my ($_tx, $_vx) = ("", "");

    my $val;
    
    $val = numsfx2val(\$_t, \$_tx);
    $_t = $val;

    $val = numsfx2val(\$_v, \$_vx);
    $_v = $val;

    push @t, $_t; push @tx, $_tx;
    push @v, $_v; push @vx, $_vx;
  }
}

#
# Get the data size.
#
sub dataSz() {
  return scalar @t;
}

sub dataSzRdf() {
  return scalar @vrdf;
}

#
# Update statistics values.
#
sub updateStats() {
  ($tmax, $vmax) = ($t[0], $v[0]);
  ($tmin, $vmin) = ($t[0], $v[0]);

  for (my $i = 0; $i < dataSz(); $i++) {
    if ($t[$i] > $tmax) { $tmax = $t[$i]; }
    if ($t[$i] < $tmin) { $tmin = $t[$i]; }
    if ($v[$i] > $vmax) { $vmax = $v[$i]; }
    if ($v[$i] < $vmin) { $vmin = $v[$i]; }
  }

  $deltav = $vmax - $vmin; # pulse height
  $deltat = $tmax - $tmin; # pulse width
  
  $optdbg && print STDERR "tmin, tmax:", $tmin, ", ", $tmax, "\n";
  $optdbg && print STDERR "vmin, vmax:", $vmin, ", ", $vmax, "\n";
  $optdbg && print STDERR "deltat:", $deltat, "\n";
  $optdbg && print STDERR "deltay:", $deltav, "\n\n";
}

#
# Interpolate values between points using a bresenham line algorithm.
# Source: http://rosettacode.org/wiki/Bitmap/Bresenham's_line_algorithm#Perl
#
sub line
{
    my ($x0, $y0, $x1, $y1) = @_;
 
    my $steep = (abs($y1 - $y0) > abs($x1 - $x0));
    if ( $steep ) {
	( $y0, $x0 ) = ( $x0, $y0);
	( $y1, $x1 ) = ( $x1, $y1 );
    }
    if ( $x0 > $x1 ) {
	( $x1, $x0 ) = ( $x0, $x1 );
	( $y1, $y0 ) = ( $y0, $y1 );
    }
    my $deltax = $x1 - $x0;
    my $deltay = abs($y1 - $y0);
    my $error = $deltax / 2;
    my $ystep;
    my $y = $y0;
    my $x;
    $ystep = ( $y0 < $y1 ) ? 1 : -1;
    for( $x = $x0; $x <= $x1; $x += 1 ) {
	if ( $steep ) {
	    #$img->draw_point($y, $x);
            $vrdf[$y] = $x;
	} else {
	    #$img->draw_point($x, $y);
            $vrdf[$x] = $y;
	}
	$error -= $deltay;
	if ( $error < 0 ) {
	    $y += $ystep;
	    $error += $deltax;
	}
    }
}

#
# Perform linear transformation of all data using parameters
# specified.
#
sub transform() {
  return unless (dataSz() > 0);
  
  updateStats();
 
  my $k0 = 0; 
  $vrdf[0] = 0;
  for (my $i = 0; $i < dataSz(); $i++) {
    # Calculate predefined scatterd data values.
    my $k = 4095 * ($t[$i] / $deltat); 
    $k = int($k + 0.5);
    my $vk = $optymx * ($v[$i] / $deltav);
    $vk = int($vk + 0.5);
    $vrdf[$k] = $vk;

    $optdbg && print STDERR "set vk:", $vk, " at k:", $k, "\n";

    my $v0 = $vrdf[$k0];

    $optdbg && print STDERR "intp from k0:", $k0, " to k:", $k, "\n";
    $optdbg && print STDERR "  between v0:", $v0, " and vk:", $vk, "\n\n";

    line($k0, $v0, $k, $vk);

    #for (my $i = $k0+1; $i < $k; $i++) {
    #  my $deltax = $k - $k0 - 1;
    #  my $deltay = $vk - $v0;
    #
    #  my $v = int($vrdf[$i-1] + $deltay / $deltax + 0.5); 
    #  if ($v > $optymx) { $v = $optymx; }
    #  $vrdf[$i] = $v;
    #}

    $k0 = $k;
  }
  
  # Make negative values 0.
  if ($optnul) {
    for (my $i = 0; $i < dataSzRdf(); $i++) {
      if ($vrdf[$i] < 0) { $vrdf[$i] = 0; }
    }
  }
}

#
# Check for negative values in the rdf output.
#
sub checkRdfNegative() {
  my $rc = 0;

  for (my $i = 0; $i < dataSzRdf(); $i++) {
    if ($vrdf[$i] < 0) {
      print STDERR "neg at:", $i, ", val:", $vrdf[$i], "\n";
      $rc = 1;
      #last;
    }
  }

  return $rc;
}

#
# Output data to stdout using specified formatting options.
#
sub output() {
  if ($opttxt) { 
    # formatting
    my ($sep1, $sep2);
    ($sep1, $sep2) = ("\t", "\n");
 
    for (my $i = 0; $i < dataSzRdf(); $i++) {
      my $last = ($i == dataSzRdf() - 1);
      
      # no separator at end of last item, except for a newline.
      if ($last && ($sep2 ne "\n")) { $sep2 = ""; }
      
      printf("%i%s%i%s", $i, $sep1, $vrdf[$i], $sep2);
    }
  }
  
  else {
    open OUTF, "> $optfnm" or die "can't open $optfnm for writin: $!\n"; 
    binmode OUTF;
    for (my $i = 0; $i < dataSzRdf(); $i++) {
      # pack unsigned, short (16bit), little-endian
      my $pck = pack('v', $vrdf[$i]);
      print OUTF $pck;
    }
    close OUTF;
  }
}

#
# MAIN
#
loadData();
transform();
if (! checkRdfNegative()) {
  $optdbg || output();
}
else {
  print STDERR "found negative values after transforming, no output created.\n";
}
