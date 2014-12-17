
## this sub is made for nice display.  note: it creates an expression like "roundfloat(3.1415,'I')", not a number.  otherwise, it may well be cut off
sub makeroundexpr {
  sub roundfloat {
    defined($_[0]) or return "NaN";
    ((!defined($_[1])||($_[1] eq "I"))) and do {
    my $rv= (abs($_[0])>=100) ? sprintf("%.1f", $_[0]) :
        (abs($_[0])>=1) ? sprintf("%.2f", $_[0]) :
        (abs($_[0])>=0.1) ? sprintf("%.3f", $_[0]) : sprintf("%.4f", $_[0]);
    return $rv+0;  ## allow perl to cut off unimportant 0 at the end
    };
    return sprintf("%.".$_[1]."f", $_[0]);
  }

  defined($_[0]) or return "NaN";
  defined($_[1]) or return "roundfloat($_[0],'I')";
  return "roundfloat($_[0], ". substr($_[1],1,1).")";
}

sub pr {
  ## given a list of values, pick one at random,  the list can be
  ## already separated, or it can be comma-separated in one element
  my $string= join(",", @_);
  $string=~ s/\(//g;
  $string=~ s/\)//g;
  my @v= split(/\,/, $string);
  my $choice= int(rand($#v+0.99));
  return $v[$choice];
}

## arg1= start, arg2=end, arg3=add-every-time
sub rseq {
  (defined($_[2])) or $_[2]=1;  ## the default is increment by 1
  ($#_ > 3) and die "wrong rseq usage with too many arguments: $_\n";
  ($_[0] == $_[1]) and return $_[0];
  (($_[2])*($_[1]-$_[0])>0) or return(undef); ## we have to go the right direction
  my @v=();
  for (my $i=$_[0]; $i<=$_[1]; $i+=($_[2]||1)) {
    push(@v, 0.0+sprintf("%.4f",$i));
  }
  my $choice= int(rand($#v+0.99));
  return $v[$choice];
}

sub mean {
  my $sum=0.0;  for my $i (@_) { $sum+= $i; }
  return $sum/($#_+1);
}

sub var {
  my $mean= mean(@_);
  my $sum=0.0;  for my $i (@_) { $sum+= ($i-$mean)**2; }
  return $sum/($#_+1);
}

sub sd {
  return sqrt(var($_));
}

sub BlackScholes {
  my ($S, $X, $T, $r, $sd) = @_;
  (defined($S)) or die "BS: bad S\n";
  (defined($X)) or die "BS: bad X\n";
  (defined($T)) or die "BS: bad T\n";
  (defined($r)) or die "BS: bad r\n";
  (defined($sd)) or die "BS: bad sd\n";
  my $d1 = ( log($S/$X) + ($r+$sd**2/2)*$T ) / ( $sd * $T**0.5 );
  my $d2 = $d1 - $sd * $T**0.5;
  return $S * &CumNorm($d1) - $X * exp( -$r * $T ) * &CumNorm($d2);
}

sub CumNorm {
  my $x = shift;
  # the percentile under consideration
  my $Pi = 3.141592653589793238;
  # Taylor series coefficients
  my ($a1, $a2, $a3, $a4, $a5) = (0.319381530, -0.356563782, 1.781477937, -1.821255978, 1.330274429);
  # use symmetry to perform the calculation to the right of 0
  my $L = abs($x);
  my $k = 1/( 1 + 0.2316419*$L);
  my $CND = 1 - 1/(2*$Pi)**0.5 * exp(-$L**2/2)* ($a1*$k + $a2*$k**2 + $a3*$k**3 + $a4*$k**4 + $a5*$k**5);
  # then return the appropriate value
  return ($x >= 0) ? $CND : 1-$CND;
}

sub Norm {
  my $x = shift;
  # the percentile under consideration
  my $Pi = 3.141592653589793238;
  return 1.0/sqrt(2*$Pi)*exp(-$x**2/2);
}

sub max { return ($_[0]>$_[1]) ? $_[0] : $_[1]; }
sub min { return ($_[0]>$_[1]) ? $_[1] : $_[0]; }

sub round {
  my $rrr= defined($_[1]) ? $_[1] : 2;
  my $v= int($_[0]*(10**$rrr)+0.5)/(10**$rrr);
  return $v;
}                ## e.g., round(12.3456,2) -> 12.35

sub ln { return log($_[0]); }

sub npv {
  my $r=shift;
  my $sum=0; my $cnt=0;
  foreach (@_) {
    $sum+= $_/(1.0+$r)**$cnt; ++$cnt;
  }
  return $sum;
}


sub pv {
  my $r=shift;
  my $sum=0; my $cnt=1;
  foreach (@_) {
    $sum+= $_/(1.0+$r)**$cnt; ++$cnt;
  }
  return $sum;
}

sub irr {
  my ($left,$right)= (-1+1e-8,1);
  my $leftpv= pv($left, @_); my $rightpv= pv($right, @_);
  ($leftpv*$rightpv<0) or do { $right= 1e3; $rightpv=pv($right, @_); };
  ($leftpv*$rightpv<0) or do { $right= 1e6; $rightpv=pv($right, @_); };
  ($leftpv*$rightpv<0) or return "NaN";

  my $numiter=1000;
  while ((--$numiter)>0) {
    my $mid= ($left+$right)/2;
    my $midpv= pv($mid, @_);
    (abs($midpv) < 1e-6) and return $mid;
    ($midpv*$leftpv > 0) and do { $left=$mid; $leftpv=$midpv; next; };
    $right=$mid; $rightpv=$midpv;
  }
}

## my @example= (-10,2,2,2);
## print irr( @example ).", ".pv( 0.2, @example )."\n";

## sub isanum { return ($_[0] =~ /^\s*[0-9\.\-]+\s*$/); }
##  sub isaposint { return ($_[0] =~ /^[0-9]+$/); }
## (isaposint($time)) or die "Your Time Limit of '$tm' is not a number.\n";


1;
