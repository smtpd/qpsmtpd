#!/bin/sh

usage() {
    echo "   usage: $0 <example.com> [qpsmtpd username]"
    echo " "
    exit
}

if [ -z $1 ];
then
    usage
fi

DOMAIN=$1
SMTPD=$2
if [ -z $SMTPD ];
then
    SMTPD="smtpd"
fi

# create a directory for each DKIM signing domain
mkdir -p $DOMAIN
cd $DOMAIN

# create a selector in the format mmmYYYY (apr2013)
date '+%h%Y' | tr "[:upper:]" "[:lower:]" > selector

# generate a private and public keys
openssl genrsa -out private 2048
chmod 400 private
openssl rsa -in private -out public -pubout

# make it really easy to publish the public key in DNS
cat > dns <<EO_DKIM_DNS

`cat selector | tr -d "\n"`._domainkey TXT "v=DKIM1;p=`grep -v -e '^-' public | tr -d "\n"`"

Tell the world that the ONLY mail servers that send mail from this domain are DKIM signed and/or bear our MX and A records.

With SPF:

        SPF "v=spf1 mx a -all"
        TXT "v=spf1 mx a -all"

With DMARC:

_dmarc  TXT "v=DMARC1; p=reject; adkim=s; aspf=r; rua=mailto:dmarc-feedback@$DOMAIN; ruf=mailto:dmarc-feedback@$DOMAIN; pct=100"

With DomainKeys (deprecated)

_domainkey TXT "o=-; t=y; r=postmaster@$DOMAIN"

For more information about DKIM and SPF policy, the documentation within each plugin contains a longer discussion and links to more detailed information:

   perldoc plugins/dkim
   perldoc plugins/sender_permitted_from


EO_DKIM_DNS

cd ..
chown -R $SMTPD:$SMTPD $DOMAIN
