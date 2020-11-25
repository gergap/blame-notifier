#!/usr/bin/env perl
use 5.020;
use warnings;
use strict;
use autodie;
#use Smart::Comments;
#use Data::Dumper;
use DBI;                        # Database module
use MIME::Lite;                 # Email module
use YAML qw(LoadFile);          # YAML parser
use List::MoreUtils qw(uniq);   # provides uniq filter function
use Getopt::Std;                # commandline parsing
use FindBin;                    # for loading my module next to the pl file
use lib "$FindBin::Bin";
use SyntaxHighlighter qw(syntax_highlight); # my syntax highlighting code

# global variables
my $config;
my $dbh;
my $db_stmt_insert;
my $db_stmt_lookup;
my $db_stmt_fuzzy_lookup;
my $fuzz = 50; # max line number difference for fuzzy lookup
my $drop_tables = 0; # for testing
my $recipient_override; # for testing
my $verbose = 0; # for testing
my @attachments; # array of file paths that should get attached (e.g. errors.txt)

sub usage {
    print << 'EOF';
blame-notifier.pl [options] < errors.txt
Options:
  -a            : One ore more attachments. Filenames should be separated by a comma.
  -h            : Print this help.
  -d            : Drop table with all stored issues.
  -r <email>    : Override recipient email addresses.
Examples:
   * Testing   : blame-notifier.pl -d -r user@domain.com -a pvs-report/index.html < pvs-report/errors.txt
   * Production: blame-notifier.pl -a pvs-report/index.html < pvs-report/errors.txt
EOF
}

sub verbose {
    print(@_) if $verbose > 0;
}

sub db_connect {
    $dbh = DBI->connect($config->{dsn}, $config->{username}, $config->{password});

    # prepare some DB statements
    $db_stmt_insert = $dbh->prepare("INSERT INTO errors(commit, file, line, col, type, code, message) VALUES(?,?,?,?,?,?,?);");
    $db_stmt_lookup = $dbh->prepare("SELECT id FROM errors WHERE commit=? AND file=? AND line=? AND code=?;");
    $db_stmt_fuzzy_lookup = $dbh->prepare("SELECT id FROM errors WHERE commit=? AND file=? AND line>=? AND line<=? AND code=?;");

    # drop only for testing
    if ($drop_tables) {
        shift @ARGV;
        $dbh->do("DROP TABLE errors");
    }
}

sub db_disconnect {
    $db_stmt_insert->finish();
    $db_stmt_lookup->finish();
    $db_stmt_fuzzy_lookup->finish();
    $dbh->disconnect();
}

sub db_create_tables {
    my $sql = <<EOF;
CREATE TABLE IF NOT EXISTS errors(
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    commit VARCHAR(32) NOT NULL,
    file VARCHAR(255) NOT NULL,
    line INT NOT NULL,
    col INT NOT NULL,
    type VARCHAR(10) NOT NULL,
    code INT NOT NULL,
    message VARCHAR(255) NOT NULL,
    INDEX issue (commit, file, line)
);
EOF
    $dbh->do($sql);
}

sub db_add {
    my $entry = shift;
    $db_stmt_insert->execute($entry->{commit}, $entry->{file}, $entry->{line}, $entry->{col}, $entry->{type}, $entry->{code}, $entry->{message});
}

sub db_lookup {
    my $entry = shift;
    $db_stmt_lookup->execute($entry->{commit}, $entry->{file}, $entry->{line}, $entry->{code});
    my @row = $db_stmt_lookup->fetchrow_array();
    return $row[0];
}

sub db_fuzzy_lookup {
    my $entry = shift;
    my $from = $entry->{line} - $fuzz;
    my $to = $entry->{line} + $fuzz;
    $db_stmt_fuzzy_lookup->execute($entry->{commit}, $entry->{file}, $from, $to, $entry->{code});
    my @row = $db_stmt_fuzzy_lookup->fetchrow_array();
    return $row[0];
}

sub parse_errors {
    my $file = shift;
    my @issues;

    verbose("Parsing PVS errors...\n");

    foreach (<>) {
        if (/(.+):(\d+):(\d+): (\w+): V(\d+) (.*)/) {
            my ($file, $line, $col, $type, $code, $message) = ($1, $2, $3, $4, $5, $6);
            ### file: $file
            ### line: $line
            ### col: $col
            ### type: $type
            ### code: $code
            ### message: $message
            if (defined $config->{path_search} && defined $config->{path_replace}) {
                $file =~ s/$config->{path_search}/$config->{path_replace}/;
            }
            push @issues, { file => $file, line => $line, col => $col, type => $type, code => $code, message => $message };
        } else {
            print(STDERR "error: could not parse error message\n");
        }
    }

    # sort by filename and line
    @issues = sort {$a->{file} cmp $b->{file} || $a->{line} <=> $b->{line} } @issues;

    return \@issues;
}

