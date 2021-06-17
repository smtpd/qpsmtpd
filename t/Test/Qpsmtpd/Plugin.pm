package Test::Qpsmtpd::Plugin;
use strict;
1;

# Additional plugin methods used during testing
package Qpsmtpd::Plugin;

use strict;
use warnings;

use Test::More;
use Qpsmtpd::Constants;

sub register_tests {

    # Virtual base method - implement in plugin
}

sub register_test {
    my ($plugin, $test) = @_;

    # print STDERR "Registering test $test ($num_tests)\n";
    push @{$plugin->{_tests}}, {name => $test};
}

sub run_tests {
    my ($plugin, $qp) = @_;
    foreach my $t (@{$plugin->{_tests}}) {
        my $method = $t->{name};
        print "# " . $plugin->plugin_name . "\t $method\n";
        local $plugin->{_qp} = $qp;
        $plugin->$method();
    }
}

sub validate_password {
    my ($self, %a) = @_;

    my ($pkg, $file, $line) = caller();

    my $src_clear     = $a{src_clear};
    my $src_crypt     = $a{src_crypt};
    my $attempt_clear = $a{attempt_clear};
    my $attempt_hash  = $a{attempt_hash};
    my $method        = $a{method} or die "missing method";
    my $ticket        = $a{ticket};
    my $deny          = $a{deny} || DENY;

    if (!$src_crypt && !$src_clear) {
        $self->log(LOGINFO, "fail: missing password");
        return $deny, "$file - no such user";
    }

    if (!$src_clear && $method =~ /CRAM-MD5/i) {
        $self->log(LOGINFO, "skip: cram-md5 not supported w/o clear pass");
        return DECLINED, $file;
    }

    if (defined $attempt_clear) {
        if ($src_clear && $src_clear eq $attempt_clear) {
            $self->log(LOGINFO, "pass: clear match");
            return OK, $file;
        }

        if ($src_crypt && $src_crypt eq crypt($attempt_clear, $src_crypt)) {
            $self->log(LOGINFO, "pass: crypt match");
            return OK, $file;
        }
    }

    if (defined $attempt_hash && $src_clear) {
        if (!$ticket) {
            $self->log(LOGERROR, "skip: missing ticket");
            return DECLINED, $file;
        }

        if ($attempt_hash eq hmac_md5_hex($ticket, $src_clear)) {
            $self->log(LOGINFO, "pass: hash match");
            return OK, $file;
        }
    }

    $self->log(LOGINFO, "fail: wrong password");
    return $deny, "$file - wrong password";
}

sub mock_hook     { shift->qp->mock_hook(@_)     }
sub unmock_hook   { shift->qp->unmock_hook(@_)   }
sub mock_config   { shift->qp->mock_config(@_)   }
sub unmock_config { shift->qp->unmock_config(@_) }

1;
