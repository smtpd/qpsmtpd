use strict;
use warnings;

use Test::More;
use Mail::Header;

use lib 'lib';
use Qpsmtpd::Transaction;

# collects what print_message writes
package Collector {
    sub new   { bless {data => '', closed => 0}, shift }
    sub PRINT { $_[0]{data} .= $_[1] }
    sub CLOSE { $_[0]{closed}++ }
}

my $t = Qpsmtpd::Transaction->new;
$t->header(Mail::Header->new(["Subject: hi\n", "X-Folded: one\n", "\ttwo\n"],
                             Modify => 0));
$t->body_write("Subject: hi\nX-Folded: one\n\ttwo\n");
$t->set_body_start;
$t->body_write("\nfirst line\r\n0\nlast line\n");

my $collector = Collector->new;
$t->print_message($collector);
is($collector->{data},
   "Subject: hi\r\nX-Folded: one\r\n\ttwo\r\n\r\nfirst line\r\n0\r\nlast line\r\n",
   'print_message writes the header and body with CRLF line endings');
is($collector->{closed}, 1, 'print_message closes the object');

done_testing;
