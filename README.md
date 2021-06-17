[![Build Status][ci-img]][ci-url]
[![Coverage Status][cov-img]][cov-url]

# Qpsmtpd - qmail perl simple mail transfer protocol daemon

[Web site](http://smtpd.github.io/qpsmtpd/), [FAQ](https://github.com/smtpd/qpsmtpd/wiki/faq), [Email List](mailto:qpsmtpd-subscribe@perl.org)

Qpsmtpd is an extensible SMTP engine written in Perl. See `plugins/quit_fortune` for a cute example.

# License

Qpsmtpd is licensed under the MIT License; see the LICENSE file for
more information.

# What's new?

See the Changes file! :-)

# Installation

## Required Perl Modules

    * Net::DNS
    * MIME::Base64
    * Mail::Header (part of the MailTools distribution)

If your Perl is older than 5.8.0, you will also need

    * Data::Dumper
    * File::Temp
    * Time::HiRes

The easiest way to install modules from CPAN is with the CPAN shell.
Run it with

    perl -MCPAN -e shell

## qpsmtpd installation

Make a new user and a directory where you'll install qpsmtpd.  I
usually use "smtpd" for the user and /home/smtpd/qpsmtpd/ for the
directory.

Put the files there.  If you install from git you can just do
run the following command in the /home/smtpd/ directory.

    git clone git://github.com/smtpd/qpsmtpd.git

Beware that the master branch might be unstable and unsuitable for anything
but development, so you might want to get a specific release, for
example (after running git clone):

    git checkout -b local_branch v0.93

chmod o+t ~smtpd/qpsmtpd/ (or whatever directory you installed qpsmtpd
in) to make supervise start the log process.

Edit the file config/IP and put the ip address you want to use for
qpsmtpd on the first line (or use 0 to bind to all interfaces).

If you use the supervise tools, then you are practically done!
Just symlink /home/smtpd/qpsmtpd into your /services (or /var/services
or /var/svscan or whatever) directory.  Remember to shutdown
qmail-smtpd if you are replacing it with qpsmtpd.

If you don't use supervise, then you need to run the ./run script in
some other way.

The smtpd user needs write access to ~smtpd/qpsmtpd/tmp/ but should
not need to write anywhere else.  This directory can be configured
with the `spool_dir` configuration and permissions can be set with
`spool_perms`.

As of version 0.25 the distributed ./run script runs tcpserver with
the -R flag to disable identd lookups.  Remove the -R flag if that's
not what you want.


# Configuration

Configuration files can go into either /var/qmail/control or into the
config subdirectory of the qpsmtpd installation.  Configuration should
be compatible with qmail-smtpd making qpsmtpd a drop-in replacement.

If qmail is installed in a nonstandard location you should set the
$QMAIL environment variable to that location in your "./run" file.

If there is anything missing, then please send a patch (or just
information about what's missing) to the mailinglist or a PR to github.


# Better Performance

For better performance we recommend using "qpsmtpd-forkserver" or
running qpsmtpd under Apache 2.x.  If you need extremely high
concurrency use [Haraka](http://haraka.github.io/).

# Plugins

The qpsmtpd core only implements the SMTP protocol.  No useful
function can be done by qpsmtpd without loading plugins.

Plugins are loaded on startup where each of them register their
interest in various "hooks" provided by the qpsmtpd core engine.

At least one plugin MUST allow or deny the RCPT command to enable
receiving mail.  The `rcpt_ok` is one basic plugin that does
this.  Other plugins provide extra functionality related to this; for
example the `resolvable_fromhost` plugin described above.


# Configuration files

All the files used by qmail-smtpd should be supported; so see the man
page for qmail-smtpd.  Extra files used by qpsmtpd include:

## plugins

List of plugins, one per line, to be loaded in the order they
appear in the file.  Plugins are in the plugins directory (or in
a subdirectory of there).


## rhsbl_zones

Right hand side blocking lists, one per line. For example:

    dsn.rfc-ignorant.org does not accept bounces - http://www.rfc-ignorant.org/

See http://www.rfc-ignorant.org/ for more examples.


## `dnsbl_zones`

Normal ip based DNS blocking lists ("RBLs"). For example:

  relays.ordb.org
  spamsources.fabel.dk


## `spool_dir`

If this file contains a directory, it will be the spool directory
smtpd uses during the data transactions. If this file doesn't exist, it
will default to use $ENV{HOME}/tmp/. This directory should be set with
a mode of 700 and owned by the smtpd user.

## `spool_perms`

The default spool permissions are 0700. If you need some other value,
chmod the directory and set it's octal value in `config/spool_perms`.

## `tls_before_auth`

If this file contains anything except a 0 on the first noncomment line, then
AUTH will not be offered unless TLS/SSL are in place, either with STARTTLS,
or SMTP-SSL on port 465.

## everything (?) that qmail-smtpd supports.

In my test qpsmtpd installation I have a "config/me" file containing
the hostname I use for testing qpsmtpd (so it doesn't introduce itself
with the normal name of the server).


# Problems

In case of problems, always check the logfile first.

By default, qpsmtpd logs to log/main/current.  Qpsmtpd can log a lot of
debug information. You can get more or less by adjusting the number in
config/loglevel. Between 1 and 3 should give you a little. Setting it
to 10 or higher will get lots of information in the logs.

If the logfile doesn't give away the problem, then post to the
mailinglist (subscription instructions above).  If possible, put
the logfile on a webserver and include a reference to it in the mail.


[cov-img]: https://coveralls.io/repos/smtpd/qpsmtpd/badge.svg
[cov-url]: https://coveralls.io/r/smtpd/qpsmtpd
[ci-img]: https://travis-ci.org/smtpd/qpsmtpd.svg?branch=master
[ci-url]: https://travis-ci.org/smtpd/qpsmtpd

