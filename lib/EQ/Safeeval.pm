#!/usr/bin/perl -w
package EQ::Safeeval;

use v5.14;
use Mojo::Base 'Mojolicious::Controller';

use strict;
use warnings;
use warnings FATAL => qw{ uninitialized };
use autodie;
use locale;

use Safe;
use HTML::Entities;
use experimental 'switch';    ## 'given' ... construct


################################################################################################################################

my $runstarttime = time();
my $allowhtml    = 1
  ; ## allows quiz designer (instructor) to use html in the questions;  injection danger, of course, but we trust instructors.
my $makenumslooknicer = 1;    # cuts numbers off after 3 digits
my $mathminus =
  '-';  ## if '\&minus;', we will substitute in to make this look nicer on HTML.

my $isweb = (defined($ENV{QUERY})) || (defined($ENV{MOJO_APP}));
my $inhtml = $isweb;    ## change this to 1 if you want to see html output

use Crypt::Simple file => '/etc/eq-passphrase.txt';

sub decryptmsg {
    my $v = decrypt(Encode::decode('UTF-8', $_[0]));
    $v =~ s/&amp;/&/g;
    return $v;
}

sub encryptedhidden {
    return
      "\t<input type=\"hidden\" name=\"$_[0]-$_[1]\" value=\""
      . encrypt(Encode::encode('UTF-8', $_[2])) . "\" />";
}

sub hidden {
    return "\t<input type=\"hidden\" name=\"$_[0]-$_[1]\" value=\""
      . encode_entities($_[2]) . "\" />";
}

################################################################################################################################

=pod

=head1 NAME

  SafeEval.pm --- read all or some questions from a file into an array

=head1 DOCS

  read tutorial.txt for the language

  for debugging, use something like

     perl Safeeval.pm --html ch2.testbank


=head1 Revisions

2012/02/09    included rounding

2012/02/15    added Mojolicious controller, etc.

2012/02/23      cleaned up.  separation of .txt and .html modes

2012/04/15    formatting changes.  passphrase factored to /etc/.

2012/04/16    more formatting and language changes.

=cut

################################################################################################################################
## math functions that I would like the programmable text to
##  know, which are not already predefined in perl
################################################################

use File::Slurp;

use File::Basename qw/dirname/;

my $predefinedfunctions = read_file(dirname(__FILE__) . "/predefined.pm");

################################################################################################################################
### the input to evalonequestion is a one-question hash.
###
### the output is either a corrected hash (with evaluated fields),
### or a single error string.  Note that some of the checking is redundant.
###
### show a sample input and output
################################################################

