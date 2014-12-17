package EQ::Plugin::FileManager::Controller;

use v5.14;
use Mojo::Base 'Mojolicious::Controller';

use strict;
use warnings;
use warnings FATAL => qw{ uninitialized };
use autodie;

use Try::Tiny;
use EQ::Plugin::FileManager::Model::Bucket;
use File::Basename qw/fileparse/;
use File::Slurp;
use Digest::MD5 qw/md5_hex/;


my $config;  # the rootdir and limit

my (@extrabuttons, @extrabuttonsurl, @extrasubs, @extrauseon, @extracss);  # extra functions
################################################################################################################################

## WithFile is called by register of hooks

sub WithFile {
    my ($name, $sub, $useon, $morecss) = @_ ;
    push @extrabuttons, $name;
    push @extrasubs, $sub;
    push @extrauseon, ($useon||'.*');
    push @extracss, $morecss;
    return $name;
}

################################################################################################################################
#sub Load {
#    (UNIVERSAL::isa( $_[0], "HASH" )) or
#    die "First argument to Load must be a descriptive hash of options.\n";
#    $config = $_[0];
#
#    (defined($config->{rootdir})) or die "You need to set up the rootdir.";
#    (-e "$config->{rootdir}") or die "Your rootdir $config->{rootdir} does not exist.";
#    (-r "$config->{rootdir}") or die "Your rootdir $config->{rootdir} is not readable.";
#    (-r "$config->{rootdir}") or die "Your rootdir $config->{rootdir} is not writable.";
#
#    $backend = EQ::Plugin::FileManager::Model::Bucket->build(%$config);
#};


################################################################################################################################
### the end user code would usually be the part that would be embedded
################################################################################################################################