# returns code fragment for issue
sub get_code {
    my $file = shift;
    my $line = shift;
    my $from = $line - 3;
    my $to = $line + 3;
    my $command = "git blame -s -L$from,$to $file";
    my $code = `$command`;
    return $code;
}

sub get_repo_url {
    my $url = `git config --get remote.origin.url`;
    return $url;
}

sub get_current_branch {
    my $branch = `git rev-parse --abbrev-ref HEAD`;
    return $branch;
}

# simple function which turns an email address into name and lastname
# this works only for our corporate mails with this syntax: name.lastname@domain
# as a fallback it will use the complete part before @domain.
sub extract_user_name {
    my $email = shift;
    my $id = {
        name => 'John',
        lastname => 'Doe',
    };

    if ($email =~ m/(\w+)\.(\w+)@/) {
        $id->{name} = ucfirst($1);
        $id->{lastname} = ucfirst($2);
    } elsif ($email =~ m/([\w-]+)@/) {
        $id->{name} = ucfirst($1);
        $id->{lastname} = '';
    }

    return $id;
}

sub create_message {
    my $issues = shift;
    my $author = shift;
    my $id = extract_user_name($author);
    my $url = get_repo_url();
    my $branch = get_current_branch();
    my $msg = "";
    my $count = 0;

    verbose("Creating message...\n");

    $msg .= <<EOF;
<html><body>
Hi $id->{name},<br/>
<br/>
one of your commits introduced a new PVS issue.<br/>
<br/>
<b>repository:</b> $url ($branch)<br/>
<br/>
EOF

    foreach my $issue (@{$issues}) {
        next if ($issue->{email} ne $author);

        my $code = get_code($issue->{file}, $issue->{line});
        my $html = syntax_highlight($code);
        $msg .= <<EOF;
<p>
<b>$issue->{type}: V$issue->{code} $issue->{message}</b></br>
$issue->{file}:$issue->{line}</br>
<pre>
$html
</pre>
</p>
EOF
        $count++;
    }

    if ($count == 1) {
        $msg .= <<EOF;
<p>
This issue is identified by its commit SHA1, file and line number and
will be reported only once.
</p>
EOF
    } else {
        $msg .= <<EOF;
<p>
These issues are identified by its commit SHA1, file and line number and
will be reported only once.
</p>
EOF
    }
    $msg .= "</body></html>\n";

    return $msg;
}

# update issue list with author info
sub add_author_info {
    my $issues = shift; # sorted array of issues
    my $start = shift;  # search start offset
    my $file = shift;   # filename of issue
    my $line = shift;   # line number of issue
    my $commit = shift; # git commit SHA1
    my $email = shift;  # git author email

    do {
        my $issue = @{$issues}[$start];
        if ($issue->{file} eq $file && $issue->{line} == $line) {
            ### adding new info
            ### file: $file
            ### line: $line
            ### commit: $commit
            ### email: $email
            @{$issues}[$start]->{commit} = $commit;
            @{$issues}[$start]->{email} = $email;
            return;
        }
        $start++;
    } while ($start < scalar @{$issues});

    print(STDERR "error: did not find issue for commit $commit.\n");
}

