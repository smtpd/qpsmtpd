# Upgrade notes

When upgrading please review these notes for the versions you are
upgrading _from_.

## v0.84 or below

### CHECK\_RELAY, CHECK\_NORELAY, RELAY\_ONLY

All 3 plugins are deprecated and replaced with a new 'relay'
plugin. The new plugin reads the same config files (see 'perldoc
plugins/relay') as the previous plugins. To get the equivalent
functionality of enabling 'relay\_only', use the 'only' argument to the
relay plugin as documented in the RELAY ONLY section of plugins/relay.

### GREYLISTING plugin

'mode' config argument is deprecated. Use reject and reject\_type instead.

The greylisting DB format has changed to accommodate IPv6
addresses. (The DB key has colon ':' seperated fields, and IPv6
addresses are colon delimited). The new format converts the IPs into
integers. There is a new config option named 'upgrade' that when
enabled, updates all the records in your DB to the new format. Simply
add 'upgrade 1' to the plugin entry in config/plugins, start up
qpsmtpd once, make one connection. A log entry will be made, telling
how many records were upgraded. Remove the upgrade option from your
config.

### SPF plugin

spf\_deny setting deprecated. Use reject N setting instead, which
provides administrators with more granular control over SPF. For
backward compatibility, a spf\_deny setting of 1 is mapped to 'reject
3' and a 'spf\_deny 2' is mapped to 'reject 4'.

### P0F plugin

defaults to p0f v3 (was v2).

Upgrade p0f to version 3 or add 'version 2' to your p0f line in
config/plugins. perldoc plugins/ident/p0f for more details.
