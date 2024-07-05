#!/bin/bash
# JRA (Jibri Recordings Access) via Nextcloud
# SwITNet Ltd © - 2024, https://switnet.net/
# GPLv3 or later.

while getopts m: option
do
	case "${option}"
	in
		m) MODE=${OPTARG};;
		\?) echo "Usage: sudo bash ./$0 [-m debug]" && exit;;
	esac
done

#DEBUG
if [ "$MODE" = "debug" ]; then
    set -x
fi

if ! [ "$(id -u)" = 0 ]; then
   echo "You need to be root or have sudo privileges!"
   exit 0
fi
exit_if_not_installed() {
if [ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -c "ok installed")" != "1" ]; then
    echo " This instance doesn't have $1 installed, exiting..."
    echo " If you think this is an error, please report to:
    -> https://forge.switnet.net/switnet/quick-jibri-installer/issues "
    exit
fi
}
clear
echo -e '\n
########################################################################
                 Jibri Recordings Access via Nextcloud
########################################################################
                    by Software, IT & Networks Ltd
\n'
exit_if_not_installed jitsi-meet
## APT checks
apt-get update -q2
# Manually add prerequisites.
apt-get install -y curl letsencrypt nginx

MIN_PHP="8.2"
DOMAIN="$(find /etc/prosody/conf.d/ -name \*.lua|awk -F'.cfg' '!/localhost/{print $1}'|xargs basename)"
PSGVER="$(apt-cache madison postgresql|tr -d '[:blank:]'|awk -F'[|+]' 'NR==1{print $2}')"
NC_NGINX_SSL_PORT="$(grep "listen 44" /etc/nginx/sites-available/"$DOMAIN".conf | awk '{print$2}')"
[ -z "$NC_NGINX_SSL_PORT" ] && NC_NGINX_SSL_PORT="443"
NC_REPO="https://download.nextcloud.com/server/releases"
NCVERSION="$(curl -s -m 900 $NC_REPO/ | sed --silent 's/.*href="nextcloud-\([^"]\+\).zip.asc".*/\1/p' | sort --version-sort | tail -1)"
STABLEVERSION="nextcloud-$NCVERSION"
NC_PATH="/var/www/nextcloud"
NC_CONFIG="$NC_PATH/config/config.php"
NC_DB_USER="nextcloud_user"
NC_DB="nextcloud_db"
NC_DB_PASSWD="$(tr -dc "a-zA-Z0-9#_*=" < /dev/urandom | fold -w 14 | head -n1)"
DIR_RECORD="$(awk  -F '"' '/RECORDING/{print$2}'  /home/jibri/finalize_recording.sh|awk 'NR==1{print$1}')"
REDIS_CONF="/etc/redis/redis.conf"
JITSI_MEET_PROXY="/etc/nginx/modules-enabled/60-jitsi-meet.conf"
[ -f "$JITSI_MEET_PROXY" ] && PREAD_PROXY=$(grep -nr "preread_server_name" "$JITSI_MEET_PROXY" | cut -d ":" -f1)
PUBLIC_IP="$(dig -4 +short myip.opendns.com @resolver1.opendns.com)"
ISO3166_CODE=TBD
NL="$(printf '\n  ')"


exit_ifinstalled() {
if [ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -c "ok installed")" == "1" ]; then
    echo " This instance already has $1 installed, exiting..."
    echo " If you think this is an error, please report to:
    -> https://forge.switnet.net/switnet/quick-jibri-installer/issues "
    exit
fi
}
install_ifnot() {
if [ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -c "ok installed")" == "1" ]; then
    echo " $1 is installed, skipping..."
else
    echo -e "\n---- Installing $1 ----"
    apt-get -yq2 install "$1"
fi
}
while [[ "$ANS_NCD" != "yes" ]]
do
  read -p "> Please set your domain (or subdomain) here for Nextcloud: (e.g.: cloud.domain.com)$NL" -r NC_DOMAIN
  if [ -z "$NC_DOMAIN" ];then
    echo " - This field is mandatory."
  elif [ "$NC_DOMAIN" = "$DOMAIN" ]; then
    echo " - You can not use the same domain for both, Jitsi Meet and JRA via Nextcloud."
  fi
  read -p "  > Did you mean?: $NC_DOMAIN (yes or no)$NL" -r ANS_NCD
  if [ "$ANS_NCD" = "yes" ]; then
    echo "   - Alright, let's use $NC_DOMAIN."
  else
    echo "   - Please try again."
  fi
done
sleep .1
  #Simple DNS test
if [ "$PUBLIC_IP" = "$(dig -4 +short "$NC_DOMAIN"|awk -v RS='([0-9]+\\.){3}[0-9]+' 'RT{print RT}')" ]; then
  echo -e "Server public IP  & DNS record for $NC_DOMAIN seems to match, continuing...\n\n"
  sleep .1
else
  echo "Server public IP ($PUBLIC_IP) & DNS record for $NC_DOMAIN don't seem to match."
  echo "  > Please check your dns records are applied and updated, otherwise Nextcloud may fail."
  read -p "  > Do you want to continue?: (yes or no)$NL" -r DNS_CONTINUE
  if [ "$DNS_CONTINUE" = "yes" ]; then
    echo "  - We'll continue anyway..."
  else
    echo "  - Exiting for now..."
  exit
  fi
fi
sleep .1
NC_NGINX_CONF="/etc/nginx/sites-available/$NC_DOMAIN.conf"
while [ -z "$NC_USER" ]
do
    read -p "Nextcloud user: " -r NC_USER
    if [ -z "$NC_USER" ]; then
        echo " - This field is mandatory."
    fi
done
sleep .1
while [ -z "$NC_PASS" ]  || [ ${#NC_PASS} -lt 8 ]
do
    read -p "Nextcloud user password: " -r NC_PASS
    if [ -z "$NC_PASS" ] || [ ${#NC_PASS} -lt 8 ]; then
        echo -e " - This field is mandatory. \nPlease make sure it's at least 8 characters.\n"
    fi
done
sleep .1
#Enable HSTS
while [ "$ENABLE_HSTS" != "yes" ] && [ "$ENABLE_HSTS" != "no" ]
do
    read -p "> Do you want to enable HSTS for this domain?: (yes or no)
  Be aware this option apply mid-term effects on the domain, choose \"no\"
  in case you don't know what you are doing. More at https://hstspreload.org/$NL" -r ENABLE_HSTS
    if [ "$ENABLE_HSTS" = "no" ]; then
        echo " - HSTS won't be enabled."
    elif [ "$ENABLE_HSTS" = "yes" ]; then
        echo " - HSTS will be enabled."
    fi
done
sleep .1
echo -e "#Default country phone code\n
> Starting at Nextcloud 21.x it's required to set a default country phone ISO 3166-1 alpha-2 code.\n
>>> https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2#Officially_assigned_code_elements  <<<\n"
sleep .1
while [ ${#ISO3166_CODE} -gt 2 ];
do
echo -e "Some examples might be: Germany > DE | Mexico > MX | Spain > ES | USA > US\n
Do you want to set such code for your installation?"
sleep .1
read -p "Leave empty if you don't want to set any: " -r ISO3166_CODE
  if [ ${#ISO3166_CODE} -gt 2 ]; then
    echo -e "\n-- This code is only 2 characters long, please check your input.\n"
  fi
done
sleep .1
echo -e "\n# Check for jitsi-meet/jibri\n"
if [ "$(dpkg-query -W -f='${Status}' jibri 2>/dev/null | grep -c "ok installed")" == "1" ] || \
   [ -f /etc/prosody/conf.d/"$DOMAIN".conf ]; then
    echo "jitsi meet/jibri is installed, checking version:"
    apt-show-versions jibri
else
    echo "Wait!, jitsi-meet/jibri is not installed on this system using apt, exiting..."
    exit
fi

#Prevent root folder permission issues
cp "$PWD"/files/jra-nc-app-ef.json /tmp

exit_ifinstalled postgresql-"$PSGVER"

## Install software requirements
# PostgresSQL
install_ifnot postgresql-"$PSGVER"


#--------------------------------------------------
# Prepare PHP
#--------------------------------------------------

if [ "$MODE" = "debug" ]; then
    bash -x "$PWD"/tools/prepare_php.sh "$MIN_PHP"
else
    bash "$PWD"/tools/prepare_php.sh "$MIN_PHP"
fi

#--------------------------------------------------
# Create DB user
#--------------------------------------------------

echo -e "\n---- Creating the PgSQL DB & User  ----"
sudo -u postgres psql <<DB
CREATE DATABASE nextcloud_db;
CREATE USER ${NC_DB_USER} WITH ENCRYPTED PASSWORD '${NC_DB_PASSWD}';
GRANT ALL PRIVILEGES ON DATABASE ${NC_DB} TO ${NC_DB_USER};
DB
echo -e "\nDone!\n"

# Add .mjs as a file extension for javascript
sed -i "/application\/javascript/s|js.*;|js mjs;|" /etc/nginx/mime.types

# nginx conf setup.
cp files/nextcloud.conf "$NC_NGINX_CONF"
sed -i "s|_PHPVER|$MIN_PHP|g" "$NC_NGINX_CONF"
sed -i "s|_NC_DOMAIN|$NC_DOMAIN|g" "$NC_NGINX_CONF"
sed -i "s|_NC_NGINX_SSL_PORT|$NC_NGINX_SSL_PORT|g" "$NC_NGINX_CONF"
sed -i "s|_NC_PATH|$NC_PATH|g" "$NC_NGINX_CONF"

systemctl stop nginx
letsencrypt certonly --standalone --renew-by-default --agree-tos -d "$NC_DOMAIN"
if [ -f /etc/letsencrypt/live/"$NC_DOMAIN"/fullchain.pem ];then
    ln -s "$NC_NGINX_CONF" /etc/nginx/sites-enabled/
else
    echo "There are issues on getting the SSL certs..."
    read -n 1 -s -r -p "Press any key to continue"
fi
nginx -t
systemctl restart nginx

if [ "$ENABLE_HSTS" = "yes" ]; then
    sed -i "s|#add_header Strict-Transport-Security|add_header Strict-Transport-Security|g" "$NC_NGINX_CONF"
fi

if [ -n "$PREAD_PROXY" ]; then
    echo "
  Setting up Nextcloud domain on Jitsi Meet turn proxy
"
    sed -i "/server {/i \ \ map \$ssl_preread_server_name \$upstream {" "$JITSI_MEET_PROXY"
    sed -i "/server {/i \ \ \ \ \ \ $DOMAIN      web;" "$JITSI_MEET_PROXY"
    sed -i "/server {/i \ \ \ \ \ \ $NC_DOMAIN web;" "$JITSI_MEET_PROXY"
    sed -i "/server {/i \ \ }" "$JITSI_MEET_PROXY"
fi

echo -e "\n  Latest version to be installed: $STABLEVERSION
  (This might take sometime, please be patient...)\n"
curl -s "$NC_REPO"/"$STABLEVERSION".zip > /tmp/"$STABLEVERSION".zip
unzip -q /tmp/"$STABLEVERSION".zip
mv nextcloud "$NC_PATH"

chown -R www-data:www-data "$NC_PATH"
chmod -R 755 "$NC_PATH"

echo -e "\nDatabase installation...\n"
sudo -u www-data php$MIN_PHP "$NC_PATH"/occ maintenance:install \
--database=pgsql \
--database-name="$NC_DB" \
--database-user="$NC_DB_USER" \
--database-pass="$NC_DB_PASSWD" \
--admin-user="$NC_USER" \
--admin-pass="$NC_PASS"

echo -e "\nApply custom mods...\n"
sed -i "/datadirectory/a \ \ \'skeletondirectory\' => \'\'," "$NC_CONFIG"
sed -i "/skeletondirectory/a \ \ \'simpleSignUpLink.shown\' => false," "$NC_CONFIG"
sed -i "/simpleSignUpLink.shown/a \ \ \'knowledgebaseenabled\' => false," "$NC_CONFIG"
sed -i "s|http://localhost|https://$NC_DOMAIN|" "$NC_CONFIG"

echo -e "\nAdd crontab...\n"
crontab -u www-data -l | { cat; echo "*/5  *  *  *  * php$MIN_PHP -f $NC_PATH/cron.php"; } | crontab -u www-data -

echo -e "\nAdd memcache support...\n"
sed -i "s|# unixsocket .*|unixsocket /var/run/redis/redis.sock|g" "$REDIS_CONF"
sed -i "s|# unixsocketperm .*|unixsocketperm 777|g" "$REDIS_CONF"
sed -i "s|port 6379|port 0|" "$REDIS_CONF"
systemctl restart redis-server

echo -e "\n--> Setting config.php...\n"
if [ -n "$ISO3166_CODE" ]; then
  sed -i "/);/i \ \ 'default_phone_region' => '$ISO3166_CODE'," "$NC_CONFIG"
fi
sed -i "/);/i \ \ 'filelocking.enabled' => 'true'," "$NC_CONFIG"
sed -i "/);/i \ \ 'memcache.locking' => '\\\OC\\\Memcache\\\Redis'," "$NC_CONFIG"
sed -i "/);/i \ \ 'memcache.local' => '\\\OC\\\Memcache\\\Redis'," "$NC_CONFIG"
sed -i "/);/i \ \ 'memcache.local' => '\\\OC\\\Memcache\\\Redis'," "$NC_CONFIG"
sed -i "/);/i \ \ 'memcache.distributed' => '\\\OC\\\Memcache\\\Redis'," "$NC_CONFIG"
sed -i "/);/i \ \ 'redis' =>" "$NC_CONFIG"
sed -i "/);/i \ \ \ \ array (" "$NC_CONFIG"
sed -i "/);/i \ \ \ \ \ 'host' => '/var/run/redis/redis.sock'," "$NC_CONFIG"
sed -i "/);/i \ \ \ \ \ 'port' => 0," "$NC_CONFIG"
sed -i "/);/i \ \ \ \ \ 'timeout' => 0," "$NC_CONFIG"
sed -i "/);/i \ \ )," "$NC_CONFIG"
echo -e "Done\n"

echo -e "\nAddding & Setting up Files External App for Local storage...\n"
sudo -u www-data php$MIN_PHP "$NC_PATH"/occ app:install files_external
sudo -u www-data php$MIN_PHP "$NC_PATH"/occ app:enable files_external
sudo -u www-data php$MIN_PHP "$NC_PATH"/occ app:disable support
sudo -u www-data php$MIN_PHP "$NC_PATH"/occ files_external:import /tmp/jra-nc-app-ef.json

usermod -a -G jibri www-data
chmod -R 770 "$DIR_RECORD"
chmod -R g+s "$DIR_RECORD"

echo -e "\nFixing possible missing tables...\n\n"
echo "y"|sudo -u www-data php$MIN_PHP "$NC_PATH"/occ db:convert-filecache-bigint
sudo -u www-data php$MIN_PHP "$NC_PATH"/occ db:add-missing-indices
sudo -u www-data php$MIN_PHP "$NC_PATH"/occ db:add-missing-columns

echo -e "\nAdding trusted domain...\n"
sudo -u www-data php$MIN_PHP "$NC_PATH"/occ config:system:set trusted_domains 0 --value="$NC_DOMAIN"

echo -e "\nSetting JRA domain on jitsi-updater.sh\n"
sed -i "s|NC_DOMAIN=.*|NC_DOMAIN=\"$NC_DOMAIN\"|" jitsi-updater.sh

echo -e "\nQuick Nextcloud installation complete!\n"
