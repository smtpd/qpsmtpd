#
# Regular cron jobs for the qpsmtpd package
#
0 4	* * *	root	[ -x /usr/bin/qpsmtpd_maintenance ] && /usr/bin/qpsmtpd_maintenance