sub evaloneqstn {

    my %qstn = %{$_[0]};

    (defined($qstn{N})) or return "you have a qstn without a name";
    (($qstn{N})) or return "you have a qstn without a name";

    (defined($qstn{I}))
      or return "no :I: (init string) for $qstn{N} ending on line $. (Keys='"
      . (join ",", keys(%qstn)) . "')\n";
    (defined($qstn{L}))
      or return "no :L: (long answer) for $qstn{N} ending on line $. (Keys='"
      . (join ",", keys(%qstn)) . "')\n";
    (defined($qstn{S}))
      or return "no :S: (short answer) for $qstn{N} ending on line $. (Keys='"
      . (join ",", keys(%qstn)) . "')\n";
    (defined($qstn{Q}))
      or return "no :Q: (qstn) for $qstn{N} ending on line $.  (Keys='"
      . (join ",", keys(%qstn)) . "')\n";

    ($qstn{I} =~ /([\"\|\`])/)
      and return
"your :I: for $qstn{N} ending on line $. contains an illegal string character '$1'.";

    ($qstn{S} =~ /[\|\`]/)
      and return
"your :S: for $qstn{N} ending on line $. contains an illegal character, \| or \`.";
    ($qstn{L} =~ /[\|\`]/)
      and return
"your :L: for $qstn{N} ending on line $. contains an illegal character, \| or \`.";
    ($qstn{Q} =~ /[\|\`]/)
      and return
"your :Q: for $qstn{N} ending on line $. contains an illegal character, \| or \`.";

    (defined($qstn{P}))
      and ($qstn{P} =~ /[\|\`]/)
      and return
"your :Q: for $qstn{P} ending on line $. contains an illegal character, \| or \`.";

    $qstn{I} =~ s/\^/**/g;    ##  perl does not think '^' is exponentiation

    ($qstn{I} =~ /^\{(.*)\}$/)
      and $qstn{I} =
      $1;    ## allow the entire initialization to be surrounded by '{' and '}'
    ($qstn{S} =~ /^\{(.*)\}$/) and $qstn{S} = $1;   ## and the short answer, too

    my $compartment = new Safe;
    {
        no strict;
        $compartment->permit(qw/ :base_math  /);    # ues
        local $SIG{__WARN__} = sub { die $_[0] };
        $compartment->reval("$predefinedfunctions ; $qstn{I}");
        ($@ eq "")
          or return
"Your init :I: evaluation algebraic expression string <div style=\"color:black;font-weight:bold\">$qstn{I}</div> for $qstn{N} ending on line $. failed.  Please fix and try again.";
    }

    use strict;

    my %results = %qstn;                            # establish defaults

    my $supersafeevalfn = sub {
        no warnings
          ;    # avoid complaints that qstn and compartment will not stay shared
        ## we want to evaluate only word-named variables inside other fields

        my $pgm =
            ($_[0] =~ /[S]/) ? 's/(\$[a-zA-Z]\w*)/($1)/gee; $_'
          : ($_[0] =~ /[LQ]/)
          ? 's/\{(\$[a-zA-Z]\w*)(\:\d)*\}/makeroundexpr($1,$2)/gee; $_'
          : die "bad selector $_[0]";

        $_ = $qstn{$_[0]};
        ## requires: :base_core :base_orig :base_loop :still_to_be_decided
        $compartment->deny_only(
            qw/ :base_mem :base_io :base_math :base_thread :filesys_read :sys_db :filesys_open
              :filesys_write :subprocess :ownprocess :others :load :dangerous/
        );    ## now we are more permissive
        my $out = $compartment->reval($pgm);
        use warnings;
        return $out;
    };

    $results{Q} = &$supersafeevalfn('Q');
    ($@ eq "") or die "Qstn Segment :Q(uestion):$.: $@\n";
    $results{L} = &$supersafeevalfn('L');
    ($@ eq "") or die "Qstn Segment :L(ong):$.: $@\n";
    $results{S} = &$supersafeevalfn('S');
    ($@ eq "") or die "Qstn Segment :S(hort):$.: $@\n";

    if (1) {    ## be even nicer on the output
        $results{L} =~ s/\$\-/$mathminus\$/g
          ;     # some extra smarts.  $-15 usually is supposed to mean -$15.
        $results{Q} =~ s/\$\-/$mathminus\$/g;    # same
        if ($mathminus ne "-") {
            $results{L} =~ s/([\d\.]\s*)\-(\s*[\d\.])/$1$mathminus$2/g
              ;                                  # 15-3 usually means 15 -- 3.
            $results{Q} =~ s/([\d\.]\s*)\-(\s*[\d\.])/$1$mathminus$2/g
              ;                                  # 15-3 usually means 15 -- 3.
        }
    }

    return \%results;
}

################################################################################################################################
### note: we break out information from before ::START::, then split up all
### qstns up to ::END::, processing each and every qstn along the way with
### evaloneqstn()
################################################################

sub processquizfile {
    my $anyfilename = shift;

#  ($anyfilename =~ /[^\w\.]/) and die "sorry, but your filename '$anyfilename' contains a non-word character";
    open(my $FIN, "<:encoding(UTF-8)", "$anyfilename")
      or die "cannot open file $anyfilename: $!\n";
    my $metastruct = processquizfhandle($FIN, $anyfilename);
    close($FIN);

    return $metastruct;

    ################
    sub processquizfhandle {
        my $FIN = shift;
        my $filename = shift() || "no-filename";

        my %validkeyfields = (
            NAME         => 2,
            INTRODUCTION => 1,
            PS           => 1,
            COMMENT      => 1,
            EQVERSION    => 2,
            INSTRUCTOR   => 2,
            AREA         => 1,
            LICENSE      => 1,
            CREATED      => 1,
            VERSION      => 1,
            RENDER       => 1,
            COMMENT      => 1,
            SHARING      => 1,
            PAGING       => 1,
            EMAIL        => 1,
            FINISH_PAGE  => 1
        );

        ## default values now
        my $rv = {
            INSTRUCTOR   => "",
            CREATED      => "",
            INTRODUCTION => "",
            NAME         => "",
            AREA         => "",
            LICENSE      => "",
            RENDER       => "all",
            PS           => "",
            EQVERSION    => "",
            VERSION      => "",
            SHARING      => "OK",
            EMAIL        => "",
            FINISH_PAGE  => 'answers+results'
        };

        my %qstn;
        my $count = 1;
        my $inqstn;

        $rv->{randgenerated} = localtime() . " = " . time();

        ################################################################
        local *readlongline = sub {
            (defined(my $line = <$FIN>)) or return undef;
            chomp($line);
            ## read lines until we see a \
            while ($line =~ s/\\\s*$//) { $line .= <$FIN>; chomp($line); }
            $line =~ s/^\s+//;
            $line =~ s/\s+$//;    ## trailing and leading spaces are ignored
            return $_ = $line;
        };

        ## first, read the header. here we break lines with a starting ::
        my $preamble = "";
        while (defined(readlongline())) {

            (/^\#/) and next;             ## comment line;
            (/^::START\::\s*$/) and last; ## ignore everything before the START.

            $preamble .= "$_\n";
        }
        (/^::START\::\s*$/) or die "I did not see the ::START:: command\n";

        my @preamble = split(/\n\:\:/, $preamble);

        foreach my $p (@preamble) {
            if ($p =~ /([\w]+)\:\:(.*)/s) {
                ($1 eq "COMMENT") and next;
                ($validkeyfields{$1}) and $rv->{$1} = $2;
                (!$validkeyfields{$1})
                  and die
                  "Sorry, but header key '$1' is not known. ($preamble)\n";
            }
        }

        my $missingheaderfields = "";
        foreach my $k (keys %validkeyfields) {
            if ($validkeyfields{$k} == 2) {
                ($rv->{$k})
                  or $missingheaderfields .=
"<p>Required Field $k is missing in quiz file.  Please contact instructor.\n";
            }
        }
        ($missingheaderfields) and die "$missingheaderfields";

        ################    ################    ################    ################
        ## now read the questions between the ::START:: and ::END::

        my $validtags =
          "[NQICSLTDMP]";   # E is eliminated in the parse; P will be precision;

        local *readrecord = sub {
            (eof($FIN)) and return undef;
            my %record;

            local $/ = "\n:E:";
            my $content = <$FIN>;
            ($content =~ /^::END::/m) and return (END => 1);

            my @fields = split(/\n\:/, $content);

        #      print STDERR "BASE CONTENT =  '".substr($content,0,70)."'****\n";

            foreach my $f (@fields) {
                if ($f =~ /($validtags)\:(.*)/s) {
                    my $tag     = $1;
                    my $content = $2;
                    (defined($record{$tag}))
                      and die
"$filename:$.: Multiple records with tag '$tag'.\nFirst='$record{$tag}'\nSecond=$content\n";
                    $record{$tag} = $content;

              #	  print STDERR "stored '".substr($content,0,40)."' in '$tag'\n";
                }
                elsif ($f =~ /E\:/) { } ## end of question
                elsif ($f =~ /c\:/) { }                      ## copyright
                elsif ($f =~ /[a-zA-Z]/) {
                    die
"\n\nSorry, but we have weird non-letter tag in field '$f'\n\n";
                }
            }

#      foreach my $r (sort keys %record) { print STDERR "returning $r (".substr($record{$r},0,40).")...\n"; } print STDERR "\n\n";

            return %record;
        };

        my $recordcnt = 0;
        my @allquestions;
        while (1) {
            my %fields = readrecord();
            ($fields{END}) and last;

            ## ok, we have a message or a question.

# sub sanitizehtml { defined($_[0]) or return undef; $_[0] =~ s/\</&lt;/g; $_[0]  =~ s/\>/&gt;/g; return $_[0]; }
# if (!$allowhtml) { $fields{M} = sanitizehtml( $fields{M} ) }

            ++$recordcnt;
            $fields{CNT} = $recordcnt;

            if (defined($fields{M})) {
                push(@allquestions, {MSG => $fields{M}});
                next;
            }

            (defined($fields{N})) or $fields{N} = "(unnamed Q$recordcnt)";
            (defined($fields{S})) or $fields{S} = '$ANS';

            ## now we have a question.  check various validities
            ## (defined($fields{N})) or die "$filename:$.: Need a name field :N:.\n";
            (defined($fields{Q}))
              or die "$filename:$.: Need a question field :Q:.\n";
            (defined($fields{I}))
              or die "$filename:$.: Need an initialization field :I:.\n";
            (defined($fields{S}))
              or die "$filename:$.: Need a short answer field :S:.\n";
            (defined($fields{L}))
              or die "$filename:$.: Need a long answer field :L:.\n";

     # :C: (choices), :T: (time), :D: (difficulty), :P: (precision) are optional

    # if (!$allowhtml) { $fields{[SLTDCc]} = sanitizehtml( $fields{[SLTDCc]} ) }

            ($fields{I} =~ /[\'\"\|\`]/)
              and die "No strings in init allowed on line $.\n";

#      ($fields{I} =~ /[\{\}]/) and die "No block statement in init allowed on line $.\n";
            $fields{I} = "\$ANS=undef ; $fields{I}";

            (($fields{S} =~ /^\s*\$\w+\s*$/) || ($fields{S} =~ /^\s*\d+\s*$/))
              or die
"$filename:$.: Short answer '$fields{S}' should not have algebra in it.  It should be a number or a variable.";

            if (defined($fields{C})) {
                ($fields{C} =~ /\|/)
                  or die
"If you have multiple choice answers, you must have at least two of them (|-separated):<br />'$fields{C}'\n";
            }

            foreach my $embeddedfield (qw(L Q)) {
                my $content = $fields{$embeddedfield};
                if ($makenumslooknicer && ($mathminus ne "-")) {
                    $fields{$embeddedfield} =~ s/\-(\d+\.\d)/\&minus;$1/g;
                }
                while ($content =~ /\{\$([^\}]+)\}/g) {
                    my $varname = $1;
                    (
                             ($varname =~ /^[a-zA-Z_]\w*$/)
                          or ($varname =~ /^[a-zA-Z_]\w*:\d+$/)
                      )
                      or die
"$filename:$.: In :$embeddedfield: paren expression {.}, did you want a variable name "
                      . "[which should not contain anything except alphanumerics], but it has $varname.\n"
                      . "the full content='\"$content\"'\n";
                }
            }

            $fields{Q_} = "$fields{Q}";
            $fields{S_} = "$fields{S}";
            $fields{L_} = "$fields{L}";

            my $v = evaloneqstn(\%fields);
            (ref($v) ne "HASH") and do {
                (my $shortfilename = $filename) =~ s/.*\///g;
                die "<p>$shortfilename:$.: Sorry, but your qstn N='"
                  . $fields{N} . "' "
                  . "ending on line $. died on me with the following error: <pre><b>\n'$v'\n</b></pre>\n";
            };

            push(@allquestions, $v);
        }

        my %existingquestionnames;
        foreach my $q (@allquestions) {
            my $nm = $q->{N};
            (defined($nm)) or next;
            (defined($existingquestionnames{$nm}))
              and die
"Sorry, but your questions must have unique names.  Question Name '$nm' appears twice.\n";
            $existingquestionnames{$nm} = 1;
        }

        $rv->{ALLQUESTIONS} = \@allquestions;

        return $rv;
    }
}

################################################################################################################################
sub displayallquestionstohtml {

    my ($metastructure, $uid, $iid, $submit_to) = @_;
    $metastructure->{uid} = $uid || "0";
    $metastructure->{iid} = $iid || "0";

    ($metastructure->{whichqstns}) or $metastructure->{whichqstns} = "all";

    my @ALLQUESTIONS = @{$metastructure->{ALLQUESTIONS}};

    given ($metastructure->{whichqstns}) {
        when ("random") {
            use List::Util qw(shuffle);
            @ALLQUESTIONS = shuffle(@ALLQUESTIONS);
            my $num = (6 || 6) - 1;   ## the default number of random qstns is 5
            $#ALLQUESTIONS = $num;
            $metastructure->{ALLQUESTIONS} = \@ALLQUESTIONS;
        }
        when ("all") {
            ## we already have everything in @ALLQUESTIONS
        }
        when ("individualqstns") {
            ## not yet implemented
        }
        default {
            ## not yet implemented
        }
    }

    sub wrapwithinnavtabular {
        return $_[0];    ## not currently enabled
        return
"\n<table>\n<tr><td><input type=\"button\" onclick=\"showQuestion(-1,0)\" value=\"&lt;\"></td>"
          . "<td>$_[0]</td>"
          . "<td><input type=\"button\" onclick=\"showQuestion(1,0)\" value=\"&gt;\"></td>\n</table>\n";
    }

    my $rv = "<script type=\"text/javascript\"\">
    function validatenum(evt) {
        var theEvent = evt || window.event;
        var key = theEvent.keyCode || theEvent.which;
        key = String.fromCharCode( key );
        var regex = /[0-9]\-|\./;
        if( !regex.test(key) ) {
        theEvent.returnValue = false;
        if(theEvent.preventDefault) theEvent.preventDefault();
        }
    }
    </script>\n\n";

    ## erase previous

    $rv =
"<div style=\"color:black;padding-top:1ex;padding-bottom:1ex\">Quiz Area: $metastructure->{AREA}</div>\n\n";

    my $ignoreme = qq(
        <nav><table class="navbar">
    <tr>
    <td> <span id="pageDisplay"></span> </td>
    <td> <input type="button" onclick="showQuestion(0,1)" value="|&lt;&lt;"> </td>
    <td> <input type="button" onclick="showQuestion(-1,0)" value="&lt;"> </td>
    <td> <span id="gotoPage"></span> </td>
    <td> <input type="button" onclick="showQuestion(+1,0)" value="&gt;"> </td>
    <td> <input type="button" onclick="showQuestion(0,100)" value="&gt;&gt;|"> </td>
    <td> <input type="checkbox" class="singleFull" onclick="displayInfo()"> View All </td>
    </tr>
    </table></nav>\n);

    my $quiznavbar = qq(

<!-- Navigation -->

<nav><table class="navbar" style="background-color:#0076BA;width:100%" border="1">
 <tbody>
 <tr>
       <td style="width:10px"> <input type="button" onclick="showQuestion(0,1)" value="|<<"> </td>
       <td style="width:10px"> <input type="button" onclick="showQuestion(-1,0)" value="<"> </td>
       <td style="text-align:center">
     <select class='selectPage' onchange="displayPage(this.value)">
NAVBAROPTIONVALUEPAGESELECT
     </select>
     <input type="checkbox" class="singleFull" onclick="displayAllInfo(this)"><span style="color:white">View All Pages</span>
       </td>
       <td style="width:10px"> <input type="button" onclick="showQuestion(+1,0)" value=">"> </td>
       <td style="width:10px"> <input type="button" onclick="showQuestion(0,100)" value=">>|"> </td>
 </tr>
 </tbody>
</table></nav>

<!-- END Navigation -->

);

    my $subpagecount = 0;
    my @subpagenames;

    $rv .= $quiznavbar;

    if (   (defined($metastructure->{INTRODUCTION}))
        && ($metastructure->{INTRODUCTION}) =~ /[a-zA-Z]/)
    {
        $rv .=
          "\n\n<div class=\"subpage\">\n"
          . wrapwithinnavtabular(
"\n<div class=\"introduction\">\n$metastructure->{INTRODUCTION}\n</div><!--introduction-->\n"
          ) . "</div><!--subpage-->\n\n\n";
        ++$subpagecount;
        push(@subpagenames, "INTRODUCTION");
    }

    $rv .= qq(<form method="post" class="quizform" action="$submit_to">\n);

    my $is_allow_partial = 0;
    if (   (defined($metastructure->{RENDER}))
        && ($metastructure->{RENDER}) =~ /ALLOWPARTIAL/)
    {
        $is_allow_partial = 1;
    }
    $rv .=
      qq(<input type="hidden" name="allowpartial" value="$is_allow_partial">);

    my @setofqs;
    my $qcnt = 0;
    foreach my $q (@ALLQUESTIONS) {

        if ($q->{MSG}) {
            $rv .=
              "\n\n<div class=\"subpage\">\n"
              . wrapwithinnavtabular(
                "\n<div class=\"qmsg\"> $q->{MSG} </div><!--qmsg-->\n")
              . "</div><!--subpage-->\n\n\n";
            ++$subpagecount;
            my $shortmsg = ($q->{MSG}) ? (": " . substr($q->{MSG}, 0, 20)) : "";
            $shortmsg =~ s/\<.*?\>//g;
            push(@subpagenames, "NOTE$shortmsg");
            next;
        }

        ++$qcnt;
        my $qL = encryptedhidden("q-L", $qcnt, $q->{L});
        my $qS = encryptedhidden("q-S", $qcnt, $q->{S});
        my $qP =
          (defined($q->{P})) ? encryptedhidden("q-P", $qcnt, $q->{P}) : "";
        my $qQ = hidden("q-Q", $qcnt, $q->{Q});
        my $qN = hidden("q-N", $qcnt, $q->{N});

        push(@setofqs, $q->{N});

        my $onequestion = "";

        (defined($q->{D}))
          and $onequestion .=
          qq(\t<p class="difficultyhint"> Difficulty: $q->{D}.&nbsp;</p>  \n);
        (defined($q->{T}))
          and $onequestion .=
          qq(\t<p class="timehint"> Suggested Time: $q->{T} min.&nbsp;</p>  \n);

        $onequestion .=
            "<p class=\"qstnnum\">[ Q$qcnt: <span class=\"qname\">"
          . $q->{N}
          . "</span> ] </p>\n";

        $onequestion .= "\n<p class=\"qstn\"> $q->{Q} </p>\n";

        if (defined($q->{C})) {
            $onequestion .=
              qq(\t<p class=\"inputanswerlist\"> Your Answer:\n\t<ol>\n);
            my $cnt = 1;
            foreach my $choice (split(/\|/, $q->{C})) {
                $onequestion .=
qq(\t\t<li class=\"mchoice\"> <input class=\"studentanswerfieldm\" type=\"radio\" value=\"$cnt\" name=\"q-stdnt-$qcnt\" /> $choice <br /></li>\n);
                ++$cnt;
            }
            $onequestion .= "</ol>\n";
        }
        else {
            ## the most common answer field, just plain
            ## fails: onblur='validatenum(event)'
            $onequestion .=
qq(\t<p class="inputanswer"> Your Answer: <input class="studentanswerfield" type="number" step="any" size="8" name="q-stdnt-$qcnt" /><br />\n<span style="font-size:smaller">(enter only numbers [digits, minus, period])</span></p>\n);
        }

        $onequestion .= qq(\n$qN\n$qL\n$qS\n$qP\n$qQ\n);
        $onequestion =
"<div class=\"qstn\" id=\"$qcnt\">\n$onequestion\n</div><!--qstn-->\n\n";

        $rv .=
            "\n\n<div class=\"subpage\">\n"
          . wrapwithinnavtabular($onequestion)
          . "</div><!--subpage-->\n\n\n";
        ++$subpagecount;
        my $shortmsg = ($qcnt) ? ("" . substr("$qcnt: $q->{N}", 0, 20)) : "";
        $shortmsg =~ s/\<.*?\>//g;
        push(@subpagenames, "Q$shortmsg");
    }

    $rv .= "\n\n";
    $rv .= encryptedhidden("q-A", "*", join(",", @setofqs)) . "\n";
    my $fingerprint =
"Your uid = $metastructure->{uid} | Generated = $metastructure->{randgenerated}";
    ## | Instructor = $metastructure->{iid}\n";
    $rv .= encryptedhidden("key", "*", $fingerprint) . "\n";

    if ((defined($metastructure->{PS})) && ($metastructure->{PS}) =~ /[a-zA-Z]/)
    {
        $rv .=
"\n\n<div class=\"subpage\">\n\t<div class=\"PS\">\n$metastructure->{PS}\n</div><!--PS-->\n</div><!--subpage-->\n\n";
        push(@subpagenames, "POSTSCRIPT");
        ++$subpagecount;
    }

    my $ignore = qq(<nav><table class="navbar">
    <tr>
    <td> <input type="button" onclick="showQuestion(-1,0)" value="&lt;"> </td>
    <td> <input type="button" onclick="showQuestion(+1,0)" value="&gt;"> </td>
    </tr>
    </table></nav>\n);

    $rv .= $quiznavbar;

    $rv .= qq(\n
          <div class="quizsubmitbutton">
             <input type="submit" class="quizsubmitbutton" name="submit" value="Submit and Grade my Answers" />\n</div><!--quizsubmitbutton-->\n);

    $rv .= qq(\n</form>\n);

    $rv .= "\n\n<hr />\n\n<p style=\"font-size:x-small\">$fingerprint</p>\n";

    my $enumerated = "";
    foreach my $i (1 .. $subpagecount) {
        $enumerated .=
            "\t<option value=\"$i\"> Choose page $i of $subpagecount :   "
          . shift(@subpagenames)
          . " </option>\n";
    }

    $rv =~ s/NAVBAROPTIONVALUEPAGESELECT/$enumerated/g;

    return $rv;
}

################################################################################################################################
sub displayallquestionstotxt {
    my $metastructrv = shift;

    my $rv = "";
    foreach my $k (keys %{$metastructrv}) {
        ($k eq "ALLQUESTIONS") and next;
        $rv .= "META ( $k ): '" . $metastructrv->{$k} . "'\n";
    }

    my @listofqstns = @{$metastructrv->{ALLQUESTIONS}};
    foreach my $l (@listofqstns) {
        my %oneqstn = %$l;
        if (defined($oneqstn{MSG})) {
            $rv .= "\n**** MSG: $oneqstn{MSG}\n";
            next;
        }
        my $difficulty =
          ($oneqstn{D}) ? ". difficulty level:'$oneqstn{D}'" : "";
        $rv .=
"\n\nQstn $oneqstn{CNT}: $oneqstn{N} ($oneqstn{T} minutes$difficulty)\n\n";
        foreach my $q (qw( Q L S )) {
            $oneqstn{$q} =~ s/(<br[^\>]*>)/$1\n/g;
            $rv .= "$q => $oneqstn{$q}\n";

            # $rv .= qq(\n\nQstn '$qcnt' (Name $q->{N}):
            #   $q->{Q}\n\nAnswer:  $q->{S}
            #   $q->{L}\n\n---------------- );
        }
    }
    return $rv;
}

################################################################################################################################
## rendering = first process, then paint
################################################################
sub processandrenderquiz {
    my ($uid, $iid, $tid, $testbank_fileondisk, $submit_to) = @_;

    my $rv = "";

    my $metastructrv = eval { processquizfile($testbank_fileondisk); };

    if ($@) {
        $rv =
"Internal Quiz Error.  Please report it to your instructor:\n<br />$@\n";
        return $rv;
    }

    if ($inhtml == (-99)) {
        ## print $SOUT "\n<h1>Quiz</h1>\n\n";
        $rv = <<"END";
<html>
<head>
<title>EQuiz.Me Quiz</title>

<script type="text/javascript" src="/static/js-pager.js"></script>

<style type="text/css">
.subpage {  display:none;  border:1px solid red;  height:25%;  width:100%; }
</style>

</head>

END
    }
    if ($inhtml) {
        $rv = displayallquestionstohtml(
            $metastructrv, $uid || 0,
            "$iid : $tid : $testbank_fileondisk",
            $submit_to || '??'
        );
    }
    else {
        $rv = displayallquestionstotxt($metastructrv);
    }

    (!$isweb)
      and print STDERR "Processed "
      . @{$metastructrv->{ALLQUESTIONS}}
      . " questions for quiz $metastructrv->{NAME}";
    return $rv;
}

################################################################################################################################

if ($0 =~ /val\.pm$/i) {
    (defined($ARGV[0]))
      or die "In Command Line Use, you need to give a filename\n";

    ($ARGV[0] eq "--html") and do { $inhtml = 1; shift(@ARGV); };
    (-r ($ARGV[0])) or die "File $ARGV[0] is not available or readable\n";

    print processandrenderquiz(1, 1, 1, $ARGV[0]);

    exit 0;
}

################################################################################################################################
## these are not really part of this module, but for Mojolicious
## interface testing only
################################################################

sub selectquiz {
    my $self = shift;

    return $self->render(text =>
qq(run <a href="/givequiz?iid=userA&tid=ch2.testbank">/givequiz?iid=userA&tid=ch2.testbank</a>)
    );
}

################################################################
sub givequiz {
    my $self = shift;

    my $iid = $self->req->param('iid');
    ($iid) or die "Sorry, we need an instructor id to identify a test\n";
    ($iid =~ /^[a-zA-Z0-9]+$/)
      or die "Sorry, instructor id $iid is not valid\n";
    my $tid = $self->req->param('tid');
    ($tid) or die "Sorry, but we need a test id for instructor $iid\n";

    my $testbank_fileondisk = "/var/tmp/FM/$iid/$tid";
    (-e -r $testbank_fileondisk)
      or die
      "Sorry, but $iid/$tid combo ($testbank_fileondisk) does not exist!\n";

    my $htmlcontent = processandrenderquiz($self->req->param('uid'),
        $iid, $tid, $testbank_fileondisk);

    return $self->render(text => $htmlcontent);
}

1;
