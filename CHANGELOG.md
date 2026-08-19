# Changelog

Notable changes to qpsmtpd are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.02] - 2026-08-19

### Added

- SMTPUTF8 support (RFC 6531), #346, #347
- A 998 octet cap on SMTP command lines (RFC 5321 4.5.3.1.6)

### Changed

- dep(perl): 5.32 is now the floor
  - ci: drop 5.16 and 5.26 from testing
- deps: drop Mail::SpamAssassin and Math::Complex from prereq; neither is loaded
- deps(plugin): moved Mail::DMARC, Mail::SPF, Mail::DKIM, GeoIP2,
  ClamAV::Client, Redis, CDB_File, Date::Parse, File::Tail, Time::TAI64) from
  `PREREQ_PM` to `recommends`
- postfix: disable `$qid` debug output (#345)
- doc: Changes -> CHANGELOG.md

### Fixed

- `Qpsmtpd::Command`: parsing ESMTP parameters was quadratic, now linear
- uribl: the body-scanning patterns were quadratic in line length

### Security

- `Qpsmtpd::Address`: reject control characters anywhere in a path, per RFC 5321.
- `Qpsmtpd::Address::new()`: an address with a newline failed the bracket match

### Removed


## [1.01] - 2026-07-13

### Added

- hosts_allow: support IPv6 addresses (#330)
- Allow an alternate ID for the `Authentication-Results` header (#323)

### Changed

- badrcptto: always block listed recipients, even for whitelisted senders (#341)
- `Authentication-Results`: track connection and transaction results separately (#336)
- Enhance SSL context error reporting (#332)
- Test on Perl 5.38; drop GeoIP1 tests; disable geoip and dspam in the sample config (#325)
- CI: migrate to GitHub Actions and restore test coverage (#324, #328)
- postfix queue: avoid logging full message headers (#319)
- milter: document that only protocol version 2 is supported, not Rspamd/v6 (#342)

### Removed

- geoip: legacy Geo::IP support; GeoIP2 only now, with distance calculation (#335)
- Apache::Qpsmtpd and Qpsmtpd::ConfigServer (#326, #327)

### Fixed

- logging/file: guard all transaction notes access, so logging outside a transaction cannot crash (#343)
- hosts_allow: the per-IP connection limit (`max-from-ip`) in the forkserver and prefork models (#340)
- Discard the message if the client disconnects before queueing, avoiding duplicate delivery (#339)
- naughty: honor whitelists (`is_immune`) before disconnecting (#338)
- p0f: handling of IPv6 addresses in `get_v3_query` (#333)
- `received_line` hook behaviour (#312)
- Load plugins in qpsmtpd-forkserver at startup again (#311)
- whitelist: add missing `NetAddr::IP` use statement (#310)

### Security

- Extend the bare LF/CR check to every message line, mitigating SMTP smuggling (#318, #337)

## [1.00] - 2023-02-16

### Added

- Log the IP address for 535 LOGIN errors, for use with fail2ban (#301)
- whitelist: support for network ranges (#298)
- Support for userprefs' reject threshold (#281)
- Make `spammy_tlds` configurable (#255)
- karma: allow setting the number of "strikes" (#254)
- Allow setting TLS protocol versions in a config file (#252)
- spamassassin: new `size_limit` parameter (#253)
- checkip argument (#283)

### Changed

- Change GeoIP order (#297)
- Improve RPM packaging (#276-278)
- DMARC policy improvements (#260-263)
- Record the name of the original plugin (#256)
- Update the TLD list (#283)
- Update `data_post_headers` documentation (#259)

### Fixed

- Use a readable file test for certificate files (#304)
- Regex fix (#283)
- tls: a typo in `SSL_dh_file` (#275)
- badmailfromto: whitespace handling (#273)
- logging/file: "Can't call method 'notes' on unblessed reference" (#272)
- Use `eval` to get DKIM policies (#268)
- Check `$addr` is defined before using it (#266)
- karma: check for negative strikes (#265)
- Find the karma DB dir (#264)
- Check `rua` is defined before trying to parse it (#257)
- Prevent a "Use of implicit split" warning (#250)
- uribl: hook in `data_post` (#251)

### Security

- Prevent credentials being logged in plain text (#249)

## [0.96] - 2016-02-16

### Added

- dmarc: option to disable reporting (#242)
- Permissions test for `Qpsmtpd::DB::File::DBM::dir()` (#234)

### Changed

- Rename `fake_{config,hook}` to `mock_{config,hook}` (#232)
- Use a fake greeting when testing `run_continuation()` (#231)

### Fixed

- dmarc: authentication-result string (#244)
- Replace all occurrences of CR in `X-Spam-Status` (#247)
- helo: check *every* regex, not just the first (#246)
- badrcpt: use reason, and add a defined-ness test (#245)
- Skip greylisting when the greylist DB is unreachable (#233)

## [0.95] - 2015-02-11

### Added

- tls: support for Perfect Forward Secrecy (biergaizi)
- greylisting: Redis support
- `Qpsmtpd::DB` with DBM and Redis classes
- `data_post_headers` hook (priyadi)
- Preliminary support for GeoIP v2 and ASN lookups from GeoIP DBs
- Script for fetching GeoIP databases
- auth_imap plugin (Graham Todd)
- fcrdns: tests and improved localhost detection

### Changed

- Auth-Results header is no longer modified if the message is DKIM signed
- Order headers to improve SpamAssassin interaction (priyadi)
- Make the content log location configurable
- Improved IPv6 support
- Use perl DNS methods instead of shell commands
- More test coverage; tidier testing under `t/tmp/*` rather than scattershot
- Miscellaneous updates to tests and docs

### Removed

- async everything (unsupported and stagnant)

### Security

- Disable SSLv3

## [0.94] - 2014-09-05

### Added

- plugins/stunnel (luzluna)
- loadcheck: imported (Robert Siddall), returning a useful error message when temporarily rejecting connections (Priyadi)
- smtp_forward: Postfix XCLIENT support (Chase Venters)
- clamdscan: support for remote (TCP/IP) clamd (M Simerson)
- karma: spammy TLD penalty

### Changed

- Build updates for CentOS 6 (Robert Siddall)
- smtp_forward: add the remote message id to the log entry (tpoindessous)
- dmarc: use Mail::DMARC
- SPF and DKIM plugins store data for DMARC processing
- A few more log prefixes (corralling stragglers)

### Fixed

- SpamAssassin plugin fixes (Priyadi Nurcahyo)
- A config error in `Apache/Qpsmtpd.pm` (luzluna)

### Security

- auth_cvm: check for a null character in the username

## [0.93] - 2013-12-17

### Added

- `Authentication-Results` header. Inbound headers are moved to
  `Original-Authentication-Results`, and auth info is no longer placed in the
  `Received` header
- Store envelope TO/FROM in connection notes
- Run files for the most common deployment methods, for easier install
- dmarc: subdomain policy handling

### Changed

- TcpServer: ignore the DNS search path and explicitly request PTR lookups (speedup)
- clamdscan: raise the maximum message size
- SPF enabled by default, when Mail::SPF is available

### Fixed

- `Qpsmtpd.pm`: split config args on `/\s+/`, was `/ /` — compatibility with newer perls

### Security

- auth_vpopmaild: taint checking on responses
- Untaint config data passed to plugins

## [0.92] - 2013-04-20

### Added

- New plugins: dmarc, fcrdns
- DKIM message signing, with a script for generating DKIM selectors, keys and
  DNS records. See `perldoc plugins/dkim`. RAM was raised to 300MB to avoid
  memory exhaustion errors
- tls: ability to store SSL keys in `config/ssl`
- log2sql: UPDATE query support
- geo_ip: `too_far` option, deducting karma from distant senders
- bogus_bounce: Return-Path check, per RFC 3834

### Changed

- helo: cease processing DNS records after the first positive match
- karma: awards sprinkled throughout other plugins — limit poor-karma hosts to
  one concurrent connection, allow +3 concurrent connections to good-karma
  hosts, and limit recipients to one for senders with negative karma
- `is_naughty` removed from the `is_immune` feature, allowing more granular
  handling by plugins

### Removed

- FAQ, moved to <https://github.com/qpsmtpd-dev/qpsmtpd-dev/wiki/faq>

### Fixed

- Net::DNS breakage (Markus Ullmann)
- SPF: rearrange logic to improve the reliability of SPF pass reporting, which
  helps the dmarc plugin

### Security

- `Qpsmtpd.pm`: untaint config options before passing them to plugins
- auth_vpopmaild: untaint responses obtained from the network. Combined with the
  config taint fix, this lets auth_vpopmaild work when setting host and port
- Sanitize the `spamd_sock` path for perl taint mode (Markus Ullmann)

## [0.91] - 2012-11-20

### Added

- whitelist plugin
- dkim plugin, superseding domainkeys
- `Plugins::adjust_karma`, reducing code requirements in other plugins
- spamassassin: `headers none` option
- qmail_deliverable: vpopmail extension support, and rejection of null senders
  to ezmlm mailing lists
- helo: `is_plain_ip` added to the lenient checks
- log2sql, `log/watch.pl`, `log/summarize.pl` and `plugins/registry.txt`

### Changed

- A handful of minor log message changes, similar to 0.90
- clamdscan: skip processing of naughty messages
- TcpServer: improved IPv6 support (Michael Holzt)
- SPF: improved IPv6 support; `is_in_relayclient` replaced by a check of whether
  the `relayclient()` note is set
- dnsbl, rhsbl: rejections handled by the naughty plugin
- Default loglevel changed from 9 to 6
- `config.sample/plugins` ordered roughly by SMTP phase
- dspam improvements

### Deprecated

- domainkeys plugin, superseded by dkim

### Fixed

- Replace all instances of `split ''` with `split //`, required for perl 5.1x
- Allow messages with no body (Robin's patch)

## [0.90] - 2012-06-27

### Added

- qmail_deliverable plugin, which depends on Qmail::Deliverable
- karma plugin
- naughty plugin
- dspam plugin (Matt Simerson)
- check_bogus_bounce plugin (Steve Kemp)
- auth_vpopmaild plugin (Robin Bowes)
- auth_checkpassword plugin (Matt Simerson)
- connection_time: tcpserver deployment compatibility
- check_basicheaders: new `past`, `future`, `reject` and `reject_type` arguments

### Changed

- Many logging adjustments across plugins, working toward one message per plugin
  summarising that plugin's actions and outcomes
- dnsbl, rhsbl: process DNS queries synchronously, improving overall efficiency
- uribl, domainkeys, spamassassin: insert headers at the top of the message, for
  consistent SMTP behaviour
- spamassassin: consolidate two `data_post` methods, for a more linear and
  simpler flow
- Rewrote `check_basicheaders` as `headers`
- Renamed `check_loop` to `loop`, `check_badrcptto` to `badrcptto`,
  `check_badmailfromto` to `badmailfromto`, and `check_badmailfrom` to
  `badmailfrom`
- sender_permitted_from — see UPGRADING (Matt Simerson)
- p0f version 3 supported, and now the default — see UPGRADING (Matt Simerson)
- resolvable_fromhost ignores the DNS search path, expecting fully resolved
  domains (Robert Spier, Charlie Brady)
- auth_vpopmail_sql: more flexible database config (Matt Simerson)
- clamav: add the ClamAV version to the `X-Virus-Checked` header, and note when
  no virus was found (Matt Simerson)
- Assorted documentation cleanups (Steve Kemp, Robert Spier)
- Revert "Spool body when `$transaction->body_fh()` is called"

### Removed

- check_badmailfrom_patterns, merged into check_badmailfrom
- check_badrcptto_patterns, merged into check_badrcptto

### Fixed

- count_unrecognized_commands: variable assignment error
- loop: `max_hops` was sometimes unset

## [0.84] - 2010-04-07

### Added

- rpm: create `.rpm` files from the `packaging/rpm` directory (Peter J. Holzer,
  Robin Bowes, Filippo Carletti, Richard Siddell)
- spamassassin: custom spam tag subject munging (Jonathan Martens, Robert Spier)

### Changed

- exim: use BSMTP response codes, plus various cleanups (Devin Carraway)
- config: cache returned values from config plugins (Peter J. Holzer)
- resolvable_fromhost: move the DENYSOFT for `temp_resolver_failed` to the
  RCPT TO hook (Larry Nedry)
- Note the Net::IP dependency (Larry Nedry)
- Various minor spelling cleanups and such (Steve Kemp, Devin Carraway)

### Fixed

- uribl: the `scan-headers` option (Jost Krieger, Robert Spier)
- AUTH PLAIN bug with Alpine (Rick Richard)
- clamav: typo in the name of the default configuration file (Filippo Carletti)

## [0.83] - 2009-09-15

### Added

- `dup_body_fh` method, returning a dup'd body filehandle (Jared Johnson)

### Changed

- virus/clamav: modify the `no-summary` option for ClamAV 0.95 (Jonathan Martens)
- clamd: temporarily deny if clamd is not running (Shad L. Lords)
- rhsbl: disconnect the host (Charlie Brady)
- check_spamhelo: disconnect after denying a HELO (Filippo Carletti)
- POD cleanups (Steve Kemp)

### Fixed

- queue/maildir: allow hyphens in the maildir path (Hinrik Örn Sigurðsson)
- spamassassin: log noise when the spam score is 0.0
- `spool_dir` configuration documentation, and a README update (Tomas Lee)
- check_badmailfrom: parsing of reason messages and similar (Robert Spier, Tomas Lee)
- Log even when not in a transaction (Jared Johnson)
- prefork: more robust child spawning (Peter Samuelson)

## [0.82] - 2009-06-02

### Added

- prefork: multi-address support
- prefork: support `--listen-address`, for consistency with forkserver

### Changed

- clamdscan now requires the ClamAV::Client perl module instead of the older,
  deprecated Clamd module (Devin Carraway)

### Fixed

- prefork: processes were sometimes "left behind" (Charlie Brady)
- prefork: startup when no interface addresses are specified (Devin Carraway)

### Security

- prefork: sanitize the shell environment before loading modules

## [0.81] - 2009-04-02

### Added

- logging/apache plugin, for logging to the Apache error log
- connection_time plugin
- rcpt_regexp plugin (Hanno Hecker)
- `notes` method on `Qpsmtpd::Address` objects (Jared Johnson)
- `remove_recipient` method on the transaction object (Jared Johnson)
- Git information in the version number when running from a git clone

### Changed

- p0f plugin updates (Tom Callahan)
- `transaction->add_recipient` skips adding a "null" recipient if passed one

### Fixed

- Close the spamd socket after reading the result back (Jared Johnson)

## [0.80] - 2009-02-27

### Added

- `data_headers_end` hook, fired at the end of headers
- Random error plugin
- async: `$connection->local_ip` and `$connection->local_port`
- async: pre- and post-connection hooks
- async versions of the dns_whitelist_soft, rhsbl and uribl plugins
- apache: post-connection hook, and `connection->reset`
- queue/maildir: multi user / multi domain support, and the `Return-Path` header
  is now set when queueing into maildir mailboxes
- prefork, forkserver: restart on SIGHUP, reloading all modules with their
  `register()` or `init()` phase
- prefork: `--detach` option to daemonize like forkserver; user/group switching
  from forkserver, to support secondary groups as needed by
  `plugins/queue/postfix-queue`; `--pid-file` now works
- Allow plugins to use the `post-fork` hook
- New config option `spool_perms`, setting the permissions of `spool_dir`
  (Jared Johnson)

### Changed

- Development moved to a git repository
- Reorganized plugin author documentation
- Improve logging of plugins generating fatal errors (Steve Kemp)
- Lower the log level of rcpt/from addresses
- prefork: improve shutdown of parent and children on very busy systems
  (Diego d'Ambra)
- prefork: exit codes cleanup (based on a patch by Diego d'Ambra)
- async, prefork: detach and daemonize only after reading the configuration and
  loading the plugins, giving init scripts a chance to detect startups that
  failed due to broken configuration or plugins (Diego d'Ambra)
- Improve handling of inetd/xinetd connections (Hanno Hecker)
- `Qpsmtpd::Connection->notes` are now reset at the end of a connection,
  currently excepting Apache. The `plugins/tls` workaround for -prefork is no
  longer needed
- Keep the square brackets around the IP as `remote_host` when the reverse
  lookup fails (Hanno Hecker)
- Add qpsmtpd-prefork to the install targets (Robin Bowes)
- Address definitions are now package variables and can be overridden by sites
  that wish to change the definition of an email address (Jared Johnson) —
  see <http://groups.google.com/group/perl.qpsmtpd/browse_thread/thread/35e3a187d8e75cbe>
- Leading and trailing whitespace in config files is ignored (Henry Baragar)

### Removed

- Outdated virus/check_for_hi_virus plugin

### Fixed

- async: the body_file/body_filename would not have headers
- async: dereference the DATA deny message before sending it to the client
- async: handle an end-of-data marker split across packets
- async/resolvable_fromhost: match the logic of the non-async version and of
  other MTAs
- prefork: detect and reset locked shared memory (based on a patch by Diego d'Ambra)
- prefork: the children pool size was sometimes not adjusted immediately after
  children exited (reported by Diego d'Ambra)
- plugins/tls: close the file descriptor for the SSL socket
- plugins/resolvable_fromhost: check all MX hosts, not just the first

### Security

- prefork: untaint the value of the `--interface` option (reported by Diego d'Ambra)

## [0.43] - 2008-02-05

Never officially released. Mostly the work of Matt Sergeant and Hanno Hecker.

### Added

- Hook and plugin caching
- Pluggable "help", based on a patch by Jose Luis Martinez
- clamdscan: option to scan all messages, even when there are no attachments
- clamdscan: new `clamd_user` parameter, setting the user passed to clamd
- async: support for HUPing the server to clear the cache, and wake-one child support
- Allow qpsmtpd-async to detach (Chris Lewis)

### Changed

- Implement config caching properly, for async
- async: no longer listen for readiness in the parent, which broke under high load
- `user()` and `host()` in `Qpsmtpd::Address` are now setters as well as getters,
  as suggested by mpelzer@gmail.com
- Updated plugin documentation

### Removed

- Connection / transaction id feature, which was never released

### Fixed

- plugins/tls: workaround for failed connections in -prefork after a STARTTLS
  connection (Stefan Priebe, Hanno Hecker)
- postfix: make the cleanup socket location parameter work (ulr...@topfen.net)

## [0.42] - 2007-10-01

Never released.

### Added

- Pluggable `noop` hook
- Pluggable `help` hook, based on a patch by Jose Luis Martinez
- `docs/plugins.pod` documentation
- spamassassin: `X-Spam-Level` header (idea from Werner Fleck)
- prefork: support two or more parallel running instances, on different ports.
  The first four digits of the port number must differ for each instance — see
  IPC::Sharable
- `connection->local_ip` is available from the Apache transport (Peter Eisch)
- Support checking for early talkers at DATA
- Allow buffered writes in the Postfix plugin (from Joe Schaefer)
- uribl plugin (Devin Carraway)

### Changed

- async: better config caching, of flat files rather than results from
  `hook_config` or `.cdb` files; send SIGHUP to clear the cache
- POD syntax cleanup (Steve Kemp)
- Cleanup of the spamassassin plugin code
- Updated documentation, covering Apache 2.2 and more

### Removed

- auth/authnull sample plugin. There are plenty of proper examples now, so this
  insecure plugin need not be shipped

### Fixed

- prefork: sporadic bug appearing after millions of connections (S. Priebe)
- `Qpsmtpd::Plugins::isa_plugin()` with multiple plugin dirs (Gavin Carr)
- False positives in the check_for_hi_virus plugin (Jerry D. Hedden)
- Make the documented `DENY{,SOFT}_DISCONNECT` work in the `data-post` hook
- Bug which broke queue plugins that implement continuations
- Unrecognized command fix (issue #16)

## [0.40] - 2007-06-11

### Added

- async server, using epoll/kqueue/poll where available (Matt Sergeant)
- Preforking qpsmtpd server (Lars Roland)
- SMTPS support (John Peacock)
- IPv6 support (Mike Williams)
- Support for "module" plugins, e.g. `My::Plugin` in the `plugins` config file
- Pluggable Received headers (Matt Sergeant)
- RFC 3848 support for ESMTP (Nick Leverton)
- Tests for the rcpt_ok plugin (Guy Hulbert, issue #4)
- badmailfrom: optional rejection messages after the rejection pattern
  (Robin Hugh Johnson)
- Support for multiple plugin directories, whose paths are given by the
  `plugin_dirs` configuration (Devin Carraway, Nick Leverton)
- `Qpsmtpd::Postfix::Constants`, encapsulating all current Postfix return codes,
  plus a script to generate it (Hanno Hecker)
- Ability to specify a socket for syslog (Peter Eisch)
- relay_only plugin, for a smart relay host (John Peacock)
- spamassassin: support for connecting to a remote spamd process (Kjetil Kjernsmo)
- domainkeys plugin (John Peacock)
- SSL encryption method in the header, mirroring other qmail/SSL patches, and
  `tls_before_auth` to suppress AUTH unless TLS is already established
  (Robin Johnson)
- `Qpsmtpd::Command`, gathering all parsing logic in one place (Hanno Hecker)
- Support for multiline responses from plugins (Charlie Brady)
- `queue_pre` and `queue_post` hooks (John Peacock)
- Multiple host/port listening for qpsmtpd-forkserver (Devin Carraway)
- prefork: `--pretty` option to change `$0` for child processes (John Peacock)

### Changed

- Don't drop privileges in forkserver if we don't have to
- Update the sample configuration to use zen.spamhaus.org
- Updated the list of DNSBLs in the default config
- Ignore lines in `config/plugins` for uninstalled plugins, instead of failing
  with a cryptic message (John Peacock)
- Clean up some of the logging (hjp)
- Greylisting DBs may now be stored in a configured location, and are looked for
  by default in `/var/lib/qpsmtpd/greylisting` in addition to the previous
  locations relative to the qpsmtpd binary (Devin Carraway)
- clamdscan: temporarily deny mail if it can't talk to clamd (Filippo Carletti)
- Move the `Qpsmtpd::Auth` POD to a top-level README, to be more obvious
- Improve `Qpsmtpd::Transaction` documentation (Fred Moyer)

### Deprecated

- The ill-named `$transaction->body_size()`. Use `$transaction->data_size()`
  instead; check your logs for LOGWARN messages about `body_size` and fix your
  plugins (Hanno Hecker)

### Fixed

- Logging when dropping a mail due to size (m. allan noah / kitno455, issue #13)
- greylisting: the `db_dir` configuration option now actually works
  (kitno455, issue #6)
- Header parsing of "space only" lines (Joerg Meyer, issue #11)
- Do the right thing for unimplemented AUTH mechanisms (Brian Szymanski)
- The `help` command when no `smtpgreeting` is configured, which is the default
  (thanks to Thomas Ogrisegg)
- Spurious newline at the start of messages queued via exim (Devin Carraway)
- prefork: patch to make it run (Leonardo Helman)

## [0.32] - 2006-02-26

### Added

- logging/file plugin, for simple logging to a file (Devin Carraway, Peter J. Holzer)
- logging/syslog plugin, for logging via the syslog facility (Devin Carraway)
- `Qpsmtpd::DSN`, returning extended SMTP status codes from RFC 1893, with
  existing plugins patched to use it where appropriate (Hanno Hecker)
- plugins/tls_cert, generating appropriately shaped self-signed certs for TLS
  support, with explicit use of the CA used to sign the cert, and abstracted
  cloning of connection information when switching to TLS
- hosts_allow plugin, supporting pre- and post-connection hooks and moving the
  `--max-from-ip` tests out of core (Hanno Hecker)

### Changed

- postfix-queue: support the known processing flags (Hanno Hecker)

### Fixed

- AUTH now works correctly with TLS
- A few fixes to the clamdscan plugin (Dave Rolsky)
- Various minor fixes and improvements

### Security

- Drop root privileges before loading plugins, rather than after

## [0.31.1] - 2005-11-18

### Fixed

- Add missing files to the distribution — the exim plugin, the tls plugin and
  various sample configuration files (thanks Budi Ang!)

## [0.31] - 2005-11-16

### Added

- STARTTLS support, see `plugins/tls`
- queue/exim-bsmtp plugin, spooling accepted mail into an Exim backend via
  BSMTP (Devin Carraway)
- New plugin inheritance system, see the bottom of README.plugins
- qpsmtpd-forkserver: `--listen-address` may now be given more than once, to
  request listening on multiple local addresses (Devin Carraway)
- qpsmtpd-forkserver: option for writing a PID file (pjh)
- qpsmtpd-forkserver: `-d` / `--detach` to detach from the controlling terminal
  and daemonize (Devin Carraway)
- Example patterns for the badrcptto plugin (Gordon Rowell)
- resolvable_fromhost: a configurable list of "impossible" addresses, to combat
  spammer forging (Hanno Hecker)
- `$QPSMTPD_CONFIG` environment variable. When set, qpsmtpd looks for its config
  files in that directory in addition to, and in preference to, other locations,
  overriding `$QMAIL/control` and `/var/qmail/control`. The usual "last location
  with the file wins" rule still applies (Peter J. Holzer)

### Changed

- Use `qmail/control/smtpdgreeting` if it exists, otherwise show the original
  qpsmtpd greeting with version information
- Refactor `Qpsmtpd::Address`
- When disconnecting with a temporary failure, return 421 rather than 450 or 451
  (Peter J. Holzer)
- The `unrecognized_command` hook now uses `DENY_DISCONNECT` to disconnect the user
- Replace some fun SMTP comments with boring ones
- Updated documentation, and various minor cleanups

### Fixed

- qpsmtpd-forkserver: no more signal problems making it crash or loop when forking
- qpsmtpd-forkserver: set auxiliary groups. This is needed for the postfix
  backend, which expects write permission on a fifo that usually belongs to
  group postdrop (pjh)

## [0.30] - 2005-07-05

### Added

- Pluggable logging support, including a sample plugin replicating the existing
  core code, plus an OK hook. See README.logging for information about the new
  logging system (John Peacock)
- logging/adaptive plugin, logging at different levels depending on whether the
  message was accepted or rejected
- plugins/auth/auth_ldap_bind, authenticating against an LDAP database
  (thanks to Elliot Foster <elliotf@gratuitous.net>)
- plugins/auth/auth_flat_file, a flat file auth plugin
- plugins/auth/auth_cvm_unix_local, which only DENYs when the credentials were
  accepted but incorrect. Interfaces with Bruce Guenther's Credential
  Validation Module (CVM)
- plugins/check_badrcptto_patterns, matching bad RCPT TO addresses with a
  regex (Gordon Rowell)
- plugins/check_norelay, carving holes out of larger relay blocks (Gordon Rowell)
- plugins/virus/sophie, using SOPHOS Antivirus via the Sophie resident daemon

### Changed

- Revamp `Qpsmtpd::Constants` so the text representation can be retrieved from
  the numeric one, for logging purposes
- Store mail in memory up to a certain threshold, 10k by default
- Remove a needless restriction on `temp_file()`, allowing the spool directory
  path to include dots, as in `../`
- Don't check the HELO host for rfc-ignorant compliance
- Update `Apache::Qpsmtpd` to work with the latest Apache/mod_perl 2.0 API
- Replace `$ENV{RELAYCLIENT}` with `$connection->relay_client` in the last plugin

### Fixed

- Off-by-one line numbers in warnings from plugins (thanks to Brian Grossman)
- `body_write` patches from Brian Grossman
- Corruption problem under Apache, plus various bucket issues
- Typo in the qpsmtpd-forkserver commandline help

## [0.29] - 2005-03-03

### Added

- New anti-virus scanners: hbedv (Hanno Hecker), bitdefender and clamdscan
  (John Peacock)
- `temp_file()` and `temp_dir()` methods, creating a filename or directory that
  lasts only as long as the current transaction, plus a `spool_dir()` method
  that checks and creates the spool dir at startup. All three are also available
  in the base class, where the temp objects are not limited to the transaction's
  lifetime (John Peacock)
- Gavin Carr's greylisting plugin
- check_badmailfromto plugin, like check_badmailfrom but matching both FROM: and
  TO:, effectively making the recipient seem not to exist for that sender —
  useful for harassment cases (John Peacock)
- dns_whitelist_soft plugin, a DNS-based whitelist override for other qpsmtpd
  plugins, plus `whitelisthost` support in dnsbl (John Peacock)
- auth/auth_vpopmail_sql: CRAM-MD5 support, requiring `clear_passwd` (John Peacock)
- Support for qmail-smtpd's `timeoutsmtpd` config file
- Plugin testing framework (Matt)
- `Apache::Qpsmtpd`, an Apache/mod_perl 2.0 connection handler, added to the distro
- Support for multiple instances of a single plugin, using the `plugin:0`
  notation (Robert)
- VRFY plugin support (Robert Spier)
- `Makefile.PL` and friends, to make packaging easier (Matt)
- plugin/virus/uvscan, the McAfee commandline virus scanner
- `Qpsmtpd::Auth` — authentication handlers, see `plugins/auth/` (John Peacock)
- Plugin hook for the DATA command
- earlytalker: optionally react to an early talker by denying all MAIL FROM
  commands rather than issuing a 4xx/5xx greeting and disconnecting
  (Mark Powell); configurable initial "awkward silence" period (Mark Powell);
  configurable DENY/DENYSOFT
- `relay_client()` method on `Connection.pm` (John Peacock)

### Changed

- Store the entire incoming message in the spool file, so scanners can read the
  complete message, and ignore old headers before adding lines and queueing for
  delivery
- clamav: scan the spool file directly
- Renamed `config/` to `config.sample/`
- `Qpsmtpd::Auth`: document the `$mechanism` option, improve the fallback to
  generic hooks, document that auth-login works now, and stash the auth user and
  method for later use by `Qpsmtpd::SMTP` to generate the authentication header
  (Michael Toren)
- `Qpsmtpd::SMTP`: `MAIL FROM: <#@[]>` now works like qmail's null sender; LOGIN
  added to the default auth mechanisms; the auth user and method are displayed in
  the `Received:` line instead of an `X-Qpsmtpd-Auth` header (Michael Toren)
- earlytalker and resolvable_fromhost: short circuit the test if `whitelistclient`
  is set (Michael Toren)
- check_badmailfrom: do not say why a given message is denied (Michael Toren)
- queue/qmail-queue: add a timestamp and the qmail-queue `qp` identifier to the
  "Queued!" message, for compatibility with qmail-smtpd (Michael Toren)
- Many improvements to the forking server, qpsmtpd-forkserver
- Make the distro follow the CPAN module style — `Makefile.PL`, `MANIFEST` and so on
- rhsbl: do DNS lookups in the background (Mark Powell)
- maildir: record who the message was to. With a bit more work this could make a
  decent local delivery plugin
- Pass extra "stuff" to the HELO/EHLO callbacks, to make it easier to support
  SMTP extensions
- Renamed the `*HARD` return codes to `DENY_DISCONNECT` and
  `DENYSOFT_DISCONNECT`; `DENYSOFT_DISCONNECT` is new
- Mail::Address does RFC 822 addresses and we need SMTP addresses, so replace it
  with Peter J. Holzer's `Qpsmtpd::Address` module
- Include the date and time the session started in the process status line
- Inbound connections are logged as soon as the remote host address is known,
  when running under tcpserver
- Move the relay flag to the connection object; `$transaction->relaying()`
  removed completely, due to popular demand (John Peacock)
- Split the check_relay plugin in two: check_relay now fires on connect and sets
  the `relay_client()` flag, while rcpt_ok runs last of the rcpt plugins and
  performs the final OK/DENY. The default `config/plugins` reflects the new
  order (John Peacock)

### Fixed

- CDB support, so the server can work without it
- Warning in the count_unrecognized_commands plugin (thanks to spaze and
  Roger Walker)
- Improve error messages from the Postfix module
  (Erik I. Bolsø <knan at mo.himolde.no>)
- Don't keep adding IP addresses to the process status line (`$0`) when running
  under PPerl

## [0.28] - 2004-06-05

### Added

- queue/maildir plugin, for writing incoming mail to a maildir
- Proper log levels, with a configuration option
- `$Include` feature in `config/plugins`

### Changed

- Include the date and time the session started in the process status line

### Fixed

- Don't keep adding IP addresses to the process status line (`$0`) when running
  under PPerl
- Warning in the check_badrcptto plugin (thanks to Robert James Kaes)

### Security

- Create temp files with permissions 0600 (thanks again to Robert James Kaes)

## [0.27.1] - 2004-03-11

### Fixed

- spamassassin: Outlook compatibility (thanks to Gergely Risko)

## [0.27] - 2004-03-10

### Added

- Support for unix sockets in the spamassassin plugin, requiring SA 2.60 or
  higher (thanks to John Peacock!)
- Postfix queue plugin (thanks to Peter J Holzer!)
- milter plugin, allowing use of sendmail milters
- SPF plugin, sender permitted from
- qpsmtpd-server, a `select()` based server for qpsmtpd
- `config/relayclients` and `config/morerelayclients` files defining who can
  relay, useful with the `select()` server
- POD documentation and config sanity checking in check_badmailfrom
- `$ENV{QMAIL}` to override `/var/qmail` when locating the `control/` directory

### Changed

- dnsbl: better support for both A and TXT records, and support for all of the
  RBLSMTPD functionality (thanks to Mark Powell)
- Make the SpamAssassin plugin work with SA 2.6+ (thanks to numerous
  contributors!). Note that for now it does not include the `Spam:` headers with
  the score explained — for that, use the spamassassin_spamc plugin from
  <http://projects.bluefeet.net/>
- Took out the last `exit` call from the SMTP object; the transport module,
  `TcpServer` or `SelectServer`, needs to do the right thing in its `disconnect`
  method
- Update the SPF plugin (Philip Gladstone, philip@gladstonefamily.net):
  integrated with Mail::SPF::Query 1.991, skip SPF processing when acting as a
  relay system, and remove the MX changes now that they live inside
  Mail::SPF::Query
- Say `Received: ... via ESMTP` instead of `via SMTP` when the client speaks
  ESMTP, in the hope this makes a useful SpamAssassin rule
- Enable earlytalker in the default plugins config
- Speed up persistent qpsmtpd instances by checking for plugin functions after
  munging the name; the main breakage was with queue/qmail-queue
- Use `dup2()` instead of perl's `open("<&")` style, as POSIX seems to work better

### Removed

- Data::Dumper, saving a few bytes of memory
- The `X-SMTPD` header

### Fixed

- count_unrecognized_commands under PPerl; it was not resetting the count properly
- `reset_transaction` is now called after the disconnect plugins, so the
  transaction object's DESTROY method is called (thanks to Robert James Kaes
  <rjkaes@flarenet.com>)
- Don't store the Qpsmtpd object in the Plugin object any more; this caused a
  circular reference
- qpsmtpd was unfolding all header lines

### Security

- Reject bare carriage returns in addition to bare line feeds (based on a patch
  from Robert James Kaes, thanks!)

## [0.26] - 2003-06-11

### Added

- queue/smtp-forward plugin (Matt Sergeant)
- Plugins running the `ehlo` hook may add to the ARRAY reference
  `$self->transaction->notes('capabilities')`, and the entries will be added to
  the EHLO response
- `command_counter` method on the SMTP object. Plugins can use this to catch, or
  not catch, consecutive commands — particularly useful with the
  `unrecognized_command` hook
- `unrecognized_command` hook and a count_unrecognized_commands plugin
  (Rasjid Wilcox)
- earlytalker plugin, denying the connection if the client talks before the SMTP
  banner is shown (from Devin Carraway)
- `Qpsmtpd::SMTP` patched to allow connect plugins to give DENY and DENYSOFT
  return codes, based on a patch from Devin Carraway
- Support for `morercpthosts.cdb`
- `config` now takes an extra "type" parameter. When it is `map`, a reference to
  a tied hash is returned

### Changed

- Add documentation to `Qpsmtpd::Transaction` (Matt Sergeant)
- qmail-queue: add the message-id to the "Queued!" message returned to the
  client, to help those odd sendmail-using people debug their logs
- Set the process name to `qpsmtpd [1.2.3.4 : host.name.tld]`

### Fixed

- dnsbl: bug that made it sometimes ignore hits (thanks to James H. Thompson
  <jht@lava.net>)
- Error message was hidden when an existing configuration file was not readable
- Don't break under taint mode on OpenBSD (thanks to Frank Denis / Jedi/Sector One)
- Timeout bug when the client sent DATA and then stopped before sending the next
  line (Gergely Risko <risko@risko.hu>)

### Security

- Filter out all uncommon characters from the `remote_host` setting (thanks to
  Frank Denis / Jedi/Sector One for the hint)
- Check that `spool_dir` has mode 0700

## [0.25] - 2003-03-18

### Added

- queue/qmail-queue: option to specify an alternate qmail-queue location (Rasjid)
- Support for the `QMAILQUEUE` environment variable (Rasjid)
- PPerl compatibility (Rasjid)
- `deny` hook, called when another hook returns DENY or DENYSOFT (Rasjid)
- Plugin hooks for HELO and EHLO (Devin Carraway <qpsmtpd-list@devin.com>)
- check_spamhelo plugin, denying mail from claimed senders in the list specified
  in `badhelo` — for example aol.com or yahoo.com (Devin Carraway)

### Changed

- Print the date in the local timezone instead of `-0000`. Not entirely convinced
  this is a good idea
- Allow mail to `<abuse>` and `<postmaster>` to go through (Rasjid)
- Add the list of required modules to the README (thanks to Skaag Argonius
  <skaag@skaag.net>)
- Disable identd lookups by passing `-R` to tcpserver (thanks to Matt)

### Fixed

- Use the proper RFC 2822 date format in the Received headers. Somehow I had
  convinced myself that ISO 8601 dates were okay (thanks to Kee Hinckley
  <nazgul@somewhere.com>)
- Error handling in queue/qmail-queue (Rasjid)
- dnsbl: give us all the results (patch from Matt Sergeant <matt@sergeant.org>)

## [0.20] - 2002-12-09

### Added

- spamassassin: `munge_subject_threshold` and `reject_threshold` options, plus
  documentation
- clamav plugin (thanks to Matt Sergeant, matt@sergeant.org). Enabling this may
  require raising the `softlimit` in the run file — see <http://www.clamav.org/>
- content_log plugin, logging the content of all mail for debugging
  (Robert Spier <robert@perl.org>)
- http_config plugin, fetching configuration via HTTP
- Plugins can take arguments via their line in the `plugins` file

### Changed

- Store hooks runtime config globally, so it works within the transaction objects too

### Fixed

- The "too many dots in the beginning of the line" bug
- Add `-p` to mkdir in `log/run` (Rasjid Wilcox <rasjidw@openminddev.net>)
- spamassassin no longer stops the next content plugins from running
- quit_fortune: check that the fortune program exists

## [0.12] - 2002-10-17

### Changed

- Better error messages when a plugin fails
- Remove some debug messages from the log
- Better installation instructions, and a better error message when no plugin
  allowed or denied relaying (thanks to Lars Rander <lrNOSPAM@rander.dk>)

### Fixed

- NOOP command with perl 5.6
- Use `/usr/bin/perl` instead of the non-standard `/home/perl/bin/perl`

## [0.11] - 2002-10-09

### Added

- `queue` plugin hook, with the qmail-queue functionality moved to
  `plugins/queue/qmail-queue`. This allows qpsmtpd to deliver mail via SMTP or
  LMTP, into a database, or whatever else you want
- `spool_dir` option (thanks to Ross Mueller <ross@visual.com>)
- check_badmailfrom and check_badrcptto plugins
  (Jim Winstead <jimw@trainedmonkey.com>)

### Changed

- Reorganize most of `Qpsmtpd.pm` into `Qpsmtpd/SMTP.pm`
- Add the plugin name to the `hooks` data structure, so the plugin module can be
  logged when a hook errors
- dnsbl: queue lookups in the background on connect, and don't block for the
  results until they are needed, greatly speeding up connection times

### Fixed

- Make the klez filter run for mail bigger than 220KB; they are sometimes bigger
  than that
- Avoid a "use of uninitialized variable" warning when the MAIL or RCPT command
  is executed without a parameter
- Compatibility with perl 5.5.3
- "Could not print" error message in the TcpServer object (thanks to Ross Mueller
  <ross@visual.com>)
- A typo in the dnsbl plugin, so it will actually work
- Better RFC conformance: reset transactions after the DATA command, and when the
  MAIL command is issued

## [0.10] - 2002-09-08

### Added

- Very flexible plugin system

### Changed

- New object oriented internals
- All functionality not core to SMTP moved to plugins
- Can accept mail as large as the file system allows, instead of as much memory
  as you would allow qpsmtpd to eat

## Earlier development (2002)

Work predating the 0.10 rewrite, recorded by date in the original `Changes`.

### 2002-09-08

- Added: klez_filter plugin
- Added: support for more return codes for `data_post`
- Added: `plugin_name` method on the default plugin object
- Changed: document `data_post`
- Changed: add the plugin name to log entries when plugins use `log()`
- Changed: improve error handling in the spamassassin plugin

### 2002-08-06

- Added: API to read the message body, undocumented and subject to change
- Added: `data_post` hook, undocumented
- Added: SpamAssassin plugin, connecting to spamd on localhost — see
  `plugins/spamassassin`
- Changed: spool message bodies to a tmp file, so HUGE messages are supported

### 2002-07-15

- Added: DNS RBL and RHSBL support via plugins
- Added: more hooks

### 2002-07-03

- Added: first, non-functional version of the new object oriented mail engine (0.10)

## [0.07] - 2002-04-20

The last releases on the old v0.0x branch.

### Added

- Support for comments in configuration files, prefixing the line with `#`
- Support for `RELAYCLIENT` like qmail-smtpd (thanks to Marius Kjeldahl
  <marius@kjeldahl.net> and Zukka Zitting <jukka.zitting@iki.fi>)

### Fixed

- If the connection failed while in DATA we would just accept the message. Ouch!
  Thanks to Devin Carraway <qpsmtpd@devin.com> for the patch

## Pre-0.07 (2002)

### 2002-05-09

- Added: klez filter (thanks to Robert Spier)

### 2002-01-26

- Fixed: allow `[1.2.3.4]` for the hostname when checking if the DNS resolves

### 2002-01-21

- Added: make the MAIL FROM host DNS check configurable (thanks to Devin Carraway)
- Changed: add more documentation to the README file
- Fixed: assorted fixes; getting DNSBLs to actually work
- Fixed: the maximum message size (`databytes`) handling (thanks for the spot to
  Andrew Pam <xanni@glasswings.com.au>)
- Security: support and enable taint checking (thanks to Devin Carraway
  <qpsmtpd@devin.com>)

[Unreleased]: https://github.com/smtpd/qpsmtpd/compare/v1.02...HEAD
[1.02]: https://github.com/smtpd/qpsmtpd/compare/v1.01...v1.02
[1.01]: https://github.com/smtpd/qpsmtpd/compare/v1.00...v1.01
[1.00]: https://github.com/smtpd/qpsmtpd/compare/v0.96...v1.00
[0.96]: https://github.com/smtpd/qpsmtpd/compare/v0.95...v0.96
[0.95]: https://github.com/smtpd/qpsmtpd/compare/v0.94...v0.95
[0.94]: https://github.com/smtpd/qpsmtpd/compare/v0.93...v0.94
[0.93]: https://github.com/smtpd/qpsmtpd/compare/v0.84...v0.93
[0.84]: https://github.com/smtpd/qpsmtpd/compare/v0.83...v0.84
[0.83]: https://github.com/smtpd/qpsmtpd/compare/v0.82...v0.83
[0.82]: https://github.com/smtpd/qpsmtpd/compare/v0.81...v0.82
[0.81]: https://github.com/smtpd/qpsmtpd/compare/v0.80...v0.81
[0.80]: https://github.com/smtpd/qpsmtpd/compare/v0.40...v0.80
[0.40]: https://github.com/smtpd/qpsmtpd/compare/v0.32...v0.40
[0.32]: https://github.com/smtpd/qpsmtpd/compare/v0.31.1...v0.32
[0.31.1]: https://github.com/smtpd/qpsmtpd/compare/v0.31...v0.31.1
[0.31]: https://github.com/smtpd/qpsmtpd/compare/v0.30rc1...v0.31
[0.30]: https://github.com/smtpd/qpsmtpd/compare/v0.29...v0.30rc1
[0.29]: https://github.com/smtpd/qpsmtpd/compare/v0.28...v0.29
[0.28]: https://github.com/smtpd/qpsmtpd/compare/v0.26...v0.28
[0.26]: https://github.com/smtpd/qpsmtpd/compare/v0.25...v0.26
[0.25]: https://github.com/smtpd/qpsmtpd/compare/v0.20...v0.25
[0.20]: https://github.com/smtpd/qpsmtpd/compare/v0.12...v0.20
[0.12]: https://github.com/smtpd/qpsmtpd/compare/v0.11...v0.12
[0.11]: https://github.com/smtpd/qpsmtpd/compare/v0.10...v0.11
[0.10]: https://github.com/smtpd/qpsmtpd/compare/v0.07...v0.10
[0.07]: https://github.com/smtpd/qpsmtpd/compare/v0.04...v0.07
