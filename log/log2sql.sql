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
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `inode` int(11) unsigned NOT NULL,
  `size` int(11) unsigned NOT NULL,
  `name` varchar(30) NOT NULL DEFAULT '',
  `created` datetime DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

# Dump of table message
# ------------------------------------------------------------

DROP TABLE IF EXISTS `message`;

CREATE TABLE `message` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `file_id` int(10) unsigned NOT NULL,
  `connect_start` datetime NOT NULL,
  `ip` int(10) unsigned NOT NULL,
  `qp_pid` int(10) unsigned NOT NULL,
  `result` tinyint(3) NOT NULL DEFAULT '0',
  `distance` mediumint(8) unsigned DEFAULT NULL,
  `time` decimal(3,2) unsigned DEFAULT NULL,
  `os_id` tinyint(3) unsigned DEFAULT NULL,
  `hostname` varchar(128) DEFAULT NULL,
  `helo` varchar(128) DEFAULT NULL,
  `mail_from` varchar(128) DEFAULT NULL,
  `rcpt_to` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `file_id` (`file_id`),
  CONSTRAINT `message_ibfk_1` FOREIGN KEY (`file_id`) REFERENCES `log` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;



# Dump of table message_plugin
# ------------------------------------------------------------

DROP TABLE IF EXISTS `message_plugin`;

CREATE TABLE `message_plugin` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `msg_id` int(11) unsigned NOT NULL,
  `plugin_id` int(4) unsigned NOT NULL,
  `result` tinyint(4) NOT NULL,
  `string` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `msg_id` (`msg_id`),
  KEY `plugin_id` (`plugin_id`),
  CONSTRAINT `message_plugin_ibfk_1` FOREIGN KEY (`plugin_id`) REFERENCES `plugin` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `msg_id` FOREIGN KEY (`msg_id`) REFERENCES `message` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;


# Dump of table os
# ------------------------------------------------------------

DROP TABLE IF EXISTS `os`;

CREATE TABLE `os` (
  `id` tinyint(3) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(36) DEFAULT NULL,
  PRIMARY KEY (`id`)
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
  `id` int(4) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(35) CHARACTER SET utf8 NOT NULL DEFAULT '',
  `abb3` char(3) CHARACTER SET utf8 DEFAULT NULL,
  `abb5` char(5) CHARACTER SET utf8 DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `abb5` (`abb5`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin;


# Dump of table plugin_aliases
# ------------------------------------------------------------

DROP TABLE IF EXISTS `plugin_aliases`;

CREATE TABLE `plugin_aliases` (
  `plugin_id` int(11) unsigned NOT NULL,
  `name` varchar(35) CHARACTER SET utf8 NOT NULL DEFAULT '',
  UNIQUE KEY `plugin_id` (`plugin_id`,`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin;

/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;
/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
