package Qpsmtpd::TcpServer;
use Qpsmtpd::SMTP;
use Qpsmtpd::Constants;

@ISA = qw(Qpsmtpd::SMTP);
use strict;

use POSIX ();

my $first_0; 

sub start_connection {
    my $self = shift;

    die "Qpsmtpd::TcpServer must be started by tcpserver\n"
      unless $ENV{TCPREMOTEIP};

    my $remote_host = $ENV{TCPREMOTEHOST} || ( $ENV{TCPREMOTEIP} ? "[$ENV{TCPREMOTEIP}]" : "[noip!]");
    my $remote_info = $ENV{TCPREMOTEINFO} ? "$ENV{TCPREMOTEINFO}\@$remote_host" : $remote_host;
    my $remote_ip   = $ENV{TCPREMOTEIP};
    $self->log(LOGNOTICE, "Connection from $remote_info [$remote_ip]");

    # if the local dns resolver doesn't filter it out we might get
    # ansi escape characters that could make a ps axw do "funny"
    # things. So to be safe, cut them out.  
    $remote_host =~ tr/a-zA-Z\.\-0-9//cd;

    $first_0 = $0 unless $first_0;
    my $now = POSIX::strftime("%H:%M:%S %Y-%m-%d", localtime);
    $0 = "$first_0 [$remote_ip : $remote_host : $now]";

    $self->SUPER::connection->start(remote_info => $remote_info,
				    remote_ip   => $remote_ip,
				    remote_host => $remote_host,
				    @_);
}

sub run {
    my $self = shift;

    # should be somewhere in Qpsmtpd.pm and not here...
    $self->load_plugins;

    my $rc = $self->start_conversation;
    return if $rc != DONE;

    # this should really be the loop and read_input should just get one line; I think

    $self->read_input;
}

sub read_input {
  my $self = shift;

  my $timeout = $self->config('timeout');
  alarm $timeout;
  while (<STDIN>) {
    alarm 0;
    $_ =~ s/\r?\n$//s; # advanced chomp
    $self->log(LOGDEBUG, "dispatching $_");
    defined $self->dispatch(split / +/, $_)
      or $self->respond(502, "command unrecognized: '$_'");
    alarm $timeout;
  }
  alarm(0);
}

sub respond {
  my ($self, $code, @messages) = @_;
  while (my $msg = shift @messages) {
    my $line = $code . (@messages?"-":" ").$msg;
    $self->log(LOGDEBUG, $line);
    print "$line\r\n" or ($self->log(LOGERROR, "Could not print [$line]: $!"), return 0);
  }
  return 1;
}

sub disconnect {
  my $self = shift;
  $self->SUPER::disconnect(@_);
  exit;
}

1;
