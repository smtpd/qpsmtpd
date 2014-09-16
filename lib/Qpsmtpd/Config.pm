package Qpsmtpd::Config;
use strict;
use warnings;

use Sys::Hostname;

use lib 'lib';
use parent 'Qpsmtpd::Base';
use Qpsmtpd::Constants;

our $_config_cache = {};
our %dir_memo;
our %defaults = (
                me      => hostname,
                timeout => 1200,
               );

sub log {
    my ($self, $trace, @log) = @_;
    # logging methods attempt to read config files, this log() prevents that
    # until after logging has fully loaded
    return if $trace > LOGWARN;
    no warnings 'once';
    if ($Qpsmtpd::LOGGING_LOADED) {
        return Qpsmtpd->log($trace, @log);
    }
    warn join(' ', $$, @log) . "\n";
}

sub config_dir {
    my ($self, $config) = @_;
    if (exists $dir_memo{$config}) {
        return $dir_memo{$config};
    }
    my $configdir = ($ENV{QMAIL} || '/var/qmail') . '/control';
    my ($path) = ($ENV{PROCESS} ? $ENV{PROCESS} : $0) =~ m!(.*?)/([^/]+)$!;
    $configdir = "$path/config" if -e "$path/config/$config";
    if (exists $ENV{QPSMTPD_CONFIG}) {
        $ENV{QPSMTPD_CONFIG} =~ /^(.*)$/;    # detaint
        $configdir = $1 if -e "$1/$config";
    }
    return $dir_memo{$config} = $configdir;
}

sub clear_cache {
    $_config_cache = {};
    %dir_memo = ();
}

sub default {
    my ($self, $def) = @_;
    return if ! $defaults{$def};
    return wantarray ? ($defaults{$def}) : $defaults{$def};
}

sub get_qmail {
    my ($self, $config, $type) = @_;
    $self->log(LOGDEBUG, "trying to get config for $config");
    my $configdir = $self->config_dir($config);

    my $configfile = "$configdir/$config";

    # CDB config support really should be moved to a plugin
    if ($type and $type eq "map") {
        return $self->get_qmail_map($config, $configfile);
    }

    return $self->from_file($configfile, $config);
}

sub get_qmail_map {
    my ($self, $config, $configfile) = @_;

    if (!-e $configfile . ".cdb") {
        $_config_cache->{$config} ||= [];
        return +{};
    }
    eval { require CDB_File };

    if ($@) {
        $self->log(LOGERROR,
"No CDB Support! Did NOT read $configfile.cdb, could not load CDB_File module: $@"
        );
        return +{};
    }

    my %h;
    unless (tie(%h, 'CDB_File', "$configfile.cdb")) {
        $self->log(LOGERROR, "tie of $configfile.cdb failed: $!");
        return +{};
    }

    # We explicitly don't cache cdb entries. The assumption is that
    # the data is in a CDB file in the first place because there's
    # lots of data and the cache hit ratio would be low.
    return \%h;
}

sub from_file {
    my ($self, $configfile, $config, $visited) = @_;
    if (!-e $configfile) {
        $_config_cache->{$config} ||= [];
        return;
    }

    $visited ||= [];
    push @$visited, $configfile;

    open my $CF, '<', $configfile or do {
        warn "$$ could not open configfile $configfile: $!";
        return;
    };
    my @config = <$CF>;
    close $CF;

    chomp @config;
    @config = grep { length($_) and $_ !~ m/^\s*#/ and $_ =~ m/\S/ } @config;
    for (@config) { s/^\s+//; s/\s+$//; }    # trim leading/trailing whitespace

    my $pos = 0;
    while ($pos < @config) {

       # recursively pursue an $include reference, if found.  An inclusion which
       # begins with a leading slash is interpreted as a path to a file and will
       # supercede the usual config path resolution.  Otherwise, the normal
       # config_dir() lookup is employed (the location in which the inclusion
       # appeared receives no special precedence; possibly it should, but it'd
       # be complicated beyond justifiability for so simple a config system.
        if ($config[$pos] =~ /^\s*\$include\s+(\S+)\s*$/) {
            my ($includedir, $inclusion) = ('', $1);

            splice @config, $pos, 1;    # remove the $include line
            if ($inclusion !~ /^\//) {
                $includedir = $self->config_dir($inclusion);
                $inclusion  = "$includedir/$inclusion";
            }

            if (grep($_ eq $inclusion, @{$visited})) {
                $self->log(LOGERROR,
                           "Circular \$include reference in config $config:");
                $self->log(LOGERROR, "From $visited->[0]:");
                $self->log(LOGERROR, "  includes $_")
                  for (@{$visited}[1 .. $#{$visited}], $inclusion);
                return wantarray ? () : undef;
            }
            push @{$visited}, $inclusion;

            for my $inc ($self->expand_inclusion_($inclusion, $configfile)) {
                my @insertion = $self->from_file($inc, $config, $visited);
                splice @config, $pos, 0, @insertion;    # insert the inclusion
                $pos += @insertion;
            }
        }
        else {
            $pos++;
        }
    }

    $_config_cache->{$config} = \@config;

    return wantarray ? @config : $config[0];
}

sub expand_inclusion_ {
    my $self      = shift;
    my $inclusion = shift;
    my $context   = shift;
    my @includes;

    if (-d $inclusion) {
        $self->log(LOGDEBUG, "inclusion of directory $inclusion from $context");

        if (opendir(INCD, $inclusion)) {
            @includes = map { "$inclusion/$_" }
              (grep { -f "$inclusion/$_" and !/^\./ } sort readdir INCD);
            closedir INCD;
        }
        else {
            $self->log(LOGERROR,
                           "Couldn't open directory $inclusion,"
                         . " referenced from $context ($!)"
                      );
        }
    }
    else {
        $self->log(LOGDEBUG, "inclusion of file $inclusion from $context");
        @includes = ($inclusion);
    }
    return @includes;
}

1;
