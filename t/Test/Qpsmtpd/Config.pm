package Test::Qpsmtpd::Config;
use strict;
1;

# Additional plugin methods used during testing
package Qpsmtpd::Config;

use strict;
use warnings;

no warnings qw( redefine );
sub config_dir {
    return './t/config' if $ENV{QPSMTPD_DEVELOPER};
    return './config.sample';
}

1;