# extract git SHA1 and author for every line
# Concept:
# - errors.txt
#   1: fileA:112: message
#   2: fileA:134: message
#   3: fileB:14: message
#   4: fileC:214: message1
#   5: fileC:214: message2 for same line
# - grouping on files basis to reduce number of git syscalls
#   - git annotatate -L112,112 -L134,134 fileA (source lines: 1,2)
#   - git annotatate -L14,14 fileB (source lines: 3)
#   - git annotatate -L214,214 fileC (source lines: 4,5)
# - results need to be fed back to orignal issue list
sub git_blame {
    my $issues = shift;
    # list of line numbers of each file stored in a Perl hash
    # key: filename
    # value: reference to array line mapping entries
    my %files;

    verbose("Git blame...\n");

    # group lines by filename
    my $index = 0;
    foreach my $issue (@{$issues}) {
        my $file = $issue->{file}; # just a shortcut var
        my $line = $issue->{line}; # just a shortcut var
        # get or create issue/line mapping object
        my $mappings = $files{$file} // [];
        my $entry = {
            file => $file,           # source file name
            lineno => $line,         # line number in source file
            source_lineno => $index, # line number of issue in errors.txt
        };
        push @{$mappings}, $entry;
        $files{$file} = $mappings;
        $index++;
    }

    # now call git-blame for each file with a list of line numbers
    # this is a little bit more efficient than calling git-blame for every single line
    foreach my $file (sort keys %files) {
        my $mappings = $files{$file};
        my $range = "";
        foreach my $entry (@{$mappings}) {
            my $lineno = $entry->{lineno};
            $range .= "-L $lineno,$lineno ";
        }
        my $command = "git annotate -e -t $range $file";
        ### command: $command
        my $output = `$command`;
        my @output = split(/\n/, $output);
        ### git-blame output: @output

        foreach my $line (@output) {
            # just a very basic email regex, not RFC822 compliant. Use Email::Valid instead if you need more.
            if ($line =~ m/^([a-z0-9]+)\s+\(<([\w.-]+@[\w.-]+)>\s+\d+\s.?\d+\s+(\d+)\)/) {
                my $sha1 = $1;
                my $email = $2;
                my $lineno = $3;
                foreach my $mapping (@{$mappings}) {
                    # update all issues with this file/lineno combination
                    if ($mapping->{lineno} == $lineno) {
                        my $source_lineno = $mapping->{source_lineno};
#                        print "Adding $file, $source_lineno, $sha1 $email\n";
                        add_author_info($issues, $source_lineno, $file, $lineno, $sha1, $email);
                    }
                }
            } else {
                print(STDERR "error: no match for '$output'\n");
            }
        }
    }
}

sub sendmail {
    my $message = shift;
    my $recipient = shift;

    # override
    if (defined $recipient_override) {
        $recipient = $recipient_override;
    }

    verbose("Sending mail to $recipient...\n");

    my $mail = MIME::Lite->new(
        To => $recipient,
        CC => $config->{smtp_cc},
        From => $config->{smtp_from},
        Subject => $config->{smtp_subject} // "New PVS Errors",
        Type    => 'multipart/mixed'
    );
    $mail->attach(
        Type     => 'text/html',
        Data     => $message
    );
    foreach my $attachment (@attachments) {
        if (-f $attachment) {
            $mail->attach(
                Type => 'AUTO',
                Path => $attachment,
                Disposition => 'attachment');
        }
    }

    if (open(my $sendmail, "|/usr/sbin/sendmail -t -oi")) {
        $mail->print(\*$sendmail);
        close($sendmail);
        print "Email Sent Successfully\n";
    } else {
        print "Failed to open sendmail command.\n";
    }
}

sub load_config {
    if (-f '/etc/blame.cfg') {
        $config = LoadFile('/etc/blame.cfg');
    }
    if (-f "$ENV{HOME}/.blame.cfg") {
        $config = LoadFile("$ENV{HOME}/.blame.cfg");
    }
    if (!defined $config) {
        printf(STDERR "error: could not load config file.\n");
        exit(1);
    }
}

sub main {
    my %opts;

    # parse commandline args
    getopts('a:dhr:v', \%opts);
    if (exists $opts{a}) {
        @attachments = split(/,/, $opts{a});
    }
    if (exists $opts{d}) {
        $drop_tables = 1;
    }
    if (exists $opts{h}) {
        usage();
        exit(0);
    }
    if (exists $opts{r}) {
        $recipient_override = $opts{r};
    }
    if (exists $opts{v}) {
        $verbose = 1;
    }

    load_config();

    db_connect();
    db_create_tables();

    # parse PVS errors
    my $issues = parse_errors();
    my @recipients;

    git_blame($issues);

    # use DB to filter out new issues
    my @new_issues;
    foreach my $issue (@{$issues}) {
        my $id = db_lookup($issue);
        if (!defined $id) {
            #### not found -> fuzzy search
            $id = db_fuzzy_lookup($issue);
        }
        if ($id) {
            #### found: $id
        } else {
            #### adding new issue
            if ($issue->{commit}) {
                db_add($issue);
                push @new_issues, $issue;
                push @recipients, $issue->{email} if ($issue->{email});
            } else {
                print(STDERR "issue with no commit\n");
#                print Dumper($issue);
            }
        }
    }
    db_disconnect();

    @recipients = uniq @recipients;

    # create and send email
    foreach my $author (@recipients) {
        my $message = create_message(\@new_issues, $author);
        sendmail($message, $author);
    }
}

main();

__END__

Requirements:
sudo apt install libdbi-perl libclass-dbi-mysql-perl
