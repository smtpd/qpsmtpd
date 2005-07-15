# $Id$

package Apache::Qpsmtpd;

use 5.006001;
use strict;
use warnings FATAL => 'all';

use Apache2::ServerUtil ();
use Apache2::Connection ();
use Apache2::Const -compile => qw(OK MODE_GETLINE);
use APR::Const -compile => qw(SO_NONBLOCK EOF SUCCESS);
use APR::Error ();
use APR::Brigade ();
use APR::Bucket ();
use APR::Socket ();
use Apache2::Filter ();
use ModPerl::Util ();

our $VERSION = '0.02';

sub handler {
    my Apache2::Connection $c = shift;
    $c->client_socket->opt_set(APR::Const::SO_NONBLOCK => 0);

    my $qpsmtpd = Qpsmtpd::Apache->new();
    $qpsmtpd->start_connection(
        ip => $c->remote_ip,
        host => $c->remote_host,
        info => undef,
        dir => $c->base_server->dir_config('QpsmtpdDir'),
        conn => $c,
    );
    
    $qpsmtpd->run($c);

    return Apache2::Const::OK;
}

package Qpsmtpd::Apache;

use Qpsmtpd::Constants;
use base qw(Qpsmtpd::SMTP);

sub start_connection {
    my $self = shift;
    my %opts = @_;

    $self->{qpdir} = $opts{dir};
    $self->{conn} = $opts{conn};
    $self->{conn}->client_socket->timeout_set($self->config('timeout') * 1_000_000);
    $self->{bb_in} = APR::Brigade->new($self->{conn}->pool, $self->{conn}->bucket_alloc);
    $self->{bb_out} = APR::Brigade->new($self->{conn}->pool, $self->{conn}->bucket_alloc);

    my $remote_host = $opts{host} || ( $opts{ip} ? "[$opts{ip}]" : "[noip!]");
    my $remote_info = $opts{info} ? "$opts{info}\@$remote_host" : $remote_host;
    my $remote_ip = $opts{ip};

    $self->log(LOGNOTICE, "Connection from $remote_info [$remote_ip]");

    $self->SUPER::connection->start(
        remote_info => $remote_info,
        remote_ip   => $remote_ip,
        remote_host => $remote_host,
        @_);
}

sub config {
    my $self = shift;
    my ($param, $type) = @_;
    if (!$type) {
        my $opt = $self->{conn}->base_server->dir_config("qpsmtpd.$param");
        return $opt if defined($opt);
    }
    return $self->SUPER::config(@_);
}

sub run {
    my $self = shift;

    # should be somewhere in Qpsmtpd.pm and not here...
    $self->load_plugins;

    my $rc = $self->start_conversation;
    return if $rc != DONE;

    # this should really be the loop and read_input should just
    # get one line; I think
    $self->read_input();
}

sub config_dir {
    my ($self, $config) = @_;
    -e "$_/$config" and return $_
        for "$self->{qpdir}/config";
    return "/var/qmail/control";
}

sub plugin_dir {
    my $self = shift;
    return "$self->{qpdir}/plugins";
}

sub getline {
    my $self = shift;
    my $c = $self->{conn} || die "Cannot getline without a conn";

    return if $c->aborted;

    my $bb = $self->{bb_in};
    
    while (1) {
        my $rc = $c->input_filters->get_brigade($bb, Apache2::Const::MODE_GETLINE);
        return if $rc == APR::Const::EOF;
        die APR::Error::strerror($rc) unless $rc == APR::Const::SUCCESS;
        
        next unless $bb->flatten(my $data);
        
        $bb->cleanup;
        return $data;
    }
    
    return '';
}

sub read_input {
    my $self = shift;
    my $c = $self->{conn};

    while (defined(my $data = $self->getline)) {
        $data =~ s/\r?\n$//s; # advanced chomp
        $self->log(LOGDEBUG, "dispatching $data");
        defined $self->dispatch(split / +/, $data)
            or $self->respond(502, "command unrecognized: '$data'");
        last if $self->{_quitting};
    }
}

sub respond {
    my ($self, $code, @messages) = @_;
    my $c = $self->{conn};
    while (my $msg = shift @messages) {
        my $bb = $self->{bb_out};
        my $line = $code . (@messages?"-":" ").$msg;
        $self->log(LOGDEBUG, $line);
        my $bucket = APR::Bucket->new(($c->bucket_alloc), "$line\r\n");
        $bb->insert_tail($bucket);
        $c->output_filters->fflush($bb);
        # $bucket->remove;
        $bb->cleanup;
    }
    return 1;
}

sub disconnect {
    my $self = shift;
    $self->SUPER::disconnect(@_);
    $self->{_quitting} = 1;
    $self->{conn}->client_socket->close();
}

1;

__END__

=head1 NAME

Apache::Qpsmtpd - a mod_perl-2 connection handler for qpsmtpd

=head1 SYNOPSIS

  Listen 0.0.0.0:25
  
  LoadModule perl_module modules/mod_perl.so
  
  <Perl>
  use lib qw( /path/to/qpsmtpd/lib );
  use Apache::Qpsmtpd;
  </Perl>
  
  <VirtualHost _default_:25>
  PerlSetVar QpsmtpdDir /path/to/qpsmtpd
  PerlModule Apache::Qpsmtpd
  PerlProcessConnectionHandler Apache::Qpsmtpd
  PerlSetVar qpsmtpd.loglevel 4
  </VirtualHost>

=head1 DESCRIPTION

This module implements a mod_perl/apache 2.0 connection handler
that turns Apache into an SMTP server using Qpsmtpd.

It also allows you to set single-valued config options (such
as I<loglevel>, as seen above) using C<PerlSetVar> in F<httpd.conf>.

This module should be considered beta software as it is not yet
widely tested. However it is currently the fastest way to run
Qpsmtpd, so if performance is important to you then consider this
module.

=head1 BUGS

Currently the F<check_early_talker> plugin will not work because it
relies on being able to do C<select()> on F<STDIN> which does not
work here. It should be possible with the next release of mod_perl
to do a C<poll()> on the socket though, so we can hopefully get
that working in the future.

Other operations that perform directly on the STDIN/STDOUT filehandles
will not work.

=head1 AUTHOR

Matt Sergeant, <matt@sergeant.org>

Some credit goes to <mock@obscurity.org> for Apache::SMTP which gave
me the inspiration to do this.

=cut
