package SyntaxHighlighter;

use warnings;
use strict;
use Carp;
use vars qw(@ISA @EXPORT @EXPORT_OK @EXPORT_TAGS $VERSION);

use Exporter;
$VERSION = 1.00;
@ISA = qw(Exporter);

@EXPORT = qw();
@EXPORT_OK = qw(has_source_highlighter syntax_highlight);

use FindBin;
#use Smart::Comments;

my $have_ipc_filter;
my $have_source_highlighter;

BEGIN {
    # conditionally load this module and keep working if not found
    # users don't want to see exceptions
    eval {
        require IPC::Filter;
        IPC::Filter->import('filter');
        $have_ipc_filter = 1;
    };
    if ($have_ipc_filter == 0) {
        print(STDERR "warning: Perl module IPC::Filter is missing.\n");
        print(STDERR "Use `sudo apt install libipc-filter-perl` to install it.\n");
    }
    # check of GNU source highlighter is available
    if (-x "/usr/bin/source-highlight") {
        $have_source_highlighter = 1;
    }
}

# Returns 1 if the GNU source highlighter is found.
sub has_source_highlighter {
    return $have_source_highlighter;
}

# here the magic happens
sub syntax_highlight {
    my $code = shift;
    my $PWD = $FindBin::Bin;

    ### have_ipc_filter: $have_ipc_filter
    ### have_source_highlighter: $have_source_highlighter

    # check for dependencies
    if ($have_ipc_filter && $have_source_highlighter) {
        # highlight code in Monokai style
        my $html = filter($code, "/usr/bin/source-highlight", "--style-css-file=$PWD/style/monokai.css", "-s", "C");
        # add missing background colors
        $html =~ s/<pre>/<pre style="color: #F8F8F2; background-color: #272822;">/;
        return $html;
    }

    # return code unmodified
    return $code;
}

1
__END__

=head1 NAME

SyntaxHighlighter.pm - Super Simple SyntaxHighlighter module

It simply uses GNU source highlighter command line tool.
This module detects if the tool is installed.
If not it prints the rest of the perl code still works.

=head1 VERSION

This documentation refers to SyntaxHighlighter.pm version 0.0.1

=head1 USAGE

    use SyntaxHighlighter;

=head1 REQUIRED ARGUMENTS

=over

None

=back

=head1 OPTIONS

=over

None

=back

=head1 DIAGNOSTICS

None.

=head1 CONFIGURATION AND ENVIRONMENT

Requires no configuration files or environment variables.


=head1 DEPENDENCIES

GNU Source SyntaxHighlighter.


=head1 BUGS

None reported.
Bug reports and other feedback are most welcome.


=head1 AUTHOR

Gerhard Gappmeier C<< gerhard.gappmeier@ascolab.com >>


=head1 COPYRIGHT

Copyright (c) 2020, Gerhard Gappmeier C<< <gerhard.gappmeier@ascolab.com> >>. All rights reserved.

This module is free software. It may be used, redistributed
and/or modified under the terms of the Perl Artistic License
(see http://www.perl.com/perl/misc/Artistic.html)


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.


