# rigol_dg1022_tools

## Introduction
Perl command line tools to manage rdf wavform files for the Rigol DG1022
arbitrary function generator.

I have developed some small utilities to manage waveform files for
the Rigol DG1022 arbitrary function generator (rdf files).
As I was interacting with LTSpice anyway, I used its pwl format as a standard
and provided a function to convert LTSpice pwl files to rdf format.

## pwl2rdf.pl
```
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
```

## pwl.pl
```
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
```

## rdfdump.pl
```
Usage: rdfump.pl [-OPTIONS] [--] FILENAME

Dump a RIGOL rdf data file as two column text. 

  -d        Produce debug output.
  --help    Show this help text.
  --version Show program version.
```
