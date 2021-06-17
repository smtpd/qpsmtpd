# Advanced Playground

## Discarding messages

If you want to make the client think a message has been regularily accepted,
but in real you delete it or send it to `/dev/null`, ..., use something
like the following plugin and load it before your default queue plugin.

    sub hook_queue {
      my ($self, $transaction) = @_;
      if ($transaction->notes('discard_mail')) {
        my $msg_id = $transaction->header->get('Message-Id') || '';
        $msg_id =~ s/[\r\n].*//s;
        return(OK, "Queued! $msg_id");
      }
      return(DECLINED);
    }

## Changing return values

This is an example how to use the `isa_plugin` method.

The `rcpt_ok_maxrelay` plugin wraps the `rcpt_ok` plugin. The `rcpt_ok`
plugin checks the `rcpthosts` and `morercpthosts` config files for
domains, which we accept mail for. If not found it tells the
client that relaying is not allowed. Clients which are marked as
`relay clients` are excluded from this rule. This plugin counts the
number of unsuccessfull relaying attempts and drops the connection if
too many were made.

The optional parameter `MAX_RELAY_ATTEMPTS` configures this plugin to drop
the connection after `MAX_RELAY_ATTEMPTS` unsuccessful relaying attempts.
Set to `0` to disable, default is `5`.

Note: Do not load both (`rcpt_ok` and `rcpt_ok_maxrelay`). This plugin
should be configured to run `last`, like `rcpt_ok`.

    use Qpsmtpd::DSN;

    sub init {
      my ($self, $qp, @args) = @_;
      die "too many arguments"
        if @args > 1;
      $self->{_count_relay_max} = defined $args[0] ? $args[0] : 5;
      $self->isa_plugin("rcpt_ok");
    }

    sub hook_rcpt {
      my ($self, $transaction, $recipient) = @_;
      my ($rc, @msg) = $self->SUPER::hook_rcpt($transaction, $recipient);

      return ($rc, @msg)
         unless (($rc == DENY) and $self->{_count_relay_max});

      my $count =
        ($self->connection->notes('count_relay_attempts') || 0) + 1;
      $self->connection->notes('count_relay_attempts', $count);

      return ($rc, @msg) unless ($count > $self->{_count_relay_max});
      return Qpsmtpd::DSN->relaying_denied(DENY_DISCONNECT,
              "Too many relaying attempts");
    }

## Results of other hooks

If we're in a transaction, the results of a callback are stored in

    $self->transaction->notes($code->{name})->{"hook_$hook"}->{return}

If we're in a connection, store things in the connection notes instead.
