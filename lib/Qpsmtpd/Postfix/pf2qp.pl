#!/usr/bin/perl -w
#
#
my $version = "0.1";
$0 =~ s#.*/##;
my $path = $&; # sneaky way to get path back

my $POSTFIX_SRC = shift || die <<"EOF";
Usage:
  $0 /path/to/postfix/source

EOF

my $header  = "$POSTFIX_SRC/src/global/cleanup_user.h";
my $src     = "$POSTFIX_SRC/src/global/cleanup_strerror.c";
my $pf_vers = "$POSTFIX_SRC/src/global/mail_version.h";
my $postfix_version = "";

open VERS, $pf_vers
  or die "Could not open $pf_vers: $!\n";
while (<VERS>) {
    next unless /^\s*#\s*define\s+MAIL_VERSION_NUMBER\s+"(.+)"\s*$/;
    $postfix_version = $1;
    last;
}
close VERS;
$postfix_version =~ s/^(\d+\.\d+).*/$1/;
if ($postfix_version < 2.3) {
    die "Need at least postfix v2.3";
}
my $start = <<'_END';
#
# Qpsmtpd::Postfix::Constants
#
# This is a generated file, do not edit
#
_END
$start .= "# created by $0 v$version @ ".scalar(gmtime)."\n"
         ."# postfix version $postfix_version\n"
         ."#\n";
$start .= <<'_END';
package Qpsmtpd::Postfix::Constants;

use Qpsmtpd::Constants;

require Exporter;

use vars qw(@ISA @EXPORT %cleanup_soft %cleanup_hard $postfix_version);
use strict;

@ISA = qw(Exporter);
_END

my @export = qw(%cleanup_soft %cleanup_hard $postfix_version);
my @out = ();

open HEAD, $header
  or die "Could not open $header: $!\n";

while (<HEAD>) {
    while (s/\\\n$//) {
        $_ .= <HEAD>;
    }
    chomp;
    if (/^\s*#define\s/) {
        s/^\s*#define\s*//;
        next if /^_/;
        s#(/\*.*\*/)##;
        my $comment = $1 || "";
        my @words = split / /, $_;
        my $const = shift @words;
        if ($const eq "CLEANUP_STAT_OK") {
            push @out, "";
        }
        push @export, $const;
        push @out, "use constant $const => ". join(" ", @words). "; " 
               .($comment ? "# $comment ": "");
    }
}
close HEAD;

open SRC, $src
  or die "Could not open $src: $!\n";
my $data;
{ 
  local $/ = undef;
  $data = <SRC>;
}
close SRC;
$data =~ s/.*cleanup_stat_map\[\]\s*=\s*{\s*\n//s;
$data =~ s/};.*$//s;
my @array = split "\n", $data;
my (@denysoft,@denyhard);
foreach (@array) {
    chomp;
    s/,/ => /;
    s/"(\d\.\d\.\d)",\s+"(.*)",/"$2 (#$1)",/;
    s!(/\*.*\*/)!# $1!;
    s/4\d\d,\s// && push @denysoft, $_;
    s/5\d\d,\s// && push @denyhard, $_;
}

open my $CONSTANTS, '>', "$path/Constants.pm";

print ${CONSTANTS} $start, '@EXPORT = qw(', "\n";
while (@export) {
    print ${CONSTANTS} "\t", shift @export, "\n";
}
print ${CONSTANTS} ");\n\n", 
       "\$postfix_version = \"$postfix_version\";\n",
       join("\n", @out),"\n\n";
print ${CONSTANTS} "\%cleanup_soft = (\n", join("\n", @denysoft), "\n);\n\n";
print ${CONSTANTS} "\%cleanup_hard = (\n", join("\n", @denyhard), "\n);\n\n1;\n";

close $CONSTANTS;
