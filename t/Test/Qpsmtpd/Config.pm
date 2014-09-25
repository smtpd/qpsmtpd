package Test::Qpsmtpd::Config;
use strict;
1;

# Additional plugin methods used during testing
package Qpsmtpd::Config;

use strict;
use warnings;

#use Test::More;
#use Qpsmtpd::Constants;

sub config_dir {
    return './t/config' if $ENV{QPSMTPD_DEVELOPER};
    return './config.sample';
}

1;
