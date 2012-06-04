package Test::Qpsmtpd::Plugin;
1;

# Additional plugin methods used during testing
package Qpsmtpd::Plugin;

use strict;
use warnings;

use Qpsmtpd::Constants;
use Test::More;

sub register_tests {
    # Virtual base method - implement in plugin
}

sub register_test {
    my ($plugin, $test, $num_tests) = @_;
    $num_tests = 1 unless defined($num_tests);
    # print STDERR "Registering test $test ($num_tests)\n";
    push @{$plugin->{_tests}}, { name => $test, num => $num_tests };
}

sub total_tests {
    my ($plugin) = @_;
    my $total = 0;
    foreach my $t (@{$plugin->{_tests}}) {
        $total += $t->{num};
    }
    return $total;
}

sub run_tests {
    my ($plugin, $qp) = @_;
    foreach my $t (@{$plugin->{_tests}}) {
        my $method = $t->{name};
        print "# Running $method tests for plugin " . $plugin->plugin_name . "\n";
        local $plugin->{_qp} = $qp;
        $plugin->$method();
    }
}

1;
