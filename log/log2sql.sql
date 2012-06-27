/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;


# Dump of table log
# ------------------------------------------------------------

DROP TABLE IF EXISTS `log`;

CREATE TABLE `log` (
  `id` int(11) unsigned NOT NULL auto_increment,
  `inode` int(11) unsigned NOT NULL,
  `size` int(11) unsigned NOT NULL,
  `name` varchar(30) NOT NULL default '',
  `created` datetime default NULL,
  PRIMARY KEY  (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


# Dump of table message
# ------------------------------------------------------------

DROP TABLE IF EXISTS `message`;

CREATE TABLE `message` (
  `id` int(11) unsigned NOT NULL auto_increment,
  `file_id` int(10) unsigned NOT NULL,
  `connect_start` datetime NOT NULL,
  `ip` int(10) unsigned NOT NULL,
  `qp_pid` int(10) unsigned NOT NULL,
  `result` tinyint(3) NOT NULL default '0',
  `distance` mediumint(8) unsigned default NULL,
  `time` decimal(3,2) unsigned default NULL,
  `os_id` tinyint(3) unsigned default NULL,
  `hostname` varchar(128) default NULL,
  `helo` varchar(128) default NULL,
  `mail_from` varchar(128) default NULL,
  `rcpt_to` varchar(128) default NULL,
  PRIMARY KEY  (`id`),
  KEY `file_id` (`file_id`),
  CONSTRAINT `message_ibfk_1` FOREIGN KEY (`file_id`) REFERENCES `log` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;



# Dump of table message_plugin
# ------------------------------------------------------------

DROP TABLE IF EXISTS `message_plugin`;

CREATE TABLE `message_plugin` (
  `id` int(11) unsigned NOT NULL auto_increment,
  `msg_id` int(11) unsigned NOT NULL,
  `plugin_id` int(4) unsigned NOT NULL,
  `result` tinyint(4) NOT NULL,
  `string` varchar(128) default NULL,
  PRIMARY KEY  (`id`),
  KEY `msg_id` (`msg_id`),
  KEY `plugin_id` (`plugin_id`),
  CONSTRAINT `message_plugin_ibfk_1` FOREIGN KEY (`plugin_id`) REFERENCES `plugin` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `msg_id` FOREIGN KEY (`msg_id`) REFERENCES `message` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;



# Dump of table os
# ------------------------------------------------------------

DROP TABLE IF EXISTS `os`;

CREATE TABLE `os` (
  `id` tinyint(3) unsigned NOT NULL auto_increment,
  `name` varchar(36) default NULL,
  PRIMARY KEY  (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

LOCK TABLES `os` WRITE;
/*!40000 ALTER TABLE `os` DISABLE KEYS */;

INSERT INTO `os` (`id`, `name`)
VALUES
    (1,'FreeBSD'),
    (2,'Mac OS X'),
    (3,'Solaris'),
    (4,'Linux'),
    (5,'OpenBSD'),
    (6,'iOS'),
    (7,'HP-UX'),
    (8,'Windows 95'),
    (9,'Windows 98'),
    (10,'Windows NT'),
    (11,'Windows XP'),
    (12,'Windows XP/2000'),
    (13,'Windows 2000'),
    (14,'Windows 2003'),
    (15,'Windows 7 or 8'),
    (17,'Google'),
    (18,'NetCache'),
    (19,'Cisco'),
    (20,'Netware');

/*!40000 ALTER TABLE `os` ENABLE KEYS */;
UNLOCK TABLES;


# Dump of table plugin
# ------------------------------------------------------------

DROP TABLE IF EXISTS `plugin`;

CREATE TABLE `plugin` (
  `id` int(4) unsigned NOT NULL auto_increment,
  `name` varchar(35) character set utf8 NOT NULL default '',
  `abb3` char(3) character set utf8 default NULL,
  `abb5` char(5) character set utf8 default NULL,
  PRIMARY KEY  (`id`),
  UNIQUE KEY `abb3` (`abb3`),
  UNIQUE KEY `abb5` (`abb5`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin;

LOCK TABLES `plugin` WRITE;
/*!40000 ALTER TABLE `plugin` DISABLE KEYS */;

INSERT INTO `plugin` (`id`, `name`, `abb3`, `abb5`)
VALUES
    (1,'hosts_allow','alw','allow'),
    (2,'ident::geoip','geo','geoip'),
    (3,'ident::p0f','p0f',' p0f'),
    (5,'karma','krm','karma'),
    (6,'dnsbl','dbl','dnsbl'),
    (7,'relay','rly','relay'),
    (9,'earlytalker','ear','early'),
    (15,'helo','hlo','helo'),
    (16,'tls','tls',' tls'),
    (20,'dont_require_anglebrackets','rab','drabs'),
    (21,'unrecognized_commands','cmd','uncmd'),
    (22,'noop','nop','noop'),
    (23,'random_error','rnd','rande'),
    (24,'milter','mtr','mlter'),
    (25,'content_log','log','colog'),
    (30,'auth::vpopmail_sql','aut','vpsql'),
    (31,'auth::vpopmaild','vpd','vpopd'),
    (32,'auth::vpopmail','vpo','vpop'),
    (33,'auth::checkpasswd','ckp','chkpw'),
    (34,'auth::cvs_unix_local','cvs','cvsul'),
    (35,'auth::flat_file','flt','aflat'),
    (36,'auth::ldap_bind','ldp','aldap'),
    (40,'badmailfrom','bmf','badmf'),
    (41,'badmailfromto','bmt','bfrto'),
    (42,'rhsbl','rbl','rhsbl'),
    (44,'resolvable_fromhost','rfh','rsvfh'),
    (45,'sender_permitted_from','spf',' spf'),
    (50,'badrcptto','bto','badto'),
    (51,'rcpt_map','rmp','rcmap'),
    (52,'rcpt_regex','rcx','rcrex'),
    (53,'qmail_deliverable','qmd',' qmd'),
    (55,'rcpt_ok','rok','rcpok'),
    (58,'bogus_bounce','bog','bogus'),
    (59,'greylisting','gry','greyl'),
    (60,'headers','hdr','headr'),
    (61,'loop','lop','loop'),
    (62,'uribl','uri','uribl'),
    (63,'domainkeys','dk','dkey'),
    (64,'dkim','dkm','dkim'),
    (65,'spamassassin','spm','spama'),
    (66,'dspam','dsp','dspam'),
    (70,'virus::aveclient','vav','avirs'),
    (71,'virus::bitdefender','vbd','bitdf'),
    (72,'virus::clamav','cav','clamv'),
    (73,'virus::clamdscan','cad','clamd'),
    (74,'virus::hbedv','hbv','hbedv'),
    (75,'virus::kavscanner','kav','kavsc'),
    (76,'virus::klez_filter','klz','vklez'),
    (77,'virus::sophie','sop','sophe'),
    (78,'virus::uvscan','uvs','uvscn'),
    (80,'queue::qmail-queue','qqm','queue'),
    (81,'queue::maildir','qdr','qudir'),
    (82,'queue::postfix-queue','qpf','qupfx'),
    (83,'queue::smtp-forward','qfw','qufwd'),
    (84,'queue::exim-bsmtp','qxm','qexim'),
    (98,'quit_fortune','for','fortu'),
    (99,'connection_time','tim','time');

/*!40000 ALTER TABLE `plugin` ENABLE KEYS */;
UNLOCK TABLES;


# Dump of table plugin_aliases
# ------------------------------------------------------------

DROP TABLE IF EXISTS `plugin_aliases`;

CREATE TABLE `plugin_aliases` (
  `plugin_id` int(11) unsigned NOT NULL,
  `name` varchar(35) character set utf8 NOT NULL default '',
  KEY `plugin_id` (`plugin_id`),
  CONSTRAINT `plugin_id` FOREIGN KEY (`plugin_id`) REFERENCES `plugin` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin;

LOCK TABLES `plugin_aliases` WRITE;
/*!40000 ALTER TABLE `plugin_aliases` DISABLE KEYS */;

INSERT INTO `plugin_aliases` (`plugin_id`, `name`)
VALUES
    (60,'check_basicheaders'),
    (44,'require_resolvable_fromhost'),
    (21,'count_unrecognized_commands'),
    (9,'check_earlytalker'),
    (40,'check_badmailfrom'),
    (50,'check_badrcptto'),
    (58,'check_bogus_bounce'),
    (15,'check_spamhelo'),
    (3,'ident::p0f_3a0'),
    (80,'queue::qmail_2dqueue'),
    (22,'noop_counter');

/*!40000 ALTER TABLE `plugin_aliases` ENABLE KEYS */;
UNLOCK TABLES;



/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;
/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
