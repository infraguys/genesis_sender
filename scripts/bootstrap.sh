#!/usr/bin/env bash

# Copyright 2025 Genesis Corporation
#
# All Rights Reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

set -eu
set -x
set -o pipefail

# Function to display help message
show_help() {
    echo "Usage: $0 <target_domain> <allowed_cidr>"
    echo "Setup exim4."
}

# Check if the second argument is set
if [ $# -lt 1 ]; then
    show_help
    exit
fi

# TODO: remove relay net at all?
valid_cidr() {
  CIDR="$1"

  # Parse "a.b.c.d/n" into five separate variables
  IFS="./" read -r ip1 ip2 ip3 ip4 N <<< "$CIDR"

  # Convert IP address from quad notation to integer
  ip=$(($ip1 * 256 ** 3 + $ip2 * 256 ** 2 + $ip3 * 256 + $ip4))

  # Remove upper bits and check that all $N lower bits are 0
  if [ $(($ip % 2**(32-$N))) = 0 ]
  then
    return 0 # CIDR OK!
  else
    return 1 # CIDR NOT OK!
  fi
}

if ! valid_cidr "${2}"; then
    echo "CIDR is not valid!"
    show_help
    exit
fi

[[ "$EUID" == 0 ]] || exec sudo -s "$0" "$@"

# Change hostname
hostnamectl set-hostname "$1"

# basic config
cd /etc/exim4

cat > /etc/exim4/update-exim4.conf.conf <<EOF
dc_eximconfig_configtype='internet'
dc_other_hostnames='$1'
dc_local_interfaces='<; [0.0.0.0]:465; [0.0.0.0]:587'
dc_readhost=''
dc_relay_domains=''
dc_minimaldns='false'
# dc_relay_nets='$2'
dc_smarthost=''
CFILEMODE='644'
dc_use_split_config='true'
dc_hide_mailname=''
dc_mailname_in_oh='true'
dc_localdelivery='mail_spool'
EOF

# DKIM
mkdir -p /etc/exim4/dkim
opendkim-genkey -D /etc/exim4/dkim/ -d "$1" -s platform
chown Debian-exim:Debian-exim /etc/exim4/dkim/ -R
chmod 640 /etc/exim4/dkim/*

cat > /etc/exim4/conf.d/transport/01_platform <<EOL
DKIM_CANON = relaxed
DKIM_DOMAIN = $1
DKIM_PRIVATE_KEY = /etc/exim4/dkim/platfrom.private
DKIM_SELECTOR = platform
EOL


# AUTH
COMMON_USER=common
COMMON_PASS=$(openssl rand -base64 32)
cd /etc/exim4
openssl req -x509 -sha256 -days 9000 -nodes -newkey rsa:4096 -keyout exim.key -out exim.crt -subj "/CN=$1/O=$1/C=US"
chown root:Debian-exim exim.key exim.crt
chmod 640 exim.key exim.crt

echo "MAIN_TLS_ENABLE = true" > /etc/exim4/conf.d/main/01_platform
cat > /etc/exim4/conf.d/auth/01_platform <<EOL
plain_server:
  driver = plaintext
  public_name = PLAIN
  server_condition = "\${if crypteq{\$auth3}{\${extract{1}{:}{\${lookup{\$auth2}lsearch{CONFDIR/passwd}{\$value}{*:*}}}}}{1}{0}}"
  server_set_id = \$auth2
  server_prompts = :
  .ifndef AUTH_SERVER_ALLOW_NOTLS_PASSWORDS
  server_advertise_condition = \${if eq{\$tls_in_cipher}{}{}{*}}
  .endif
login_server:
  driver = plaintext
  public_name = LOGIN
  server_prompts = "Username:: : Password::"
  server_condition = "\${if crypteq{\$auth2}{\${extract{1}{:}{\${lookup{\$auth1}lsearch{CONFDIR/passwd}{\$value}{*:*}}}}}{1}{0}}"
  server_set_id = \$auth1
  .ifndef AUTH_SERVER_ALLOW_NOTLS_PASSWORDS
  server_advertise_condition = \${if eq{\$tls_in_cipher}{}{}{*}}
  .endif
EOL

touch /etc/exim4/passwd
chown root:Debian-exim /etc/exim4/passwd
chmod 640 /etc/exim4/passwd
COMMON_PASS_HASH=$(echo "$COMMON_PASS" | mkpasswd -H md5 -s)
echo "$COMMON_USER:$COMMON_PASS_HASH:$COMMON_PASS" >> /etc/exim4/passwd

update-exim4.conf
systemctl restart exim4

# Finish info
cat <<EOL
------------------------------------------
- See SMTP passwords (third column) in /etc/exim4/passwd (`common` user already added)
- Add new SMTP password with /usr/share/doc/exim4-base/examples/exim-adduser
- Set DKIM record, see /etc/exim4/dkim/platform.txt for DKIM parameters for domain
- Set SPF record: name: - (on domain itself) type: TXT, TTL 3600 data: "v=spf1 ip4:YOUR_SERVER_IP/32 a mx ~all"
- Set DMARC record: name: "_dmarc" type: TXT TTL: 3600 data: "v=DMARC1; p=none; pct=100; adkim=s; aspf=s"
- Set PTR record on your server IP to domain $1
- To test message send: swaks --to YOUR_EMAIL --server 127.0.0.1:465 --tls --auth
- Or: use test_mail.py
EOL
