# $Id$

package Test::Qpsmtpd::Plugin;
1;

# Additional plugin methods used during testing
package Qpsmtpd::Plugin;

use Test::More;
use strict;

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
        diag "Running $method tests for plugin " . $plugin->plugin_name;
        local $plugin->{_qp} = $qp;
        $plugin->$method();
    }
}

1;
