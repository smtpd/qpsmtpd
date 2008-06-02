package Qpsmtpd::Plugin::Async::DNSBLBase;

# Class methods shared by the async plugins using DNS based blacklists or
# whitelists.

use strict;
use Qpsmtpd::Constants;
use ParaDNS;

sub lookup {
    my ($class, $qp, $A_lookups, $TXT_lookups) = @_;

    my $total_zones = @$A_lookups + @$TXT_lookups;

    my ($A_pdns, $TXT_pdns);

    if (@$A_lookups) {
        $qp->log(LOGDEBUG, "Checking ",
                 join(", ", @$A_lookups),
                 " for A record in the background");

        $A_pdns = ParaDNS->new(
            callback => sub {
                my ($result, $query) = @_;
                return if $result !~ /^\d+\.\d+\.\d+\.\d+$/;
                $qp->log(LOGDEBUG, "Result for A $query: $result");
                $class->process_a_result($qp, $result, $query);
            },
            finished => sub {
                $total_zones -= @$A_lookups;
                $class->finished($qp, $total_zones);
            },
            hosts  => [@$A_lookups],
            type   => 'A',
            client => $qp->input_sock,
                              );

        return unless defined $A_pdns;
    }

    if (@$TXT_lookups) {
        $qp->log(LOGDEBUG, "Checking ",
                 join(", ", @$TXT_lookups),
                 " for TXT record in the background");

        $TXT_pdns = ParaDNS->new(
            callback => sub {
                my ($result, $query) = @_;
                return if $result !~ /[a-z]/;
                $qp->log(LOGDEBUG, "Result for TXT $query: $result");
                $class->process_txt_result($qp, $result, $query);
            },
            finished => sub {
                $total_zones -= @$TXT_lookups;
                $class->finished($qp, $total_zones);
            },
            hosts  => [@$TXT_lookups],
            type   => 'TXT',
            client => $qp->input_sock,
                                );

        unless (defined $TXT_pdns) {
            undef $A_pdns;
            return;
        }
    }

    return 1;
}

sub finished {
    my ($class, $qp, $total_zones) = @_;
    $qp->log(LOGDEBUG, "Finished ($total_zones)");
    $qp->run_continuation unless $total_zones;
}

# plugins should implement the following two methods to do something
# useful with the results
sub process_a_result {
    my ($class, $qp, $result, $query) = @_;
}

sub process_txt_result {
    my ($class, $qp, $result, $query) = @_;
}

1;
