#!/usr/bin/perl -w

use strict;
#eval("use diagnostics"); # not all perls provide diagnostics.
eval("use Math::Trig"); # missing module non-fatal.

use Getopt::Std; $Getopt::Std::STANDARD_HELP_VERSION = 1;
# avoid "Name "Getopt::Std::STANDARD_HELP_VERSION" used only once: possible typo at pwl.pl line 7."
my $_x = $Getopt::Std::STANDARD_HELP_VERSION;

my %opts;
exit 1 if !getopts("0:d:eg:mr:t:T:v:V:", \%opts);
my $optnul = $opts{0};
my $optfmt = $opts{d} ? $opts{d} : "pwl";
my $optexp = $opts{e};
my $optgen = $opts{g};
my $optmul = $opts{m};
my $optrep = $opts{r} ? $opts{r} : 1;

my (@t, @tx, @v, @vx);
my ($tmin, $vmin, $tmax, $vmax, $deltat, $deltav);
my $pi2 = pi() + pi();

sub VERSION_MESSAGE($) {
  my $fh = shift;
  print $fh "v3.1\n";
}

sub HELP_MESSAGE($) {
  my $fh = shift;
  print $fh <<END_USAGE;
Usage: pwl.pl [-OPTIONS] [--] [< FILENAME]
       pwl.pl [-OPTIONS] [--] [FILENAME ...]
       cat FILENAME | pwl.pl [-OPTIONS]

Transforms a given or creates a SPICE time/voltage PWL sequence so that it meets 
certain electrical and timing criteria.
Numbers may be specified using SPICE exponential suffixes like g, meg, k,
m, u, n, p, f.
Note that the program preserves suffixes from the input data in the 
calculation.

  -0 x      Add a 0,x-record before the other data, after the transformation.
  -d x      Use x as output separator string between values. Otherwise or
            with x = pwl the output is in PWL format. Input is always expected
            in PWL format.
  -e        Output without exponential suffixes.
  -g x      Generate a unity pulse of 1s duration. No input stream is 
            accepted with -g.
            rct: rectangular pulse, 1V amplitude, 1ms/V slew rate. 
            rmp: ramp from 0,0 to 1s,1V.
            sin: sinusoidal pulse, +/-1V amplitude.
	    fnc: arbitray perl syntax function of t, use "fnc:from,to,steps,f". 
	      You might need to put part of or the whole expression in quotes.
	      Steps must be between 1 and 1000. 
	      You may reference from, to, steps, (to - from)/(steps - 1) as t0, 
	      t1, s and dt inside the function.
  -m        Modify -V x and -T x to multiply respective values with x;
            no effect to -v and -t.a
  -r n      Cycle n times, shifting time by 100.1% of pulse width or by -t x.
            The additinal 0.1% is to avoid singularities between pulses.
  -v x      Shift voltage by x.
  -V x      Transform voltage so that Vmax becomes x.
  -t x      Shift time by x, or with -r use cycle period of x.
  -T x      Transform time so that Tmax becomes x.
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

#
# Generate an arbitrary fuction.
# Argument $args of format "t0,t1,n,f".
# Generate n value pairs t,f.t with t from t0 to t1.
#
sub generateFunction($) {
  my $args = shift;
  my ($from, $to, $steps, $fn) = split(/,/, $args);
  
  $from = sfxval($from);
  $to = sfxval($to);
  $steps = sfxval($steps);
  my $dt = ($to - $from) / ($steps - 1);
  
  if (($steps < 1) or ($steps > 1000)) {
    die "steps should be in 1, 1000 but is $steps";
  }
  
  $fn =~ s/\bt0\b/$from/ig; # replace constant
  $fn =~ s/\bt1\b/$to/ig;   # replace constant
  $fn =~ s/\bs\b/$steps/ig; # replace constant
  $fn =~ s/\bdt\b/$dt/ig;   # replace constant
  $fn =~ s/\bt\b/\$_t/ig;   # replace variable
  
  my $_v = 0;
  my $_t = $from;
  for (my $i = 0; $i < $steps; $i++) {
    # Evaluate function and die on division by zero.
    my $formula = "\$_v=$fn"; eval($formula); die $@ if $@;
    push @t, $_t; push @tx, ""; push @v, $_v; push @vx, "";
    $_t += $dt;
  }
}

#
# Generate primitive waveforms:
# rct: rectangle with 1s, height 1V
# rmp: linear ramp from 0s/0V to 1s/1V
# sin: sinus from 0 to 1s, -1V to 1V
#
sub generate() {
  # Generate a single rectangular unity pulse of 1s/1V
  if ($optgen eq "rct") {
    push @t, 0.000; push @tx, ""; push @v, 0; push @vx, "";
    push @t, 0.001; push @tx, ""; push @v, 1; push @vx, "";
    push @t, 0.999; push @tx, ""; push @v, 1; push @vx, "";
    push @t, 1.000; push @tx, ""; push @v, 0; push @vx, "";
  }
  
  # Generate a sinusoidal pulse of 1s/1V
  elsif ($optgen eq "sin") {
    my $d = pi() / 10;
    for (my $x = 0; $x < $pi2 + $d; $x += $d) {
      push @t, $x / $pi2; push @tx, ""; push @v, sin($x); push @vx, "";
    }
  }
  
  # Generate a ramp from 0s/0V to 1s/1V
  elsif ($optgen eq "rmp") {
    push @t, 0.000; push @tx, ""; push @v, 0; push @vx, "";
    push @t, 1.000; push @tx, ""; push @v, 1; push @vx, "";
  }
  
  # Generate am arbitrary function
  elsif (substr($optgen, 0, 4) eq "fnc:") {
    generateFunction(substr($optgen, 4));
  }
  
  else {
    print STDERR "don't know how to generate $optgen.\n";
    exit;
  }
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
}

#
# Perform linear transformation of all data using parameters
# specified.
#
sub transform() {
  return unless (dataSz() > 0);
  
  updateStats();
  
  for (my $i = 0; $i < dataSz(); $i++) {
    my ($t, $tx, $v, $vx) = ($t[$i], $tx[$i], $v[$i], $vx[$i]);

    if ($optmul) {
      if (defined $optvmax) { $v *= $optvmax; }
      if (defined $opttmax) { $t *= $opttmax; }
    }
    else {
      if (defined $optvmax) { $v = (($v - $vmin) / $deltav * ($optvmax - $vmin)) + $vmin; }
      if (defined $opttmax) { $t = (($t - $tmin) / $deltat * ($opttmax - $tmin)) + $tmin; }
    }

    if (defined $optvadd) { $v += $optvadd; }
    if (defined $opttadd && ($optrep < 2)) { $t += $opttadd; } # shift only for single cycle

    ($t[$i], $v[$i]) = ($t, $v);
  }

  updateStats();
}

#
# Output data to stdout using specified formatting options.
#
sub output() {
  # formatting
  my ($sep1, $sep2);
  if ($optfmt eq "pwl") {
    ($sep1, $sep2) = ("\t", "\n");
  }
  else {
    ($sep1, $sep2) = ($optfmt, $optfmt);
  }
  
  # prefix with a 0-0-record on request
  if (defined $optnul) {
    my $v0 = $optnul;
    my $v0x = "";
    
    my $val = numsfx2val(\$v0, \$v0x);
    $v0 = $val;
   
    unshift @t, 0; unshift @tx, ""; unshift @v, $v0; unshift @vx, $v0x;
  }  
  
  for (my $k = 0; $k < $optrep; $k++) {
    for (my $i = 0; $i < dataSz(); $i++) {
      my $last = ($k == $optrep - 1) && ($i == dataSz() - 1);
      
      # no separator at end of last item, except for a newline.
      if ($last && ($sep2 ne "\n")) { $sep2 = ""; }
      
      my ($t, $tx, $v, $vx) = ($t[$i], $tx[$i], $v[$i], $vx[$i]);

      # shift time when doing multiple cycles.
      if (defined $opttadd) { 
        $t += $k * $opttadd; # shift by supplied value.
      }
      else {
        $t += $k * 1.001 * $deltat; # shift by 100.1% of pulse width.
      }

      if (defined $optexp) {
        printf("%e%s%e%s", $t, $sep1, $v, $sep2);
      }
      else {
        $t /= sfx2exp($tx);
        $v /= sfx2exp($vx);
        printf("%g%s%g%s", $t, $tx . $sep1, $v, $vx . $sep2);
      }
    }
  }
}

#
# MAIN
#
if (defined $optgen) {
  generate();
}
else {
  loadData();
}
transform();

if (($optrep > 1) && (defined $opttadd) && ($opttadd <= $deltat)) {
  die "Time to add suplied with -t must be > pulse width (which is $deltat).";
}

output();


