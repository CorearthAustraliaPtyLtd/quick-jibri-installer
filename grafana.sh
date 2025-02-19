#!/bin/bash
# Grafana Installer for Jitsi Meet
#
# Based on:
# - https://community.jitsi.org/t/38696
# by Igor Kerstges
# - https://grafana.com/grafana/dashboards/11969
# by "mephisto"
#
# Igor Kerstges © - 2021
# SwITNet Ltd © - 2024, https://switnet.net/
#
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

clear
echo '
########################################################################
                      Grafana Dashboard addon
########################################################################
                    by Software, IT & Networks Ltd
'
run_service() {
systemctl enable "$1"
systemctl restart "$1"
systemctl status "$1"
}
test_match() {
    if grep -q "$1" "$2" ; then
        echo "$(basename "$2") - OK..."
    else
        echo "$(basename "$2"), FAIL..."
        echo "Please report this to https://forge.switnet.net/switnet/quick-jibri-installer"
        exit
    fi
}
MAIN_TEL="/etc/telegraf/telegraf.conf"
TEL_JIT="/etc/telegraf/telegraf.d/jitsi.conf"
GRAFANA_INI="/etc/grafana/grafana.ini"
DOMAIN="$(find /etc/prosody/conf.d/ -name \*.lua|awk -F'.cfg' '!/localhost/{print $1}'|xargs basename)"
WS_CONF="/etc/nginx/sites-available/$DOMAIN.conf"
WS_MATCH1="# ensure all static content can always be found first"
WS_MATCH2="upstream prosody {"
GRAFANA_PASS="$(tr -dc "a-zA-Z0-9#_*=" < /dev/urandom | fold -w 14 | head -n1)"

# Min requirements
apt-get update && \
apt-get install -y gnupg2 \
                   curl \
                   wget \
                   jq

# Make sure we can rely on the match strings.
printf "> Testing match strings on config files.\n"
test_match "$WS_MATCH1" "$WS_CONF"

echo "
# Setup InfluxDB Packages
"
curl -s https://repos.influxdata.com/influxdata-archive.key > \
    /etc/apt/trusted.gpg.d/influxdata-archive.key
echo "deb [signed-by=/etc/apt/trusted.gpg.d/influxdata-archive.key] https://repos.influxdata.com/debian buster stable" | \
    sudo tee /etc/apt/sources.list.d/influxdb.list
apt-get update && apt-get install influxdb -y
run_service influxdb

echo "
#  Setup Grafana Packages
"
curl -s https://apt.grafana.com/gpg-full.key | \
gpg --dearmor | tee /etc/apt/trusted.gpg.d/grafana-full-key.gpg  >/dev/null
echo "deb https://packages.grafana.com/oss/deb stable main" | \
    sudo tee /etc/apt/sources.list.d/grafana_com_oss_deb.list
apt-get update && apt-get install grafana -y
run_service grafana-server

echo "
# Setup Telegraf Packages
"
apt-get update && apt-get install telegraf -y
mv /etc/telegraf/telegraf.conf /etc/telegraf/telegraf.conf.original

echo "
# Setup Telegraf config files
"
cat << TELEGRAF > $MAIN_TEL
[global_tags]

###############################################################################
#                                  GLOBAL                                     #
###############################################################################

[agent]
    interval = "10s"
    debug = false
    hostname = "localhost"
    round_interval = true
    flush_interval = "10s"
    flush_jitter = "0s"
    collection_jitter = "0s"
    metric_batch_size = 1000
    metric_buffer_limit = 10000
    quiet = false
    logfile = ""
    omit_hostname = false

TELEGRAF

cat << JITSI_TELEGRAF > $TEL_JIT
###############################################################################
#                                  INPUTS                                     #
###############################################################################

[[inputs.http]]
    name_override = "jitsi_stats"
    urls = [
      "http://localhost:8080/colibri/stats"
    ]

    data_format = "json"

###############################################################################
#                                  OUTPUTS                                    #
###############################################################################

[[outputs.influxdb]]
    urls = ["http://localhost:8086"]
    database = "jitsi"
    timeout = "0s"
    retention_policy = ""

JITSI_TELEGRAF

run_service telegraf

echo -e "\n# Setup videobridge  options\n"
echo '
# extra options to pass to the JVB daemon
JVB_OPTS="--apis=rest,xmpp"' >>  /etc/jitsi/videobridge/config
sed -i "s|TRANSPORT=muc|TRANSPORT=muc,colibri|" /etc/jitsi/videobridge/sip-communicator.properties
# Enable videobridge REST API
hocon -f /etc/jitsi/videobridge/jvb.conf set videobridge.apis.rest.enabled true
systemctl restart jitsi-videobridge2

echo -e "\n# Setup Grafana nginx domain\n"
sed -i "s|;protocol =.*|protocol = http|" $GRAFANA_INI
sed -i "s|;http_addr =.*|http_addr = 127.0.0.1|" $GRAFANA_INI
sed -i "s|;http_port =.*|http_port = 3000|" $GRAFANA_INI
sed -i "s|;domain =.*|domain = $DOMAIN|" $GRAFANA_INI
sed -i "s|;enforce_domain =.*|enforce_domain = false|" $GRAFANA_INI
sed -i "s|;root_url =.*|root_url = http://$DOMAIN:3000/grafana/|" $GRAFANA_INI
sed -i "s|;serve_from_sub_path =.*|serve_from_sub_path = true|" $GRAFANA_INI
sed -i "s|;allow_sign_up =.*|allow_sign_up = false|" $GRAFANA_INI

