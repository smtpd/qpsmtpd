package Qpsmtpd::Command;

=head1 NAME

Qpsmtpd::Command - parse arguments to SMTP commands

=head1 DESCRIPTION

B<Qpsmtpd::Command> provides just one public sub routine: B<parse()>.

This sub expects two or three arguments. The first is the name of the 
SMTP command (such as I<HELO>, I<MAIL>, ...). The second must be the remaining
of the line the client sent.

If no third argument is given (or it's not a reference to a CODE) it parses 
the line according to RFC 1869 (SMTP Service Extensions) for the I<MAIL> and 
I<RCPT> commands and splitting by spaces (" ") for all other.

Any module can supply it's own parsing routine by returning a sub routine 
reference from a hook_*_parse. This sub will be called with I<$self>, I<$cmd>
and I<$line>. 

On successfull parsing it MUST return B<OK> (the constant from 
I<Qpsmtpd::Constants>) success as first argument and a list of 
values, which will be the arguments to the hook for this command.

If parsing failed, the second returned value (if any) will be returned to the
client as error message.

=head1 EXAMPLE

Inside a plugin 

 sub hook_unrecognized_command_parse {
    my ($self, $transaction, $cmd) = @_;
    return (OK, \&bdat_parser) if ($cmd eq 'bdat');
 }

 sub bdat_parser {
    my ($self,$cmd,$line) = @_;
    # .. do something with $line...
    return (DENY, "Invalid arguments") 
      if $some_reason_why_there_is_a_syntax_error;
    return (OK, @args);
 }

 sub hook_unrecognized_command {
    my ($self, $transaction, $cmd, @args) = @_;
    return (DECLINED) if ($self->qp->connection->hello eq 'helo');
    return (DECLINED) unless ($cmd eq 'bdat');
    ....
 }

=cut

use strict;

use Qpsmtpd::Constants;
use vars qw(@ISA);
@ISA = qw(Qpsmtpd::SMTP);

sub parse {
    my ($me,$cmd,$line,$sub) = @_;
    return (OK) unless defined $line; # trivial case
    my $self = {};
    bless $self, $me;
    $cmd = lc $cmd;
    if ($sub and (ref($sub) eq 'CODE')) {
        my @ret = eval { $sub->($self, $cmd, $line); };
        if ($@) {
            $self->log(LOGERROR, "Failed to parse command [$cmd]: $@");
            return (DENY, $line, ());
        }
        ## my @log = @ret;
        ## for (@log) {
        ##     $_ ||= "";
        ## }
        ## $self->log(LOGDEBUG, "parse($cmd) => [".join("], [", @log)."]");
        return @ret;
    } 
    my $parse = "parse_$cmd";
    if ($self->can($parse)) {
        # print "CMD=$cmd,line=$line\n";
        my @out = eval { $self->$parse($cmd, $line); };
        if ($@) {
            $self->log(LOGERROR, "$parse($cmd,$line) failed: $@");
            return(DENY, "Failed to parse line");
        }
        return @out;
    }
    return(OK, split(/ +/, $line)); # default :)
}

sub parse_rcpt {
    my ($self,$cmd,$line) = @_;
    return (DENY, "Syntax error in command") unless $line =~ s/^to:\s*//i;
    return &_get_mail_params($cmd, $line);
}

sub parse_mail {
    my ($self,$cmd,$line) = @_;
    return (DENY, "Syntax error in command") unless $line =~ s/^from:\s*//i;
    return &_get_mail_params($cmd, $line);
}
### RFC 1869:
## 6.  MAIL FROM and RCPT TO Parameters
## [...]
##
##   esmtp-cmd        ::= inner-esmtp-cmd [SP esmtp-parameters] CR LF
##   esmtp-parameters ::= esmtp-parameter *(SP esmtp-parameter)
##   esmtp-parameter  ::= esmtp-keyword ["=" esmtp-value]
##   esmtp-keyword    ::= (ALPHA / DIGIT) *(ALPHA / DIGIT / "-")
##
##                        ; syntax and values depend on esmtp-keyword
##   esmtp-value      ::= 1*<any CHAR excluding "=", SP, and all
##                           control characters (US ASCII 0-31
##                           inclusive)>
##
##                        ; The following commands are extended to
##                        ; accept extended parameters.
##   inner-esmtp-cmd  ::= ("MAIL FROM:" reverse-path)   /
##                        ("RCPT TO:" forward-path)
sub _get_mail_params {
    my ($cmd,$line) = @_;
    my @params = ();
    $line =~ s/\s*$//;

    while ($line =~ s/\s+([A-Za-z0-9][A-Za-z0-9\-]*(=[^= \x00-\x1f]+)?)$//) {
        push @params, $1;
    }
    @params = reverse @params;

    # the above will "fail" (i.e. all of the line in @params) on 
    # some addresses without <> like
    #    MAIL FROM: user=name@example.net
    # or RCPT TO: postmaster

    # let's see if $line contains nothing and use the first value as address:
    if ($line) {
        # parameter syntax error, i.e. not all of the arguments were 
        # stripped by the while() loop:
        return (DENY, "Syntax error in parameters")
          if ($line =~ /\@.*\s/); 
        return (OK, $line, @params);
    }

    $line = shift @params; 
    if ($cmd eq "mail") {
        return (OK, "<>") unless $line; # 'MAIL FROM:' --> 'MAIL FROM:<>'
        return (DENY, "Syntax error in parameters") 
          if ($line =~ /\@.*\s/); # parameter syntax error
    }
    else {
        if ($line =~ /\@/) {
            return (DENY, "Syntax error in parameters") 
              if ($line =~ /\@.*\s/);
        } 
        else {
            # XXX: what about 'abuse' in Qpsmtpd::Address?
            return (DENY, "Syntax error in parameters") if $line =~ /\s/;
            return (DENY, "Syntax error in address") 
              unless ($line =~ /^(postmaster|abuse)$/i); 
        }
    }
    ## XXX:  No: let this do a plugin, so it's not up to us to decide
    ##       if we require <> around an address :-)
    ## unless ($line =~ /^<.*>$/) { $line = "<".$line.">"; }
    return (OK, $line, @params);
}

1;
