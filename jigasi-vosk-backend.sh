#!/bin/bash
# Quick Jigasi Installer with VOSK backend - *buntu (LTS) based systems.
# SwITNet Ltd © - 2024, https://switnet.net/
# GPLv3 or later.

#Check if user is root
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
echo ''
echo '########################################################################'
echo '                       Jigasi Transcript addon'
echo '########################################################################'
echo '                    by Software, IT & Networks Ltd'
echo ''

exit_if_not_installed jitsi-meet

export DOMAIN="$(find /etc/prosody/conf.d/ -name \*.lua|awk -F'.cfg' '!/localhost/{print $1}'|xargs basename)"
export JIG_TRANSC_PASWD="$(tr -dc "a-zA-Z0-9#*=" < /dev/urandom | fold -w 16 | head -n1)"
JIGASI_CONFIG="/etc/jitsi/jigasi/config"
MEET_CONF="/etc/jitsi/meet/${DOMAIN}-config.js"
JIG_SIP_CONF="/etc/jitsi/jigasi/config"
JIG_SIP_PROP="/etc/jitsi/jigasi/sip-communicator.properties"
#JIG_TRANSC_PASWD_B64="$(echo -n "$JIG_TRANSC_PASWD" | base64)"

apt-get -q2 update

# Disbale 
echo "jigasi	jigasi/sip-account	string	''" | debconf-set-selections
echo "jigasi	jigasi/sip-password	password	''" | debconf-set-selections

echo "Installing Jigasi, SIP configuration disabled by default."
apt-get -y install gettext-base jigasi docker.io

echo "Please select a language for the VOSK transcription model:"
echo "1) Chinese"
echo "2) English"
echo "3) French"
echo "4) German"
echo "5) Hindi"
echo "6) Japanese"
echo "7) Russian"
echo "8) Spanish"

read -p "Enter the number corresponding to your language choice: " lang_choice

case $lang_choice in
    1)
        echo "You selected Chinese."
        VOSK_DOCKER_MODEL="alphacep/kaldi-cn"
        ;;
    2)
        echo "You selected English."
        VOSK_DOCKER_MODEL="alphacep/kaldi-en"
        ;;
    3)
        echo "You selected French."
        VOSK_DOCKER_MODEL="alphacep/kaldi-fr"
        ;;
    4)
        echo "You selected German."
        VOSK_DOCKER_MODEL="alphacep/kaldi-de"
        ;;
    5)
        echo "You selected Hindi."
        VOSK_DOCKER_MODEL="alphacep/kaldi-hi"
        ;;
    6)
        echo "You selected Japanese."
        VOSK_DOCKER_MODEL="alphacep/kaldi-ja"
        ;;
    7)
        echo "You selected Russian."
        VOSK_DOCKER_MODEL="alphacep/kaldi-ru"
        ;;
    8)
        echo "You selected Spanish."
        VOSK_DOCKER_MODEL="alphacep/kaldi-es"
        ;;
    *)
        echo "Invalid selection. Please choose a number between 1 and 8."
        ;;
esac

# Running selected VOSK docker model.
docker run -d -p 2700:2700 ${VOSK_DOCKER_MODEL}:latest

echo "Setting up Jigasi transcript with current platform..."

# Jitsi Meet
echo "> Patching Jitsi Meet's config.js for Transcription support."
echo "  Read more at patches/jigasi/jigasi-meet-config.patch file"
envsubst < patches/jigasi/jigasi-meet-config.patch | patch --no-backup-if-mismatch -d / -p1

# Jigasi
echo "> Patching jigasi's sip-communicator.properties configuration."
echo "  Read more at patches/jigasi/jigasi-sip-properties.patch file"
cp "$JIG_SIP_PROP" ${JIG_SIP_PROP}-dpkg-file
envsubst < patches/jigasi/jigasi-sip-properties.patch | patch --no-backup-if-mismatch -d / -p1

# Create transcribe user on hidden domain.
prosodyctl register transcriber recorder."$DOMAIN" "$JIG_TRANSC_PASWD"

# Restart services.
systemctl restart prosody \
                  jicofo \
                  jigasi \
                  jibri* \
                  jitsi-videobridge2

echo ""
echo "Full transcript files are available at:"
echo "--> /var/lib/jigasi/transcripts/"
echo ""
echo "Happy transcripting!"
echo ""
