#!/bin/bash
# Excalidraw Jitsi Backend Installer
#
# Based on:
# - https://community.jitsi.org/t/118883
#
# SwITNet Ltd © - 2024, https://switnet.net/
# GPLv3 or later.

# Reset
Color_Off='\e[0m'       # Text Reset
# Regular Colors
Black='\e[0;30m'        # Black
Red='\e[0;31m'          # Red
Green='\e[0;32m'        # Green
Yellow='\e[0;33m'       # Yellow
Blue='\e[0;34m'         # Blue
Purple='\e[0;35m'       # Purple
Cyan='\e[0;36m'         # Cyan

printwc() {
    printf "%b$2%b" "$1" "${Color_Off}"
}
print_title() {
printwc "${Blue}" "\n#--------------------------------------------------"
printwc "${Blue}" "\n# $1"
printwc "${Blue}" "\n#--------------------------------------------------\n"
}
restart_jibri() {
if [ "$(dpkg-query -W -f='${Status}' "jibri" 2>/dev/null | grep -c "ok installed")" == "1" ]
then
    systemctl restart jibri
    systemctl restart jibri-icewm
    systemctl restart jibri-xorg
else
    echo "Jibri service not installed"
fi
}
restart_services() {
    systemctl restart jitsi-videobridge2
    systemctl restart jicofo
    restart_jibri
    systemctl restart prosody
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
echo -e '\n
########################################################################
                  Excalidraw Jitsi Backend Installer
########################################################################
                    by Software, IT & Networks Ltd
\n'

DOMAIN="$(find /etc/prosody/conf.d/ -name \*.lua|awk -F'.cfg' '!/localhost/{print $1}'|xargs basename)"
WS_CONF="/etc/nginx/sites-available/$DOMAIN.conf"
PROSODY_FILE="/etc/prosody/conf.d/$DOMAIN.cfg.lua"
MEET_CONF="/etc/jitsi/meet/$DOMAIN-config.js"
WS_MATCH1='# ensure all static content can always be found first'
PROS_MATCH1='"av_moderation";'
PROS_MATCH2='breakout_rooms_muc = "breakout.'
PROS_MATCH3='VirtualHost "recorder.'
CONFIG_MATCH1='List of undocumented settings used in jitsi-meet'
EXCALIDRAW_HOME="/opt/excalidraw"
EXCAL_MATCH1="prometheus.metrics(io"
EXCAL_NEW_PORT="9091"
EXCAL_PORT_FILE="$EXCALIDRAW_HOME/backend/src/index.ts"

# Make sure we can rely on the match strings.
printf "Testing match strings on config files.\n"
test_match "$WS_MATCH1" "$WS_CONF"
test_match "$PROS_MATCH1" "$PROSODY_FILE"
test_match "$PROS_MATCH2" "$PROSODY_FILE"
test_match "$PROS_MATCH3" "$PROSODY_FILE"
test_match "$PROS_MATCH3" "$PROSODY_FILE"
test_match "$CONFIG_MATCH1" "$MEET_CONF"

#--------------------------------------------------
print_title "Setup excalidraw backend."
#--------------------------------------------------
adduser --home "$EXCALIDRAW_HOME" --disabled-password --gecos "" excalidraw
git clone https://github.com/jitsi/excalidraw-backend "$EXCALIDRAW_HOME/backend"
test_match "$EXCAL_MATCH1" "$EXCAL_PORT_FILE"

chown -R excalidraw:excalidraw "$EXCALIDRAW_HOME"
cd "$EXCALIDRAW_HOME/backend"
sudo -u excalidraw cp .env.development .env.production

# Use documented port to get some sort of standarization.
if sed -n "/$EXCAL_MATCH1/,/});/p" "$EXCAL_PORT_FILE" |grep -q port: ; then
    echo -e "> Update predefined port for metrics to $EXCAL_NEW_PORT\n"
    sed -i "/$EXCAL_MATCH1/,/});/s|port:.*,|port: $EXCAL_NEW_PORT,|" "$EXCAL_PORT_FILE"
else
    echo -e "> Define new port from default to $EXCAL_NEW_PORT\n"
    sed -i  "/$EXCAL_MATCH1/a \ \ \ \ port: $EXCAL_NEW_PORT," "$EXCAL_PORT_FILE"
fi

printf "Installing npm backend.\n"
sudo -u excalidraw npm install
sudo -u excalidraw npm run build

#--------------------------------------------------
print_title "Setup system & jitsi config files."
#--------------------------------------------------
# Enable websocket on nginx
sed -i "/$WS_MATCH1/i \\\n" "$WS_CONF"
sed -i "/$WS_MATCH1/i \ \ \ \ location = /socket.io/ {" "$WS_CONF"
sed -i "/$WS_MATCH1/i \ \ \ \ \ \ \ \ proxy_pass http://127.0.0.1:3002/socket.io/?\$args;" "$WS_CONF"
sed -i "/$WS_MATCH1/i \ \ \ \ \ \ \ \ proxy_http_version 1.1;" "$WS_CONF"
sed -i "/$WS_MATCH1/i \ \ \ \ \ \ \ \ proxy_set_header Upgrade \$http_upgrade;" "$WS_CONF"
sed -i "/$WS_MATCH1/i \ \ \ \ \ \ \ \ proxy_set_header Connection \"upgrade\";" "$WS_CONF"
sed -i "/$WS_MATCH1/i \ \ \ \ \ \ \ \ proxy_set_header Host \$http_host;" "$WS_CONF"
sed -i "/$WS_MATCH1/i \ \ \ \ \ \ \ \ tcp_nodelay on;" "$WS_CONF"
sed -i "/$WS_MATCH1/i \ \ \ \ }" "$WS_CONF"
sed -i "/$WS_MATCH1/i \\\n" "$WS_CONF"

if grep -rq room_metadata /etc/prosody/conf.d/ ;then
    echo "> Prosody seems to be already configured."
else
    echo "> Setting up prosody for whiteboard..."
    # Modules enabled
    sed -i "/$PROS_MATCH1/a \ \ \ \ \ \ \ \ \"room_metadata\";" "$PROSODY_FILE"
    # Define internal component
    sed -i "/$PROS_MATCH2/a \ \ \ \ room_metadata_component = \"metadata.$DOMAIN\"" "$PROSODY_FILE"
    # Register component
    sed -i "/$PROS_MATCH3/i \\\n" "$PROSODY_FILE"
    sed -i "/$PROS_MATCH3/i Component \"metadata.$DOMAIN\" \"room_metadata_component\"" "$PROSODY_FILE"
    sed -i "/$PROS_MATCH3/i \ \ \ \ muc_component = \"conference.$DOMAIN\"" "$PROSODY_FILE"
    sed -i "/$PROS_MATCH3/i \ \ \ \ breakout_rooms_component = \"breakout.$DOMAIN\"" "$PROSODY_FILE"
    sed -i "/$PROS_MATCH3/i \\\n" "$PROSODY_FILE"
fi

printf "\n# Checking for whitebord setup at %s.\n" "$(basename "$MEET_CONF")"
if [ -z "$(sed -n '/whiteboard: {/,/},/p' "$MEET_CONF")" ]; then
    echo "> No present configuration on current config.js file"
    sed -i "/$CONFIG_MATCH1/i \\\n" "$MEET_CONF"
    sed -i "/$CONFIG_MATCH1/i \ \ \ \ whiteboard: {" "$MEET_CONF"
    sed -i "/$CONFIG_MATCH1/i \ \ \ \ \ \ \ \ enabled: true," "$MEET_CONF"
    sed -i "/$CONFIG_MATCH1/i \ \ \ \ \ \ \ \ collabServerBaseUrl: 'https://$DOMAIN'" "$MEET_CONF"
    sed -i "/$CONFIG_MATCH1/i \ \ \ \ }," "$MEET_CONF"
    sed -i "/$CONFIG_MATCH1/i \\\n" "$MEET_CONF"
else
    echo "> Enabling configuration on current config.js file"
    sed -i "/whiteboard: {/,/},/s|// ||" "$MEET_CONF"
    sed -i "/collabServerBaseUrl:/s|'https://.*'|'https://$DOMAIN'|" "$MEET_CONF"
fi

if  sed -n '/toolbarButtons: \[/,/\],/p' "$MEET_CONF" | \
    grep -v '//'| grep -q whiteboard ; then
    echo "> Whiteboard toolbar already enabled."
elif sed -n '/toolbarButtons: \[/,/\],/p' "$MEET_CONF" | \
     grep -v '//'|grep -q toolbarButtons: ; then 
    echo "> Enabling whiteboard toolbar."
    sed -i "/toolbarButtons:/a \ \ \ \ \ \ \ 'whiteboard'," "$MEET_CONF"
else
    echo "> ToolbarButtons not customized, whiteboard should be enabled by default,"
    echo "  otherwise, please report to: https://forge.switnet.net/switnet/quick-jibri-installer/issues"
fi

printf "\n# Add systemd service\n"
cat << EOF > /etc/systemd/system/excalidraw.service
[Unit]
Description=Excalidraw backend
After=network-online.target

[Service]
User=excalidraw
Group=excalidraw
WorkingDirectory=$EXCALIDRAW_HOME/backend
ExecStart=npm start
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl enable excalidraw.service
systemctl start excalidraw.service

printwc "${Green}" "\nExcalidraw setup complete!\n"
restart_services