sub fm {
    my $self = shift;

    (defined(my $uid = $self->session('uid')))
      or return $self->render( text => 'You have no home.  Go away.');

    my $exclude_re = $self->fm_config->{hide};

    my $rv = "<table class='filemanager'>
    <thead><tr> <th>View File</th> <th>Size</th> <th>Date</th> <th>Download</th> <th>Edit</th> <th>Designer</th> <th>Rename</th> <th>Toggle Quiz</th> <th>Delete</th>"
      . ((@extrabuttons) ? "<th>Extras</th>" : "") . "</tr></thead>\n";

#  ((@extrabuttons) ? "<th colspan=".(scalar @extrabuttons).">Extras</th>":"")."</tr></thead>\n";

    my @files = $self->backend->list_files($uid, exclude => $self->fm_config->{hide});

    foreach (@files) {
        s/^.*\///; ## kill all directory paths in the filename until we get to the basename

        my $css = "";
        foreach my $i (0 .. $#extrabuttons) {
            if ($_ =~ /$extrauseon[$i]/) {
                $css = "\t\t";
                if (defined($extracss[$i])) {
                    $css = " style=\"$extracss[$i]\"";
                    last;
                }    ## picks up the first one.  we hope its the right one!
            }
        }

        $rv .= "\n\n\t<tr>";

        ## arg 0 = function ; arg 1 = filename ;  arg 2 = further arg to extra if needed;  arg 3 = css
        sub button {
            my $css = $_[3] || "";
            return qq(<form action="/fm/$_[0]">)
              . (
                (defined($_[2]))
                ? qq(<input type="hidden" name="ex" value="$_[2]" />)
                : ""
              )
              . qq(<input type="hidden" name="f" value="$_" />)
              . qq(<input $css type="submit" value="$_[1]" /></form>);
        }
        sub tdbutton { return "\n\t\t" . '<td>' . button(@_) . '</td>'; }
        sub tdempty { return "\n\t\t" . '<td></td>'; }

        $rv .= qq(\n\t\t<td $css><a href="/fm/viewfile?f=$_"> $_ </a></td> );
        $rv .= "\n\t\t<td style=\"text-align:right\">"
          . $self->backend->get_file_size($uid, $_) . "</td>";
        $rv
          .= "\n\t\t<td>"
          . $self->backend->get_file_mtime($uid, $_) . " / "
          . localtime($self->backend->get_file_mtime($uid, $_)) . "</td>";
        $rv .= tdbutton("downloadfile", "Download");
        $rv .= /-(?:deleted|previous)$/ ? tdempty() : tdbutton("editfile",     "Edit");
        if (/\.(quiz|testbank)$/) {
            $rv .= qq(\n\t\t<td><form action=") . $self->url_for('instructors_quiz_designer', user_id => $uid) . qq("><input type="hidden" name="f" value="$_" /><button type="submit">Designer</button></form></td> );
        }
        else {
            $rv .= qq(\n\t\t<td></td>);
        }
        $rv .= tdbutton("renamefile",   "Rename");
        if (/\.(quiz|testbank)$/) {
            my $what = $1 eq 'quiz' ? 'Quiz' : 'Testbank';
            $rv .= tdbutton("togglequiz",   "Toggle&nbsp;$what");
        }
        else {
            $rv .= qq(\n\t\t<td></td>);
        }
        $rv .= tdbutton("deletefile",   "Delete");

        foreach my $i (0 .. $#extrabuttons) {
            $rv .=
              ($_ =~ /$extrauseon[$i]/)
              ? tdbutton("extra", $extrabuttons[$i], $i, $css)
              : "";
        }
        $rv .= "</tr>\n";
    }

    $rv .= "\n</table>\n\n";

    $rv
      .= qq(\t<table><tr style="background-color:khaki"> <td colspan=")
      . (7 + scalar @extrabuttons)
      . qq("> <div id="dropbox"><form method="post" action="/fm/uploadfile" enctype ="multipart/form-data">)
      . qq( Or <input type="file" name="f" />  and then <input id="upload_button" type="submit" value="upload selected file" />. </form> </div></tr></table>\n);

    ($self->req->param('msg'))
      and $rv
      .= "<hr /> <div class=\"msg\">Last Message: "
      . $self->req->param('msg')
      . "</div>\n";

    return $self->_render($rv, "Files");    # Home of '$uid'
}

sub extra {
    my $self = shift;

    my $uid      = $self->session('uid');
    my $filename = $self->param('f');

    try {
        my $fni = $self->req->param('ex');
        my $subfn = $extrasubs[$fni];

        die 'Unknown extra' unless $subfn && ref $subfn eq 'CODE';

        my $contents = $self->backend->slurp_file($uid, $filename);
        my $file = $self->backend->write_temp_file($contents, $filename);

        open my $fh, '<', $file or die $!;

        my $result = $subfn->($self, $file, $fh);

        return $self->_render($result, $filename);
    }
    catch {
        return $self->render_error($_);
    };
}

sub downloadfile {
    my $self = shift;

    my $uid      = $self->session('uid');
    my $filename = $self->param('f');

    try {
        my $contents = $self->backend->slurp_file($uid, $filename);
        my $fileondisk = $self->backend->write_temp_file($contents);

        my $headers = Mojo::Headers->new();
        $headers->add('Content-Type','application/x-download;name=' . $filename);
        $headers->add('Content-Disposition','attachment;filename=' . $filename);
        $self->res->content->headers($headers);

        # Stream content directly from file
        $self->res->content->asset(Mojo::Asset::File->new(path => $fileondisk));
        return $self->rendered(200);
    }
    catch {
        return $self->render_error($_);
    };
}

sub viewfile {
    my $self = shift;

    my $uid      = $self->session('uid');
    my $filename = $self->param('f');

    try {
        my $contents = $self->backend->slurp_file($uid, $filename);

        $contents = $self->backend->htmlify($contents);

        return $self->_render($contents, "Viewfile $filename");
    }
    catch {
        return $self->render_error($_);
    };
}

sub editfile {
    my $self = shift;

    my $uid      = $self->session('uid');
    my $filename = $self->param('f');

    try {
        my $contents = $self->backend->slurp_file($uid, $filename);

        $contents = _editfile($contents, $filename);

        return $self->_render($contents, "Edit $filename");
    }
    catch {
        return $self->render_error($_);
    };
}

sub submitedit {
    my $self = shift;

    my $uid      = $self->session('uid');
    my $filename = $self->param('f');

    try {
        my $content = $self->req->body_params->param('content');

        $self->_check_content($content);

        my $previous_content = $self->backend->slurp_file($uid, $filename);
        $self->backend->overwrite_file($uid, "$filename-previous", $previous_content);

        $self->backend->overwrite_file($uid, $filename, $content);

        return $self->redirect_to("/fm?msg=just submitted edits of $filename");
    }
    catch {
        my $e = $_;

        $e =~ s{at .* line \d+.*}{};

        $self->flash(error => $e);
        return $self->redirect_to("/fm");
    };
};

sub renamefile {
    my $self = shift;

    my $uid      = $self->session('uid');
    my $filename = $self->param('f');

    try {
        $self->backend->check_file($uid, $filename);
    }
    catch {
        return $self->render_error($_);
    };

    my $contents = "<table>
<tr> <th> From </th> <th> To </th> </tr>
<tr> <td> $filename </td> <td> ".inputfieldfm('submitrename', qq(<input type="hidden" name="old" value="$filename" />))."</td> </tr> </table>
<span style=\"font-size:x-small\">Warning: Existing destination files may be (silently) overwritten</span>\n
";

    return $self->_render($contents, "Renaming file $filename");
};

sub submitrename {
    my $self = shift;

    my $uid      = $self->session('uid');
    my $from = $self->param('old');
    my $dest = $self->param('v');

    try {
        $self->backend->rename_file($uid, $from, $dest);

        return $self->redirect_to("/fm?msg=just renamed $from to $dest" );
    }
    catch {
        return $self->render_error($_);
    };
};

sub togglequiz {
    my $self = shift;

    my $uid  = $self->session('uid');
    my $filename = $self->param('f');

    try {
        $self->backend->check_file($uid, $filename);

        if ($filename =~ m/^(.*)\.(.*?)$/) {
            my ($name, $type) = ($1, $2);

            my $new_filename;
            if ($type eq 'quiz') {
                $new_filename = "$name.testbank";
            }
            elsif ($type eq 'testbank') {
                $new_filename = "$name.quiz";
            }
            else {
                die 'Unknown file extension';
            }

            $self->backend->rename_file($uid, $filename, $new_filename);

            return $self->redirect_to( "/fm?msg=quiz toggled" );
        }
        else {
            die 'Unknown file type';
        }
    }
    catch {
        return $self->render_error($_);
    };
};

sub deletefile {
    my $self = shift;

    my $uid      = $self->session('uid');
    my $filename = $self->param('f');

    try {
        if ($filename =~ m/-(?:deleted|previous)$/) {
            $self->backend->delete_file($uid, $filename);
        }
        else {
            $self->backend->rename_file($uid, $filename, "$filename-deleted");
        }

        return $self->redirect_to( "/fm?msg=just completed deleting $filename" );
    }
    catch {
        return $self->render_error($_);
    };
};

sub uploadfile {
    my $self = shift;

    my $uid    = $self->session('uid');
    my $upload = $self->param('f');

    my $MAXUPLOADSIZE = 64 * 1024;

    try {
        my $filename = $upload->filename;

        die "Upload failed. Your file is larger than allowed."
          if $upload->size() > $MAXUPLOADSIZE;

        my $content = $upload->slurp;

        $self->_check_content($content);

        $self->backend->write_file($uid, $filename, $content);

        $self->redirect_to("/fm?msg=just returned from uploading $filename");
    }
    catch {
        return $self->render_error($_);
    };
}

sub submitfile {
    my $self = shift;

    my $uid      = $self->session('uid');
    my $content  = $self->param('content');
    my $filename = $self->param('f');

    return $self->redirect_error( 'FileName required',
        'instructors_quiz_designer', user_id => $uid )
      unless $filename;
    return $self->render_error('Content required') unless $content;

    try {
        $self->_check_content($content);

        $self->backend->write_file($uid, $filename, $content);

        $self->redirect_to("/fm?msg=just returned from submitting $filename");
    }
    catch {
        return $self->redirect_error($_, "/fm?msg=$_");
    };
}

sub inputfieldfm {
    return qq(<form action="/fm/$_[0]" method="get"> <input name="v" /> ).
    (defined($_[1]) ? $_[1] : "").
    qq(<input type="submit" value="Submit" /> </form>\n);
}

sub inputfieldsu {
    return qq(<form action="/su/$_[0]" method="get"> <input name="v" /> ).
    (defined($_[1]) ? $_[1] : "").
    qq(<input type="submit" value="Submit" /> </form>\n);
}

sub _render {
    my ( $self, $content, $pagename ) = ( $_[0], $_[1], $_[2] || "filemanager.pl");

    $self->render(
       template => 'fm_wrapper',
       fm_html  => $content,
       layout   => $self->fm_config->{layout},
       title    => $pagename,
    );
}

sub render_error {
    my $self = shift;
    my $message = shift;

    $message =~ s{at .* line \d+.*}{};

    $self->flash(error => $message);
    $self->render(  'fm_error',  error_message => $message, layout => $self->fm_config->{layout} );
}

sub redirect_error {
    my $self = shift;
    my $message = shift;

    $message =~ s{at .* line \d+.*}{};

    $self->flash(error => $message);
    $self->redirect_to(@_);
}

sub _editfile {
    my ($filecontents, $filename) = @_;

    ## count rows and columns
    my ($rows, $cols)= (0,60);
    my @rows=split(/\n/, $filecontents);
    foreach (@rows) { (length($_)>$cols) and $cols= length($_); }
    $rows= $#rows+3;

    ## ok, lets finish htmlizing it
    $filecontents =~ s/\n>/\<br \/>/g;

    my $sizestring= "\n<p>Real File: $rows Rows. $cols Cols. ";
    ($cols >= 120) and $cols=120; ($cols <= 60) and $cols=60;
    ($rows >= 200) and $rows=200; ($rows <= 5) and $rows=5;
    $sizestring .= " Displayed Window: $rows Rows. $cols Cols.</p>";

    return <<END;

    $sizestring

    <form action="/fm/submitedit" method="post">
    <p><input type="submit" value="Submit Edits" /></p>

    <textarea rows="$rows" cols="$cols" name="content">$filecontents</textarea>

    <p><input type="hidden" name="f" value="$filename" />
    <input type="submit" value="Submit Edits" /></p>
    </form>

END
}

sub _check_content {
    my $self = shift;
    my ($content) = @_;

    my @tags = qw(input button form);
    my $re = '</?(?:' . join('|', @tags) . ')>';

    if ($content =~ m/$re/ms) {
        die "Please, do not use HTML form tags. This is forbidden";
    }

    return 1;
}

#our $_manglefn; ## undef.  if set to a function, will be called to translate;
#
#################################################################
#sub _dirondisk {
#    my $uid = shift;
#    my $optionalfilename = shift;
#    my $dirondisk = resolvehomedir($uid);
#    (-e $dirondisk) or die "Home User directory '$dirondisk' for user '$uid' does not exist";
#    (-r $dirondisk) or die "Home User directory '$dirondisk' for user '$uid' is not readable";
#    ## (-w $dirondisk) or do { $@= "User directory for $uid is not writeable"; return undef; };
#
#    ## check for optionalfilename validity?
#
#    (defined($optionalfilename)) and $dirondisk .= "/$optionalfilename";
#    return $dirondisk;
#}
#
#sub resolvehomedir {
#    my $uid = shift;
#    (defined($uid)) or die "You need a user id";
#    $uid =~s/^\/*(.*?)\/*/$1/g;
#    (_isvalidname($uid)) or die "Your user id '$uid' is invalid";
#    my $homedir= (defined($_manglefn)) ? $_manglefn->($uid) : md5_hex($uid);
#    return "$config->{rootdir}/$homedir";
#}
#
#sub _isvalidname {
#    return($_[0] =~ m/^[a-zA-Z0-9][a-zA-Z0-9_\@\-.+]*[a-zA-Z0-9]$/i );
#}
#
#
#################################################################
#sub _listofusers { return map { s/$config->{rootdir}\///;"$_" } glob("$config->{rootdir}/*/"); }
#
#
#################
#
#################################################################################################################################
#################################################################################################################################
#################################################################################################################################
#################################################################################################################################
#
#sub selectmode {
#    my $self=shift;
#    return $self->render( text => body( qq(<ul> <li> <a href="/su">super user</a> <li> <a href="/fm?msg=fromroot">current user</a> </ul>), "Select Mode" ) );
#}
#
#
#################################################################################################################################
#### the super user code, which you may want to skip
#################################################################################################################################
#
#sub sufm {
#    my $self = shift;
#
#    my @allusers = _listofusers();
#
#    my $youare = $self->session( 'uid' ) || "unknown user";
#
#    (my $makeuser = inputfieldsu('makeuser')) =~ s/fm\//su\//;  ## usually, requests go to /fm/makeuser, but this one goes to /su/makeuser
#    (my $setuser = inputfieldsu('setuser')) =~ s/fm\//su\//;
#
#    my $rv= <<END;
#    <p>Choose from the following options:</p>
#    <ul>
#    <li> List of Existing Accounts: @allusers</li>
#    <li> Create a single new user account $makeuser </li>
#    <li> (<a href="/su/cheatsetup">Cheat</a> and create some users with some files for quick illustration.) </li>
#    <li> Set user: $setuser </li>
#    </ul>
#    You are currently '<b>$youare</b>'.  If you have a home, go to your <a href="/fm?msg=fromroot">home</a> first.
#END
#    $self->render(text => body($rv, "Administrator Home Page"));
#}
#
#
#################################################################################################################################
#
#sub sucheatsetup {
#    my $self=shift;
#    sucreateuser($self, "userA");
#    sucreateuser($self, "userB");
#    sucreateuser($self, "userC");
#
#    $self->redirect_to( "/su?msg=completed cheat setup" );
#}
#
#################
#
#sub sumakeuser {
#    my $self=shift;
#    my $uid= $self->req->param('v') or return $self->render_error( 'You have given me no user.');
#    sucreateuser($self, "$uid") or return $self->render_error( 'I could not create user $uid: $@.');
#    $self->redirect_to( "/su?msg=just completed makeuser $uid" );
#}
#
#################
#
#sub sucreateuser {
#    my $self= shift();
#    my $uid= shift();
#    (my $dirondisk = resolvehomedir( $uid ))
#    or return $self->render_error( qq(Resolving Problem: $@.));
#    mkdir "$dirondisk"  or return $self->render_error( qq(Cannot create user dir for '$uid'.));
#    my $FOUT;
#    open($FOUT, ">", "$dirondisk/_USER=$uid"); close($FOUT);  ## this is not changeable or usable
#
#    open($FOUT, ">", "$dirondisk/samplefile.txt");
#    print $FOUT "$uid home directory created for $uid on ".localtime().".\n\nYou can edit or delete this file at will.\n";
#    close($FOUT);
#
#    open($FOUT, ">", "$dirondisk/samplefile.pl");
#    print $FOUT "!#/usr/bin/perl -w;\nuse strict;\n";
#    close($FOUT);
#
#    return "ok";
#}
#
#
#################################################################################################################################
#sub susetuser {
#    my $self= shift;
#    my $uid= $self->req->param('v') or return $self->render_error( 'You have given me no user.');
#
#    $self->session( 'uid' => $uid );  ## this actually sets it!!
#
#    (defined(_dirondisk($uid))) or do {
#    $self->session( 'uid' => 0 );
#    return $self->render_error( "Sorry, but you have no home directory, which is an error: $@");
#    };
#
#    ## return $self->render(text => "You have set: uhomedir to $user  and uhomedirptr to $uhomedirptr");
#    $self->redirect_to( "/su?msg=just completed set user $uid" );
#}

1;

__DATA__

@@ error.html.ep
<html>
  <head>
    <meta http-equiv="Content-Type" content="text/html;charset=UTF-8" >
    <title>Error <%= $message %></title>
  </head>
  <body style="background-color:orange;padding-top:5em">
  <h1 style="font-size:large;text-align:center"><%= $message %></h1>
  </body>
</html>


@@ exception.development.html.ep

<html>
  <head>
    <meta http-equiv="Content-Type" content="text/html;charset=UTF-8" >
    <title>File Manager Error <%= $exception->message %> </title>
  </head>

  <body style="background-color:orange;padding-top:5em">
  <h1 style="font-size:large;text-align:center"> <%= $exception->message %></h1>
  </body>
</html>

