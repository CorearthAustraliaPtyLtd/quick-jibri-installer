#!/bin/bash
# Jitsi Meet brandless mode
# for Debian/*buntu binaries.
# SwITNet Ltd © - 2024, https://switnet.net/
# GNU GPLv3 or later.

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

DOMAIN="$(find /etc/prosody/conf.d/ -name \*.lua|awk -F'.cfg' '!/localhost/{print $1}'|xargs basename)"
CSS_FILE="/usr/share/jitsi-meet/css/all.css"
TITLE_FILE="/usr/share/jitsi-meet/title.html"
INT_CONF="/usr/share/jitsi-meet/interface_config.js"
INT_CONF_ETC="/etc/jitsi/meet/$DOMAIN-interface_config.js"
BUNDLE_JS="/usr/share/jitsi-meet/libs/app.bundle.min.js"
#
JM_IMG_PATH="/usr/share/jitsi-meet/images"
WTM2_PATH="$JM_IMG_PATH/watermark2.png"
WTM2_SVG_PATH="$JM_IMG_PATH/watermark2.svg"
FICON_PATH="$JM_IMG_PATH/favicon2.ico"
REC_ICON_PATH="$JM_IMG_PATH/gnome_record.png"
#
APP_NAME="Conferences"
MOVILE_APP_NAME="Jitsi Meet"
PART_USER="Participant"
LOCAL_USER="me"
#
#SEC_ROOM="TBD"
copy_if_not_there() {
	if [ ! -f "$1" ]; then
        cp images/"$(echo $1|xargs basename)" "$1"
    else
        echo "$(echo $1|xargs basename) file exists, skipping copying..."
    fi
}
echo '
#--------------------------------------------------
# Applying Brandless mode
#--------------------------------------------------
'

#Watermark
copy_if_not_there "$WTM2_PATH"

#Watermark svg
copy_if_not_there "$WTM2_SVG_PATH"

#Favicon
copy_if_not_there "$FICON_PATH"

#Local recording icon
copy_if_not_there "$REC_ICON_PATH"

#Custom / Remove icons
sed -i "s|watermark.png|watermark2.png|g" "$CSS_FILE"
sed -i "s|favicon.ico|favicon2.ico|g" "$TITLE_FILE"
sed -i "s|jitsilogo.png|watermark2.png|g" "$TITLE_FILE"
sed -i "s|logo-deep-linking.png|watermark2.png|g" "$BUNDLE_JS"
sed -i "s|icon-cloud.png|gnome_record.png|g" "$BUNDLE_JS"
#Disable logo and url
if ! grep -q ".leftwatermark{display:none" "$CSS_FILE" ; then
    sed -i "s|.leftwatermark{|.leftwatermark{display:none;|" "$CSS_FILE"
fi
#Replace App logo
sed -i "s|// defaultLogoUrl: .*|    defaultLogoUrl: 'images/watermark2.svg',|" "$MEET_CONF"
#Overwrite favicon svg
cp images/watermark2.svg $JM_IMG_PATH/favicon.svg

#Customize room title
sed -i "s|Jitsi Meet|$APP_NAME|g" "$TITLE_FILE"
sed -i "s| powered by the Jitsi Videobridge||g" "$TITLE_FILE"
sed -i "/appNotInstalled/ s|{{app}}|$MOVILE_APP_NAME|g" /usr/share/jitsi-meet/lang/*

#Custom UI changes
if [ -f "$INT_CONF_ETC" ]; then
    echo "Static interface_config.js exists, skipping modification..."
else
    echo "This setup doesn't have a static interface_config.js, checking changes..."
    echo -e "\nPlease note that brandless mode will also overwrite support links.\n"
    sed -i "21,32 s|Jitsi Meet|$APP_NAME|g" "$INT_CONF"
    sed -i  "s|\([[:space:]]\)APP_NAME:.*| APP_NAME: \'$APP_NAME\',|" "$INT_CONF"
    sed -i "s|Fellow Jitster|$PART_USER|g" "$INT_CONF"
    sed -i "s|'me'|'$LOCAL_USER'|" "$INT_CONF"
    sed -i "s|LIVE_STREAMING_HELP_LINK: .*|LIVE_STREAMING_HELP_LINK: '#',|g" "$INT_CONF"
    sed -i "s|SUPPORT_URL: .*|SUPPORT_URL: '#',|g" "$INT_CONF"
    #Logo 2
    sed -i "s|watermark.png|watermark2.png|g" "$INT_CONF"
    sed -i "s|watermark.svg|watermark2.png|g" "$INT_CONF"
fi