systemctl restart grafana-server
echo "Waiting for Grafana to load..."
secs=$((10))
while [ $secs -gt 0 ]; do
   echo -ne "$secs\033[0K\r"
   sleep 1
   : $((secs--))
done

if [ -f "$WS_CONF" ]; then
    sed -i "/$WS_MATCH1/i \ \ \ \ # Proxy Grafana." "$WS_CONF"
    sed -i "/$WS_MATCH1/i \ \ \ \ location ~ ^/(grafana/|grafana/login) {" "$WS_CONF"
    sed -i "/$WS_MATCH1/i \ \ \ \ \ \ proxy_set_header Host \$host;" "$WS_CONF"
    sed -i "/$WS_MATCH1/i \ \ \ \ \ \ proxy_pass http://grafana;" "$WS_CONF"
    sed -i "/$WS_MATCH1/i \ \ \ \ }" "$WS_CONF"
    sed -i "/$WS_MATCH1/i \\\n" "$WS_CONF"
    sed -i "/$WS_MATCH1/i \ \ \ \ # Proxy Grafana Live WebSocket connections." "$WS_CONF"
    sed -i "/$WS_MATCH1/i \ \ \ \ location /grafana/api/live/ {" "$WS_CONF"
    sed -i "/$WS_MATCH1/i \ \ \ \ \ \ proxy_http_version 1.1;" "$WS_CONF"
    sed -i "/$WS_MATCH1/i \ \ \ \ \ \ proxy_set_header Upgrade \$http_upgrade;" "$WS_CONF"
    sed -i "/$WS_MATCH1/i \ \ \ \ \ \ proxy_set_header Connection \$connection_upgrade;" "$WS_CONF"
    sed -i "/$WS_MATCH1/i \ \ \ \ \ \ proxy_set_header Host \$host;" "$WS_CONF"
    sed -i "/$WS_MATCH1/i \ \ \ \ \ \ proxy_pass http://grafana;" "$WS_CONF"
    sed -i "/$WS_MATCH1/i \ \ \ \ }" "$WS_CONF"

    sed -i "/$WS_MATCH2/i # This is required to proxy Grafana Live WebSocket connections." "$WS_CONF"
    sed -i "/$WS_MATCH2/i map \$http_upgrade \$connection_upgrade {" "$WS_CONF"
    sed -i "/$WS_MATCH2/i \ \ default upgrade;" "$WS_CONF"
    sed -i "/$WS_MATCH2/i \ \ '' close;" "$WS_CONF"
    sed -i "/$WS_MATCH2/i }" "$WS_CONF"
    sed -i "/$WS_MATCH1/i \\\n" "$WS_CONF"
    sed -i "/$WS_MATCH2/i upstream grafana {" "$WS_CONF"
    sed -i "/$WS_MATCH2/i \ \ server localhost:3000;" "$WS_CONF"
    sed -i "/$WS_MATCH2/i }" "$WS_CONF"
    systemctl restart nginx
else
    echo "No app configuration done to server file, please report to:
    -> https://forge.switnet.net/switnet/quick-jibri-installer/issues"
fi

echo "
# Setup Grafana credentials.
"
curl -s -k -u "admin:admin" -X \
PUT -H "Content-Type: application/json;charset=UTF-8" -d \
"{
  \"oldPassword\": \"admin\",
  \"newPassword\": \"$GRAFANA_PASS\",
  \"confirmNew\": \"$GRAFANA_PASS\"
}" http://127.0.0.1:3000/api/user/password; echo ""

echo "
# Create InfluxDB datasource
"
curl -s -k -u "admin:$GRAFANA_PASS" -X \
POST -H 'Content-Type: application/json;charset=UTF-8' -d \
'{
    "name": "InfluxDB",
    "type": "influxdb",
    "url": "http://127.0.0.1:8086",
    "access": "proxy",
    "isDefault": true,
    "database": "jitsi"
}' http://127.0.0.1:3000/api/datasources; echo ""

echo "
# Add Grafana Dashboard
"
grafana_host="http://127.0.0.1:3000"
grafana_cred="admin:$GRAFANA_PASS"
grafana_datasource="InfluxDB"
ds=(11969);
for d in "${ds[@]}"; do
  echo "Processing $d: "
  j="$(curl -s -k -u "$grafana_cred" "$grafana_host"/api/gnet/dashboards/"$d" | jq .json)"
  curl -s -k -u "$grafana_cred" -XPOST -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    -d "{
    \"dashboard\": $j,
    \"overwrite\": true,
    \"inputs\": [{
        \"name\": \"DS_INFLUXDB\",
        \"type\": \"datasource\",
        \"pluginId\": \"influxdb\",
        \"value\": \"$grafana_datasource\"
        }]
    }" $grafana_host/api/dashboards/import; echo ""
done

echo "
Go check:

>>    http://$DOMAIN/grafana/

(emphasis on the trailing \"/\") to review configuration and dashboards.

User: admin
Password: $GRAFANA_PASS

Please save it somewhere safe.
"
read -n 1 -s -r -p "Press any key to continue..."$'\n'
