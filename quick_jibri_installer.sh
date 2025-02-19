#!/bin/bash
# Quick Jibri Installer - *buntu (LTS) based systems.
# SwITNet Ltd © - 2024, https://switnet.net/
# GPLv3 or later.
{
echo "Started at $(date +'%Y-%m-%d %H:%M:%S')" >> qj-installer.log

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

# SYSTEM SETUP
JITSI_REPO=$(apt-cache policy | awk '/jitsi/&&/stable/{print$3}' | awk -F / 'NR==1{print$1}')
APACHE_2=$(dpkg-query -W -f='${Status}' apache2 2>/dev/null | grep -c "ok installed")
NGINX=$(dpkg-query -W -f='${Status}' nginx 2>/dev/null | grep -c "ok installed")
DIST=$(lsb_release -sc)
GOOGL_REPO="/etc/apt/sources.list.d/dl_google_com_linux_chrome_deb.list"
GOOGLE_ACTIVE_REPO=$(apt-cache policy | awk '/chrome/{print$3}' | awk -F "/" 'NR==1{print$2}')
PROSODY_REPO="$(apt-cache policy | awk '/prosody/{print$3}' | awk -F "/" 'NR==1{print$2}')"
PUBLIC_IP="$(dig -4 +short myip.opendns.com @resolver1.opendns.com)"
NL="$(printf '\n  ')"
NODEJS_VER="18"
JITSI_GPG_KEY="/etc/apt/trusted.gpg.d/jitsi-key.gpg.key"
PROSODY_GPG_KEY="/etc/apt/trusted.gpg.d/prosody-debian-packages.key"
NODEJS_GPG_KEY="/etc/apt/keyrings/nodesource.gpg"
TODAY=$(date +%s)
NEXT_LTS_DATE=$(date -d 2024-04-01 +%s)
CERT_CHOICE_DEBCONF="Generate a new self-signed certificate (You will later get a chance to obtain a Let's encrypt certificate)"

printwc() {
    printf "%b$2%b" "$1" "${Color_Off}"
}
exit_ifinstalled() {
	if [ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -c "ok installed")" == "1" ]; then
        echo -e "\nThis instance already has $1 installed, exiting..."
        echo -e "Please try again on a clean system."
        echo -e " If you think this is an error, please report to:"
        echo -e "  -> https://forge.switnet.net/switnet/quick-jibri-installer/issues"
		exit
	fi
}
exit_ifinstalled jitsi-meet

rename_distro() {
    if [ "$DIST" = "$1" ]; then
        DIST="$2"
    fi
}
#Trisquel distro upstream referencing.
rename_distro nabia  focal
rename_distro aramo  jammy

install_ifnot() {
    if [ "$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -c "ok installed")" == "1" ]; then
        echo " $1 is installed, skipping..."
    else
        printf "\n---- Installing %s ----" "$1"
        apt-get -yq2 install "$1"
    fi
}
check_serv() {
    if [ "$APACHE_2" -eq 1 ]; then
        echo -e "\nThe recommended setup is using NGINX, exiting...\n"
        exit
    elif [ "$NGINX" -eq 1 ]; then
    printf "\nWebserver already installed!\n"
    else
        printf "\nInstalling nginx webserver!\n"
        install_ifnot nginx
    fi
}
check_snd_driver() {
    printf "\n# Checking ALSA - Loopback module..."
    echo "snd-aloop" | tee -a /etc/modules
    modprobe snd-aloop
    if [ "$(lsmod|awk '/snd_aloop/{print$1}'|awk 'NR==1')" = "snd_aloop" ]; then
        echo -e "\n#-----------------------------------------------------------------------"
        echo "# Audio driver seems - OK."
        echo -e "#-----------------------------------------------------------------------\n"
    else
        echo -e "\n#-----------------------------------------------------------------------"
        echo "# Your audio driver might not be able to load."
        echo "# We'll check the state of this Jibri with our 'test-jibri-env.sh' tool."
        echo -e "#-----------------------------------------------------------------------\n"
        #Test tool
        if [ "$MODE" = "debug" ]; then
            bash "$PWD"/tools/test-jibri-env.sh -m debug
        else
            bash "$PWD"/tools/test-jibri-env.sh
        fi
        read -n 1 -s -r -p "Press any key to continue..."$'\n'
    fi
}
# sed limiters for add-jibri-node.sh variables
var_dlim() {
    grep -n "$1" add-jibri-node.sh|head -n1|cut -d ":" -f1
}
add_gpg_keyring() {
    apt-key adv --recv-keys --keyserver keyserver.ubuntu.com \$1
    apt-key export \$1 | gpg --dearmour | tee /tmp/\$1.gpg >/dev/null
    apt-key del \$1
    mv /tmp/\$1.gpg /etc/apt/trusted.gpg.d/
}
add_prosody_repo() {
    echo "Add Prosody repo"
    if [ "$PROSODY_REPO" = "main" ]; then
        echo "Prosody repository already installed"
    else
        echo "deb [signed-by=$PROSODY_GPG_KEY] http://packages.prosody.im/debian $DIST main" \
            > /etc/apt/sources.list.d/prosody.list
        curl -s https://prosody.im/files/prosody-debian-packages.key \
            > "$PROSODY_GPG_KEY"
        apt-get update -q2
    fi
}
dpkg-compare() {
    dpkg --compare-versions "$(dpkg-query -f='${Version}' --show "$1")" "$2" "$3"
}
wait_seconds() {
    secs=$(($1))
    while [ $secs -gt 0 ]; do
       echo -ne "$secs\033[0K\r"
       sleep 1
       : $((secs--))
    done
}
print_title() {
    printwc "${Blue}" "\n#--------------------------------------------------"
    printwc "${Blue}" "\n# $1"
    printwc "${Blue}" "\n#--------------------------------------------------\n"
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
clear
printwc "${Green}" '
########################################################################
                    Welcome to Jitsi/Jibri Installer
########################################################################
                    by Software, IT & Networks Ltd

Featuring:
- Jibri Recording and YouTube Streaming
- Jibri Recordings Access via Nextcloud
- Grafana Statistics
- Etherpad
- Whiteboard
- Customized brandless mode
- Recurring updater

Learn more about these at,
Main repository: https://forge.switnet.net/switnet/quick-jibri-installer
Wiki and documentation: https://forge.switnet.net/switnet/quick-jibri-installer/wiki\n\n'
sleep .1
read -n 1 -s -r -p "Press any key to continue..."$'\n'

#Check if user is root
if ! [ "$(id -u)" = 0 ]; then
   echo "You need to be root or have sudo privileges!"
   exit 0
fi

    printf "\nOS: %s" "$(lsb_release -sd)"
if [ "$DIST" = "focal" ] || \
   [ "$DIST" = "jammy" ] || \
   [ "$DIST" = "noble" ]; then
    printf "\nGood, this is a supported platform!"
else
    printf "\nSorry, this platform is not supported... exiting"
    exit
fi
#Suggest 22.04 LTS release over 20.04 in April 2024
if [ "$DIST" = "focal" ]; then
  if [ "$TODAY" -gt "$NEXT_LTS_DATE" ]; then
    echo "  > $(lsb_release -sc), even when it's compatible and functional."
    echo -n "    We suggest to use the next (LTS) release, for longer"
    echo " support and security reasons."
    read -n 1 -s -r -p "Press any key to continue..."$'\n'
  else
    echo "Focal is supported."
  fi
fi

#Check system resources
printf "\n\nVerifying System Resources:"
if [ "$(nproc --all)" -lt 4 ];then
    printf "\nWarning!: The system do not meet the minimum CPU"
    printf " requirements for Jibri to run."
    printf "\n>> We recommend 4 cores/threads for Jibri!\n"
    CPU_MIN="N"
else
    printf "\nCPU Cores/Threads: OK (%s)\n" "$(nproc --all)"
    CPU_MIN="Y"
fi
sleep .1
### Test RAM size (8GB min) ###
mem_available="$(grep MemTotal /proc/meminfo| grep -o '[0-9]\+')"
if [ "$mem_available" -lt 7700000 ]; then
    printf "\nWarning!: The system do not meet the minimum RAM"
    printf " requirements for Jibri to run."
    printf "\n>> We recommend 8GB RAM for Jibri!\n\n"
    MEM_MIN="N"
else
    printf "\nMemory: OK (%s) MiB\n\n" "$((mem_available/1024))"
    MEM_MIN="Y"
fi
sleep .1
if [ "$CPU_MIN" = "Y" ] && [ "$MEM_MIN" = "Y" ];then
    echo "All requirements seems meet!"
    printf "\n    - We hope you have a nice recording/streaming session\n"
else
    printf "CPU (%s)/RAM (%s MiB)" "$(nproc --all)" "$((mem_available/1024))"
    printf " does NOT meet minimum recommended requirements!"
    printf "\nEven when you can use the videoconferencing sessions, we"
    printf " advice to increase the resources in order to user Jibri.\n\n"
sleep .1
    while [ "$CONTINUE_LOW_RES" != "yes" ] && [ "$CONTINUE_LOW_RES" != "no" ]
    do
    read -p "> Do you want to continue?: (yes or no)$NL" -r CONTINUE_LOW_RES
    if [ "$CONTINUE_LOW_RES" = "no" ]; then
            echo " - See you next time with more resources!..."
            exit
    elif [ "$CONTINUE_LOW_RES" = "yes" ]; then
            printf "\n - We highly recommend to increase the server resources."
            printf "\n - Otherwise, please think about adding dedicated"
            printf " jibri nodes instead.\n\n"
    fi
    done
fi
sleep .1
if [ "$CONTINUE_LOW_RES" = "yes" ]; then
echo 'This server will likely have issues due the lack of resources.
If you plan to enable other components such as,

 - JRA via Nextcloud
 - Grafana
 - Etherpad
 - Whiteboards
 - Connect additional Jibri Nodes
 - Others

>>> We highly recommend to increase resources of this server. <<<

For now we advice to disable the Jibri service locally and add an external
Jibri node once this installation has finished, using our script:

 >> add-jibri-node.sh'
printf "\nSo you can add a Jibri server on a instance with enough resources.\n\n"
sleep .1
    while [ "$DISABLE_LOCAL_JIBRI" != "yes" ] && [ "$DISABLE_LOCAL_JIBRI" != "no" ]
    do
    read -p "> Do you want to disable local jibri service?: (yes or no)$NL" -r DISABLE_LOCAL_JIBRI
        if [ "$DISABLE_LOCAL_JIBRI" = "no" ]; then
            printf " - Please keep in mind that we might not support"
            printf " underpowered servers.\n"
        elif [ "$DISABLE_LOCAL_JIBRI" = "yes" ]; then
            printf " - You can add dedicated jibri nodes later, see more"
            printf " at the wiki.\n"
        fi
    done
fi
sleep .1
#Check system oriented porpuse
apt-get -q2 update
SYSTEM_DE="$(apt-cache search "ubuntu-(desktop|mate-desktop)"|awk '{print$1}'|xargs|sed 's|$| trisquel triskel trisquel-mini|')"
SYSTEM_DE_ARRAY=( "$SYSTEM_DE" )
printf "\nChecking for common desktop system oriented purpose....\n"
for de in "${SYSTEM_DE_ARRAY[@]}"
do
    if [ "$(dpkg-query -W -f='${Status}' "$de" 2>/dev/null | grep -c "ok installed")" == "1" ]; then
        printf "\n > This instance has %s installed, exiting...\n" "$de"
        printf "\nPlease avoid using this installer on a desktop-user"
        printf " oriented GNU/Linux system.\n"
        printf "This is an unsupported use, as it will likely BREAK YOUR"
        printf " SYSTEM, so please don't.\n"
        exit
    else
        printf " > No standard desktop environment for user oriented"
        printf " porpuse detected, good!, continuing...\n\n"
    fi
done
sleep .1
#Prosody repository
add_prosody_repo
sleep .1
# Jitsi-Meet Repo
printf "\nAdd Jitsi repo\n"
if [ "$JITSI_REPO" = "stable" ]; then
    printf " - Jitsi stable repository already installed\n\n"
else
    echo "deb [signed-by=$JITSI_GPG_KEY] http://download.jitsi.org stable/" \
        > /etc/apt/sources.list.d/jitsi-stable.list
    curl -s https://download.jitsi.org/jitsi-key.gpg.key \
        > "$JITSI_GPG_KEY"
    apt-get update -q2
    JITSI_REPO="stable"
fi
sleep .1
#Default to LE SSL?
while [ "$LE_SSL" != "yes" ] && [ "$LE_SSL" != "no" ]
do
read -p "> Do you plan to use Let's Encrypt SSL certs?: (yes or no)$NL" -r LE_SSL
if [ "$LE_SSL" = yes ]; then
    printf " - We'll setup Let's Encrypt SSL certs.\n\n"
else
    printf " - We'll let you choose later on for it."
    printf "   Please be aware that a valid SSL cert is required for"
    printf " some features to work properly.\n\n"
fi
done
sleep .1
#Set domain
if [ "$LE_SSL" = "yes" ]
then
  while [ "$ANS_JD" != "yes" ]
  do
    read -p "> Please set your domain (or subdomain) here: (e.g.: jitsi.domain.com)$NL" -r JITSI_DOMAIN
    read -p "  > Did you mean?: $JITSI_DOMAIN (yes or no)$NL" -r ANS_JD
    if [ "$ANS_JD" = "yes" ]
    then
      echo "   - Alright, let's use $JITSI_DOMAIN."
    else
      echo "   - Please try again."
    fi
  done
sleep .1
  #Sysadmin email
    while [ -z "$SYSADMIN_EMAIL" ]
    do
      read -p "$NL  > Set sysadmin email (this is a mandatory field):$NL" -r SYSADMIN_EMAIL
    done
sleep .1
  #Simple DNS test
    if [ "$PUBLIC_IP" = "$(dig -4 +short "$JITSI_DOMAIN"||awk -v RS='([0-9]+\\.){3}[0-9]+' 'RT{print RT}')" ]; then
        printf "\nServer public IP  & DNS record for"
        printf " %s seems to match, continuing..." "$JITSI_DOMAIN"
    else
        echo -n "Server public IP ($PUBLIC_IP) & DNS record for $JITSI_DOMAIN"
        echo " don't seem to match."
        echo -n "  > Please check your dns records are applied and updated,"
        echo " otherwise components may fail."
        read -p "  > Do you want to continue?: (yes or no)$NL" -r DNS_CONTINUE
        if [ "$DNS_CONTINUE" = "yes" ]; then
            echo "  - We'll continue anyway..."
        else
            echo "  - Exiting for now..."
            exit
        fi
    fi
fi
sleep .1
# Requirements
printf "\nWe'll start by installing system requirements this may take"
printf " a while please be patient...\n"
apt-get dist-upgrade -yq2

apt-get -y install \
                    apt-show-versions \
                    bmon \
                    curl \
                    ffmpeg \
                    git \
                    htop \
                    jq \
                    net-tools \
                    rsync \
                    ssh \
                    unzip \
                    wget

if [ "$LE_SSL" = "yes" ]; then
apt-get -y install \
                certbot
    if [ "$(dpkg-query -W -f='${Status}' ufw 2>/dev/null | grep -c "ok installed")" == "1"  ]; then
        echo "# Disable pre-installed ufw, more on firewall see:"
        echo "    > https://forge.switnet.net/switnet/quick-jibri-installer/wiki/Firewall"
        ufw disable
    fi
fi

echo "# Check and Install HWE kernel if possible..."
HWE_VIR_MOD="$(apt-cache madison linux-image-generic-hwe-"$(lsb_release -sr)" \
             2>/dev/null|head -n1|grep -c "hwe-$(lsb_release -sr)")"
if [ "$HWE_VIR_MOD" = "1" ]; then
    apt-get -y install \
    linux-image-generic-hwe-"$(lsb_release -sr)" \
    linux-tools-generic-hwe-"$(lsb_release -sr)"
else
    apt-get -y install \
    linux-image-generic \
    linux-modules-extra-"$(uname -r)"
fi

check_serv

echo "
#--------------------------------------------------
# Install Jitsi Framework
#--------------------------------------------------
"
if [ "$LE_SSL" = "yes" ]; then
    echo "set jitsi-meet/cert-choice	select	$CERT_CHOICE_DEBCONF" \
        | debconf-set-selections
    echo "jitsi-videobridge2	jitsi-videobridge/jvb-hostname	string	$JITSI_DOMAIN" \
        | debconf-set-selections
    echo "jitsi-meet-web-config	jitsi-meet/email	string $SYSADMIN_EMAIL" \
        | debconf-set-selections
fi
echo "jitsi-meet-web-config	jitsi-meet/jaas-choice	boolean	false" \
        | debconf-set-selections
apt-get -y install \
                jitsi-meet \
                jibri \
                openjdk-11-jre-headless

# Fix RAND_load_file error
#https://github.com/openssl/openssl/issues/7754#issuecomment-444063355
sed -i "/RANDFILE/d" /etc/ssl/openssl.cnf

#--------------------------------------------------
print_title "Install NodeJS $NODEJS_VER.x"
#--------------------------------------------------
if [ "$(dpkg-query -W -f='${Status}' nodejs 2>/dev/null | grep -c "ok")" == "1" ]; then
    echo "Nodejs is installed, skipping..."
else
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o "$NODEJS_GPG_KEY"
    echo "deb [signed-by=$NODEJS_GPG_KEY] https://deb.nodesource.com/node_$NODEJS_VER.x nodistro main" | \
        tee /etc/apt/sources.list.d/nodesource.list
    apt-get update -q2
    apt-get install -yq2 nodejs

    echo "Installing nodejs esprima package..."
    npm install -g esprima
fi

if [ "$(npm list -g esprima 2>/dev/null | grep -c "empty")" == "1" ]; then
    echo "Installing nodejs esprima package..."
    npm install -g esprima
elif [ "$(npm list -g esprima 2>/dev/null | grep -c "esprima")" == "1" ]; then
    echo "Good. Esprima package is already installed"
fi

echo "# Installing Google Chrome / ChromeDriver"
if [ "$GOOGLE_ACTIVE_REPO" = "main" ]; then
    echo "Google repository already set."
else
    echo "Installing Google Chrome Stable"
    curl -s https://dl.google.com/linux/linux_signing_key.pub | \
    gpg --dearmor | tee /etc/apt/trusted.gpg.d/google-chrome-key.gpg  >/dev/null
    echo "deb http://dl.google.com/linux/chrome/deb/ stable main" | tee "$GOOGL_REPO"
fi
apt-get -q2 update
apt-get install -yq2 google-chrome-stable
rm -rf "$GOOGL_REPO"

G_CHROME=$(apt-cache madison google-chrome-stable|awk '{print$3}'|cut -d. -f1-3)
CHROMELAB_URL="https://googlechromelabs.github.io/chrome-for-testing"
CHD_LTST_DWNL=$(curl -s $CHROMELAB_URL/known-good-versions-with-downloads.json | jq -r ".versions[].downloads.chromedriver | select(. != null) | .[].url" | grep linux64 | grep "$G_CHROME" | tail -1)
CHD_LTST=$(awk -F '/' '{print$7}' <<< "$CHD_LTST_DWNL")
GCMP_JSON="/etc/opt/chrome/policies/managed/managed_policies.json"

if [ -f /usr/local/bin/chromedriver ]; then
    echo "Chromedriver already installed."
else
    echo "Installing Chromedriver"
    wget -q "$CHD_LTST_DWNL" \
         -O /tmp/chromedriver_linux64.zip
    unzip -o /tmp/chromedriver_linux64.zip -d /usr/local/bin/
    mv /usr/local/bin/chromedriver-linux64/chromedriver /usr/local/bin/chromedriver
    chown root:root /usr/local/bin/chromedriver
    chmod 0755 /usr/local/bin/chromedriver
    rm -rf /tmp/chromedriver_linux64.zip
fi

printf "\nCheck Google Software Working...\n"
/usr/bin/google-chrome --version
/usr/local/bin/chromedriver --version | awk '{print$1,$2}'

printf "\nRemove Chrome warning...\n"
mkdir -p /etc/opt/chrome/policies/managed
echo '{ "CommandLineFlagSecurityWarningsEnabled": false }' > "$GCMP_JSON"

## JMS system tune up
if [ "$MODE" = "debug" ]; then
    bash "$PWD"/mode/jms-stu.sh -m debug
else
    bash "$PWD"/mode/jms-stu.sh
fi

echo '
########################################################################
                    Please Setup Your Installation
########################################################################
'
# MEET / JIBRI SETUP
DOMAIN="$(find /etc/prosody/conf.d/ -name \*.lua|awk -F'.cfg' '!/localhost/{print $1}'|xargs basename)"
WS_CONF="/etc/nginx/sites-available/$DOMAIN.conf"
JB_AUTH_PASS="$(tr -dc "a-zA-Z0-9#*=" < /dev/urandom | fold -w 10 | head -n1)"
JB_REC_PASS="$(tr -dc "a-zA-Z0-9#*=" < /dev/urandom | fold -w 10 | head -n1)"
PROSODY_FILE="/etc/prosody/conf.d/$DOMAIN.cfg.lua"
PROSODY_SYS="/etc/prosody/prosody.cfg.lua"
JICOFO_SIP="/etc/jitsi/jicofo/sip-communicator.properties"
MEET_CONF="/etc/jitsi/meet/$DOMAIN-config.js"
JIBRI_CONF="/etc/jitsi/jibri/jibri.conf"
JVB2_CONF="/etc/jitsi/videobridge/config"
JVB2_SIP="/etc/jitsi/videobridge/sip-communicator.properties"
DIR_RECORD="/var/jbrecord"
REC_DIR="/home/jibri/finalize_recording.sh"
JB_NAME="Jibri Sessions"
LE_RENEW_LOG="/var/log/letsencrypt/renew.log"
MOD_LISTU="https://prosody.im/files/mod_listusers.lua"
MOD_LIST_FILE="/usr/lib/prosody/modules/mod_listusers.lua"
MJS_RAND_TAIL="$(tr -dc "a-zA-Z0-9" < /dev/urandom | fold -w 4 | head -n1)"
MJS_USER="jbsync_$MJS_RAND_TAIL"
MJS_USER_PASS="$(tr -dc "a-zA-Z0-9#_*=" < /dev/urandom | fold -w 32 | head -n1)"
FQDN_HOST="fqdn"
JIBRI_XORG_CONF="/etc/jitsi/jibri/xorg-video-dummy.conf"
WS_MATCH1="# ensure all static content can always be found first"
WS_MATCH2="external_api.js"
MEET_MATCH1="disable simulcast support."
export DOMAIN

# Make sure we can rely on the match strings.
printf "> Testing match strings on config files.\n"
test_match "$WS_MATCH1" "$WS_CONF"
test_match "$WS_MATCH2" "$WS_CONF"
test_match "$MEET_MATCH1" "$MEET_CONF"

# Rename hostname for jitsi server
while [ "$FQDN_HOST" != "yes" ] && [ "$FQDN_HOST" != "no" ] && [ -n "$FQDN_HOST" ]
do
  printf "> Set %s as a fqdn hostname?: (yes or no)\n" "$DOMAIN" && \
  read -p "Leave empty to default to your current one ($(hostname -f)):$NL" -r FQDN_HOST
  if [ "$FQDN_HOST" = "yes" ]; then
    printf " - %s will be used as fqdn hostname, changes will show on reboot.\n\n" "$DOMAIN"
    hostnamectl set-hostname "${DOMAIN}"
    sed -i "1i ${PUBLIC_IP} ${DOMAIN}" /etc/hosts
  else
    printf " - %s will be keep.\n\n" "$(hostname -f)"
  fi
done
sleep .1
#Participant
printf "> Do you want to translate 'Participant' to your own language?\n"
sleep .1
read -p "Leave empty to use the default one (English):$NL" -r L10N_PARTICIPANT
sleep .1
#Me
printf "\n> Do you want to translate 'me' to your own language?
This must be a really small word to present one self.
Some suggestions might be: yo (Spanish) | je (French) | ich (German)\n"
sleep .1
read -p "Leave empty to use the default one (English):$NL" -r L10N_ME

#Drop unsecure TLS
while [ "$DROP_TLS1" != "yes" ] && [ "$DROP_TLS1" != "no" ]
do
    read -p "> Do you want to drop support for unsecure protocols TLSv1.0/1.1 now: (yes or no)$NL" -r DROP_TLS1
    if [ "$DROP_TLS1" = "no" ]; then
        printf " - TLSv1.0/1.1 will remain.\n\n"
    elif [ "$DROP_TLS1" = "yes" ]; then
        printf " - TLSv1.0/1.1 will be dropped\n\n"
    fi
done
sleep .1
#Brandless  Mode
while [ "$ENABLE_BLESSM" != "yes" ] && [ "$ENABLE_BLESSM" != "no" ]
do
    read -p "> Do you want to install customized \"brandless mode\"?: (yes or no)$NL" -r ENABLE_BLESSM
    if [ "$ENABLE_BLESSM" = "no" ]; then
        printf " - Brandless mode won't be set.\n\n"
    elif [ "$ENABLE_BLESSM" = "yes" ]; then
        printf " - Brandless mode will be set.\n\n"
    fi
done
sleep .1
#Welcome Page
while [ "$ENABLE_WELCP" != "yes" ] && [ "$ENABLE_WELCP" != "no" ]
do
    read -p "> Do you want to disable the Welcome page: (yes or no)$NL" -r ENABLE_WELCP
    if [ "$ENABLE_WELCP" = "yes" ]; then
        printf " - Welcome page will be disabled.\n\n"
    elif [ "$ENABLE_WELCP" = "no" ]; then
        printf " - Welcome page will be enabled.\n\n"
    fi
done
sleep .1
#Close page
while [ "$ENABLE_CLOCP" != "yes" ] && [ "$ENABLE_CLOCP" != "no" ]
do
    read -p "> Do you want to enable the close page on room exit: (yes or no)$NL" -r ENABLE_CLOCP
    if [ "$ENABLE_CLOCP" = "yes" ]; then
        printf " - Close page will be enabled.\n\n"
    elif [ "$ENABLE_CLOCP" = "no" ]; then
        printf " - Close page will be kept disabled.\n\n"
    fi
done
sleep .1
# Set authentication method
printf "\n> Jitsi Meet Auth Method selection.\n"
PS3='Select the authentication method for your Jitsi Meet instance: '
options=("Local" "JWT" "None")
select opt in "${options[@]}"
do
    case $opt in
        "Local")
            printf "\n  > Users are created manually using prosodyctl,"
            printf " only moderators can open a room or launch recording.\n"
            ENABLE_SC="yes"
            break
            ;;
        "JWT")
            printf "\n  > A external app manage the token usage/creation,"
            printf " like RocketChat does.\n"
            ENABLE_JWT="yes"
            break
            ;;
        "None")
            printf "\n  > Everyone can access the room as moderators as"
            printf " there is no auth mechanism.\n"
            break
            ;;
        *) echo "Invalid option $REPLY, choose 1, 2 or 3";;
    esac
done
sleep .1
# Set jibris default resolution
printf "\n> What jibri resolution should be the default for this and all"
printf " the following jibri nodes?\n"
PS3='The more resolution the more resources jibri will require to record properly: '
jib_res=("HD 720" "FHD 1080")
select res in "${jib_res[@]}"
do
    case $res in
        "HD 720")
            printf "\n  > HD (1280x720) is good enough for most cases,"
            printf " and requires a moderate high hw requirements.\n\n"
            JIBRI_RES="720"
            break
            ;;
        "FHD 1080")
            printf "\n  > Full HD (1920x1080) is the best resolution"
            printf " available, it also requires high hw requirements.\n\n"
            JIBRI_RES="1080"
            break
            ;;
        *) printf "\nInvalid option «%s», choose 1 or 2\n\n" "$REPLY"
        ;;
    esac
done
sleep .1
if [ "$JIBRI_RES" = "720" ]; then
    JIBRI_RES_CONF="\"1280x720\""
    JIBRI_RES_XORG_CONF="1280 720"
fi

if [ "$JIBRI_RES" = "1080" ]; then
    JIBRI_RES_CONF="\"1920x1080\""
    JIBRI_RES_XORG_CONF="1920 1080"
fi

##Jigasi
while [ "$ENABLE_TRANSCRIPT" != "yes" ] && [ "$ENABLE_TRANSCRIPT" != "no" ]
do
    read -p "> Do you want to setup Jigasi Transcription: (yes or no)
#( Please check requirements at: https://forge.switnet.net/switnet/quick-jibri-installer )$NL" -r ENABLE_TRANSCRIPT
    if [ "$ENABLE_TRANSCRIPT" = "no" ]; then
        printf " - Jigasi Transcription won't be enabled.\n\n"
    elif [ "$ENABLE_TRANSCRIPT" = "yes" ]; then
        printf " - Jigasi Transcription will be enabled.\n\n"
    fi
done
sleep .1

#Start configuration
echo '
########################################################################
                  Start Jitsi Framework configuration
########################################################################
'
JibriBrewery=JibriBrewery
INT_CONF="/usr/share/jitsi-meet/interface_config.js"
INT_CONF_ETC="/etc/jitsi/meet/$DOMAIN-interface_config.js"

ssl_wa() {
if [ "$LE_SSL" = "yes" ]; then
  systemctl stop "$1"
  certbot certonly --standalone --renew-by-default --agree-tos --email "$5" -d "$6" --non-interactive
  sed -i "s|/etc/jitsi/meet/$3.crt|/etc/letsencrypt/live/$3/fullchain.pem|" "$4"
  sed -i "s|/etc/jitsi/meet/$3.key|/etc/letsencrypt/live/$3/privkey.pem|" "$4"
  systemctl restart "$1"
  #Add cron
  if [ "$(crontab -l|sed 's|#.*$||g'|grep -c 'weekly certbot renew')" = 0 ];then
    crontab -l | { cat; echo "@weekly certbot renew --${2} > $LE_RENEW_LOG 2>&1"; } | crontab -
  else
    echo "Crontab seems to be already in place, skipping."
  fi
  crontab -l
fi
}

check_jibri() {
if [ "$(dpkg-query -W -f='${Status}' "jibri" 2>/dev/null | grep -c "ok installed")" == "1" ]
then
    systemctl restart jibri
    systemctl restart jibri-icewm
    systemctl restart jibri-xorg
else
    echo "Jibri service not installed"
fi
}

# Restarting services
restart_services() {
    systemctl restart jitsi-videobridge2
    systemctl restart jicofo
    systemctl restart prosody
    check_jibri
}

# Configure Jvb2
sed -i "/shard.HOSTNAME/s|localhost|$DOMAIN|" "$JVB2_SIP"

# Configure Jibri
if [ "$ENABLE_SC" = "yes" ]; then
  if [ ! -f "$MOD_LIST_FILE" ]; then
  printf "\n-> Adding external module to list prosody users...\n"
  curl -s "$MOD_LISTU" > "$MOD_LIST_FILE"

  printf "Now you can check registered users with:"
  printf " \n  prosodyctl mod_listusers\n"
    else
  printf "Prosody support for listing users seems to be enabled.check with:"
  printf " \n  prosodyctl mod_listusers\n"
  fi

fi
sleep .1
#Enable jibri recording
cat  << REC-JIBRI >> "$PROSODY_FILE"

VirtualHost "recorder.$DOMAIN"
  modules_enabled = {
    "ping";
  }
  authentication = "internal_hashed"

REC-JIBRI

#Enable Jibri withelist
sed -i "s|-- muc_lobby_whitelist|muc_lobby_whitelist|" "$PROSODY_FILE"

#Fix Jibri conectivity issues
sed -i "s|c2s_require_encryption = .*|c2s_require_encryption = false|" "$PROSODY_SYS"
sed -i "/c2s_require_encryption = false/a \\
\\
consider_bosh_secure = true" "$PROSODY_SYS"

if [ -n "$L10N_PARTICIPANT" ]; then
    sed -i "s|PART_USER=.*|PART_USER=\"$L10N_PARTICIPANT\"|" jm-bm.sh
fi
if [ -n "$L10N_ME" ]; then
    sed -i "s|LOCAL_USER=.*|LOCAL_USER=\"$L10N_ME\"|" jm-bm.sh
fi


### Prosody users
prosodyctl register jibri auth."$DOMAIN" "$JB_AUTH_PASS"
prosodyctl register recorder recorder."$DOMAIN" "$JB_REC_PASS"

## JICOFO
# /etc/jitsi/jicofo/sip-communicator.properties
cat  << BREWERY >> "$JICOFO_SIP"
#org.jitsi.jicofo.auth.URL=XMPP:$DOMAIN
#org.jitsi.jicofo.auth.URL=EXT_JWT:$DOMAIN
org.jitsi.jicofo.jibri.BREWERY=$JibriBrewery@internal.auth.$DOMAIN
org.jitsi.jicofo.jibri.PENDING_TIMEOUT=90
#org.jitsi.jicofo.auth.DISABLE_AUTOLOGIN=true
BREWERY

# Jibri tweaks for /etc/jitsi/meet/$DOMAIN-config.js
sed -i "s|conference.$DOMAIN|internal.auth.$DOMAIN|" "$MEET_CONF"

#Enable recording & livestreaming by default.
echo "> Patching config.js to enable recording and livestreaming by default..."
echo "  Read more about patches at the patches folder."
envsubst < \
  patches/jitsi-meet/001-jitsi-meet-enable-livestreaming-and-recording.patch | \
  patch --no-backup-if-mismatch -d / -p1

#Prepare hidden domain for jibri/jigasi silent users.
sed -i "/fileRecordingsServiceEnabled: false,/a \\
    hiddenDomain: \'recorder.$DOMAIN\'," "$MEET_CONF"
# Recording directory
if [ ! -d "$DIR_RECORD" ]; then
    mkdir "$DIR_RECORD"
fi
chown -R jibri:jibri "$DIR_RECORD"

cat << REC_DIR > "$REC_DIR"
#!/bin/bash

RECORDINGS_DIR="$DIR_RECORD"

echo "This is a dummy finalize script" > /tmp/finalize.out
echo "The script was invoked with recordings directory $RECORDINGS_DIR." >> /tmp/finalize.out
echo "You should put any finalize logic (renaming, uploading to a service" >> /tmp/finalize.out
echo "or storage provider, etc.) in this script" >> /tmp/finalize.out

chmod -R 770 \$RECORDINGS_DIR

LJF_PATH="\$(find \$RECORDINGS_DIR -exec stat --printf="%Y\t%n\n" {} \; | sort -nr|sed 1d|awk '{print\$2}'| grep -v "meta\|_" | head -n1)"
NJF_NAME="\$(find \$LJF_PATH |grep "mp4"|sed "s|\$LJF_PATH/||"|cut -d "." -f1)"
NJF_PATH="\$RECORDINGS_DIR/\$NJF_NAME"
mv \$LJF_PATH \$NJF_PATH

exit 0
REC_DIR
chown jibri:jibri "$REC_DIR"
chmod +x "$REC_DIR"

## New Jibri Config (2020)
mv "$JIBRI_CONF" ${JIBRI_CONF}-dpkg-file
cp files/jibri.conf "$JIBRI_CONF"
sed -i "s|JIBRI_RES_CONF|$JIBRI_RES_CONF|g" "$JIBRI_CONF"
sed -i "s|DIR_RECORD|$DIR_RECORD|g" "$JIBRI_CONF"
sed -i "s|REC_DIR|$REC_DIR|g" "$JIBRI_CONF"
sed -i "s|JB_NAME|$JB_NAME|g" "$JIBRI_CONF"
sed -i "s|DOMAIN|$DOMAIN|g" "$JIBRI_CONF"
sed -i "s|JibriBrewery|$JibriBrewery|g" "$JIBRI_CONF"
sed -i "s|JB_AUTH_PASS|$JB_AUTH_PASS|g" "$JIBRI_CONF"
sed -i "s|JB_REC_PASS|$JB_REC_PASS|g" "$JIBRI_CONF"

#Jibri xorg resolution
sed -i "s|[[:space:]]Virtual .*|Virtual $JIBRI_RES_XORG_CONF|" "$JIBRI_XORG_CONF"

#Create receiver user
useradd -m -g jibri "$MJS_USER"
echo "$MJS_USER:$MJS_USER_PASS" | chpasswd

#Create ssh key and restrict connections
sudo su "$MJS_USER" -c "ssh-keygen -t rsa -f ~/.ssh/id_rsa -b 4096 -o -a 100 -q -N ''"
#Allow password authentication
sed -i "s|PasswordAuthentication .*|PasswordAuthentication yes|" /etc/ssh/sshd_config
systemctl restart sshd

#Setting varibales for add-jibri-node.sh
sed -i "s|MAIN_SRV_DIST=.*|MAIN_SRV_DIST=\"$DIST\"|" add-jibri-node.sh
sed -i "s|MAIN_SRV_REPO=.*|MAIN_SRV_REPO=\"$JITSI_REPO\"|" add-jibri-node.sh
sed -i "s|MAIN_SRV_DOMAIN=.*|MAIN_SRV_DOMAIN=\"$DOMAIN\"|" add-jibri-node.sh
sed -i "s|JB_NAME=.*|JB_NAME=\"$JB_NAME\"|" add-jibri-node.sh
sed -i "s|JibriBrewery=.*|JibriBrewery=\"$JibriBrewery\"|" add-jibri-node.sh
sed -i "s|JB_AUTH_PASS=.*|JB_AUTH_PASS=\"$JB_AUTH_PASS\"|" add-jibri-node.sh
sed -i "s|JB_REC_PASS=.*|JB_REC_PASS=\"$JB_REC_PASS\"|" add-jibri-node.sh
sed -i "s|MJS_USER=.*|MJS_USER=\"$MJS_USER\"|" add-jibri-node.sh
sed -i "s|MJS_USER_PASS=.*|MJS_USER_PASS=\"$MJS_USER_PASS\"|" add-jibri-node.sh
sed -i "s|JIBRI_RES_CONF=.*|JIBRI_RES_CONF=\"$JIBRI_RES_CONF\"|" add-jibri-node.sh
sed -i "s|JIBRI_RES_XORG_CONF=.*|JIBRI_RES_XORG_CONF=\"$JIBRI_RES_XORG_CONF\"|" add-jibri-node.sh
sed -i "$(var_dlim 0_LAST),$(var_dlim 1_LAST){s|LETS: .*|LETS: $(date -R)|}" add-jibri-node.sh
echo "Last file edition at: $(grep "LETS:" add-jibri-node.sh|head -n1|awk -F'LETS:' '{print$2}')"

#-- Setting variables for add-jvb2-node.sh
g_conf_value() {
  grep "$1" "$JVB2_CONF"|sed "s|$1||"
}
JVB_HOSTNAME=$(g_conf_value JVB_HOSTNAME=)
JVB_HOST=$(g_conf_value JVB_HOST=)
JVB_PORT=$(g_conf_value JVB_PORT=)
JVB_SECRET=$(g_conf_value JVB_SECRET=)
JVB_OPTS=$(g_conf_value JVB_OPTS=)
JAVA_SYS_PROPS=$(g_conf_value JAVA_SYS_PROPS=)

g_sip_value() {
  grep "$1" "$JVB2_SIP" |cut -d "=" -f2
}
DISABLE_AWS_HARVESTER=$(g_sip_value DISABLE_AWS_HARVESTER=)
STUN_MAPPING_HARVESTER_ADDRESSES=$(g_sip_value STUN_MAPPING_HARVESTER_ADDRESSES=)
ENABLE_STATISTICS=$(g_sip_value ENABLE_STATISTICS=)
SHARD_HOSTNAME=$(g_sip_value shard.HOSTNAME=)
SHARD_DOMAIN=$(g_sip_value shard.DOMAIN=)
SHARD_PASSWORD=$(g_sip_value shard.PASSWORD=)
MUC_JID=$(g_sip_value MUC_JIDS=)

##-- Replacing on add-jvb2-node.sh
sed -i "s|JVB_HOSTNAME=.*|JVB_HOSTNAME=$JVB_HOSTNAME|" add-jvb2-node.sh
sed -i "s|JVB_HOST=.*|JVB_HOST=$JVB_HOST|" add-jvb2-node.sh
sed -i "s|JVB_PORT=.*|JVB_PORT=$JVB_PORT|" add-jvb2-node.sh
sed -i "s|JVB_SECRET=.*|JVB_SECRET=$JVB_SECRET|" add-jvb2-node.sh
sed -i "s|JVB_OPTS=.*|JVB_OPTS=$JVB_OPTS|" add-jvb2-node.sh
sed -i "s|SYS_PROPS=.*|SYS_PROPS=$JAVA_SYS_PROPS|" add-jvb2-node.sh
#-
sed -i "s|AWS_HARVEST=.*|AWS_HARVEST=$DISABLE_AWS_HARVESTER|" add-jvb2-node.sh
sed -i "s|STUN_MAPPING=.*|STUN_MAPPING=$STUN_MAPPING_HARVESTER_ADDRESSES|" add-jvb2-node.sh
sed -i "s|ENABLE_STATISTICS=.*|ENABLE_STATISTICS=$ENABLE_STATISTICS|" add-jvb2-node.sh
sed -i "s|SHARD_HOSTNAME=.*|SHARD_HOSTNAME=$SHARD_HOSTNAME|" add-jvb2-node.sh
sed -i "s|SHARD_DOMAIN=.*|SHARD_DOMAIN=$SHARD_DOMAIN|" add-jvb2-node.sh
sed -i "s|SHARD_PASS=.*|SHARD_PASS=$SHARD_PASSWORD|" add-jvb2-node.sh
sed -i "s|MUC_JID=.*|MUC_JID=$MUC_JID|" add-jvb2-node.sh

sed -i "s|MAIN_SRV_DIST=.*|MAIN_SRV_DIST=\"$DIST\"|" add-jvb2-node.sh
sed -i "s|MAIN_SRV_REPO=.*|MAIN_SRV_REPO=\"$JITSI_REPO\"|" add-jvb2-node.sh
sed -i "s|MAIN_SRV_DOMAIN=.*|MAIN_SRV_DOMAIN=\"$DOMAIN\"|" add-jvb2-node.sh
sed -i "s|MJS_USER=.*|MJS_USER=\"$MJS_USER\"|" add-jvb2-node.sh
sed -i "s|MJS_USER_PASS=.*|MJS_USER_PASS=\"$MJS_USER_PASS\"|" add-jvb2-node.sh
##--

#nginx -tlsv1/1.1
if [ "$DROP_TLS1" = "yes" ];then
    printf "\nDropping TLSv1/1.1\n\n"
    sed -i "s|TLSv1 TLSv1.1||" /etc/nginx/nginx.conf
elif [ "$DROP_TLS1" = "no" ];then
    printf "\nNo TLSv1/1.1 dropping was done.\n\n"
else
    echo -n "No condition meet, please report to:"
    echo "https://forge.switnet.net/switnet/quick-jibri-installer/issues"
fi
sleep .1
#================== Setup prosody conf file =================

###Setup secure rooms
if [ "$ENABLE_SC" = "yes" ]; then
    SRP_STR=$(grep -n "VirtualHost \"$DOMAIN\"" "$PROSODY_FILE" | awk -F ':' 'NR==1{print$1}')
    SRP_END=$((SRP_STR + 10))
    sed -i "$SRP_STR,$SRP_END{s|authentication = \"jitsi-anonymous\"|authentication = \"internal_hashed\"|}" "$PROSODY_FILE"
    sed -i "s|// anonymousdomain: 'guest.example.com'|anonymousdomain: \'guest.$DOMAIN\'|" "$MEET_CONF"

    #Secure room initial user
    read -p "Set username for secure room moderator:$NL" -r SEC_ROOM_USER
    read -p "Secure room moderator password:$NL" -r SEC_ROOM_PASS
    prosodyctl register "$SEC_ROOM_USER" "$DOMAIN" "$SEC_ROOM_PASS"
sleep .1
    printf "\nSecure rooms are being enabled...\n"
    echo -n "You'll be able to login Secure Room chat with '${SEC_ROOM_USER}' "
    echo "or '${SEC_ROOM_USER}@${DOMAIN}' using the password you just entered."
    echo "If you have issues with the password refer to your sysadmin."
    sed -i "s|#org.jitsi.jicofo.auth.URL=XMPP:|org.jitsi.jicofo.auth.URL=XMPP:|" "$JICOFO_SIP"
    sed -i "s|SEC_ROOM=.*|SEC_ROOM=\"on\"|" jm-bm.sh
fi
sleep .1
###JWT
if [ "$ENABLE_JWT" = "yes" ]; then
    printf "\nJWT auth is being setup...\n"
    if [ "$MODE" = "debug" ]; then
        bash "$PWD"/mode/jwt.sh -m debug
    else
        bash "$PWD"/mode/jwt.sh
    fi
fi
sleep .1
#Guest allow
#Change back lobby - https://community.jitsi.org/t/64769/136
if [ "$ENABLE_SC" = "yes" ];then
    cat << P_SR >> "$PROSODY_FILE"
-- #Change back lobby - https://community.jitsi.org/t/64769/136
VirtualHost "guest.$DOMAIN"
    authentication = "anonymous"
    c2s_require_encryption = false
    speakerstats_component = "speakerstats.$DOMAIN"
    main_muc = "conference.$DOMAIN"

    modules_enabled = {
      "speakerstats";
    }

P_SR
fi

#======================
# Custom settings
#Start with video muted by default
sed -i "s|// startWithVideoMuted: false,|startWithVideoMuted: true,|" "$MEET_CONF"

#Start with audio muted but admin
sed -i "s|// startAudioMuted: 10,|startAudioMuted: 2,|" "$MEET_CONF"

#Disable/enable welcome page
[ "$ENABLE_WELCP" = "yes" ] && ENABLE_WELCP_BOL=true
[ "$ENABLE_WELCP" = "no" ] && ENABLE_WELCP_BOL=false
export ENABLE_WELCP_BOL
echo "> Patching config.js to modify welcompage behavior..."
echo "  Read more about patches at the patches folder."
envsubst < \
  patches/jitsi-meet/002-jitsi-meet-welcome-page-on-off.patch | \
  patch --no-backup-if-mismatch -d / -p1

#Enable close page
[ "$ENABLE_CLOCP" = "yes" ] && \
    sed -i "s|// enableClosePage:.*|enableClosePage: true,|" "$MEET_CONF"
[ "$ENABLE_CLOCP" = "no" ] && \
    sed -i "s|// enableClosePage:.*|enableClosePage: false,|" "$MEET_CONF"

#Add pre-join screen by default, since it improves YouTube autoplay capabilities
#pre-join screen by itself don't require autorization by moderator, don't confuse with lobby which does.
sed -i "s|// prejoinPageEnabled:.*|prejoinPageEnabled: true,|" "$MEET_CONF"

#Set HD resolution and widescreen format
sed -i "/$MEET_MATCH1/i \/\/ Start QJI - Set resolution and widescreen format" "$MEET_CONF"
sed -i "/$MEET_MATCH1/i \ \ \ \ resolution: 720," "$MEET_CONF"
sed -i "/$MEET_MATCH1/i \ \ \ \ constraints: {" "$MEET_CONF"
sed -i "/$MEET_MATCH1/i \ \ \ \ \ \ aspectRatio: 16 \/ 9," "$MEET_CONF"
sed -i "/$MEET_MATCH1/i \ \ \ \ \ \ \ \ \ video: {" "$MEET_CONF"
sed -i "/$MEET_MATCH1/i \ \ \ \ \ \ \ \ \ \ \ \ \ height: {" "$MEET_CONF"
sed -i "/$MEET_MATCH1/i \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ ideal: 720," "$MEET_CONF"
sed -i "/$MEET_MATCH1/i \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ max: 720," "$MEET_CONF"
sed -i "/$MEET_MATCH1/i \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ min: 180" "$MEET_CONF"
sed -i "/$MEET_MATCH1/i \ \ \ \ \ \ \ \ \ \ \ \ \ }," "$MEET_CONF"
sed -i "/$MEET_MATCH1/i \ \ \ \ \ \ \ \ \ \ \ \ \ width: {" "$MEET_CONF"
sed -i "/$MEET_MATCH1/i \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ ideal: 1280," "$MEET_CONF"
sed -i "/$MEET_MATCH1/i \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ max: 1280," "$MEET_CONF"
sed -i "/$MEET_MATCH1/i \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ \ min: 320" "$MEET_CONF"
sed -i "/$MEET_MATCH1/i \ \ \ \ \ \ \ \ \ \ \ \ \ }" "$MEET_CONF"
sed -i "/$MEET_MATCH1/i \ \ \ \ \ \ \ \ \ }" "$MEET_CONF"
sed -i "/$MEET_MATCH1/i \ \ \ \ \ }," "$MEET_CONF"
sed -i "/$MEET_MATCH1/i \/\/ End QJI" "$MEET_CONF"

#Check config file
printf "\n# Checking %s file for errors\n" "$MEET_CONF"
CHECKJS=$(esvalidate "$MEET_CONF"| cut -d ":" -f2)
if [ -z "$CHECKJS" ]; then
    printf "\n# The %s configuration seems correct. =)\n" "$MEET_CONF"
else
    echo -e "\nWatch out!, there seems to be an issue on $MEET_CONF line:
$CHECKJS
Most of the times this is due upstream changes, please report to
https://forge.switnet.net/switnet/quick-jibri-installer/issues\n"
fi

#Enable jibri services
systemctl enable jibri
systemctl enable jibri-xorg
systemctl enable jibri-icewm
restart_services
if [ "$DISABLE_LOCAL_JIBRI" = "yes" ]; then
    systemctl stop jibri*
    systemctl disable jibri
    systemctl disable jibri-xorg
    systemctl disable jibri-icewm
    # Manually apply permissions since finalize_recording.sh won't be
    # triggered under this server options.
    chmod -R 770 "$DIR_RECORD"
fi

# Fix prosody not able to read SSL Certs
chown -R root:prosody /etc/prosody/certs/
chmod -R 650 /etc/prosody/certs/

#SSL workaround
if [ "$(dpkg-query -W -f='${Status}' nginx 2>/dev/null | grep -c "ok installed")" -eq 1 ]; then
    ssl_wa nginx nginx "$DOMAIN" "$WS_CONF" "$SYSADMIN_EMAIL" "$DOMAIN"
    install_ifnot python3-certbot-nginx
else
    echo "No webserver found please report."
fi
#Brandless  Mode
if [ "$ENABLE_BLESSM" = "yes" ]; then
    echo "Custom brandless mode will be enabled."
    sed -i "s|ENABLE_BLESSM=.*|ENABLE_BLESSM=\"on\"|" jitsi-updater.sh
    if [ "$MODE" = "debug" ]; then
        bash "$PWD"/jm-bm.sh -m debug
    else
        bash "$PWD"/jm-bm.sh
    fi
fi

# Applying best practives for interface config.js
printf "\n> Setting up custom interface_config.js according to best practices."
cp "$INT_CONF" "$INT_CONF_ETC"

#Tune webserver for interface_config.js
if [ -f "$WS_CONF" ]; then
    sed -i "/external_api.js/i \\\n" "$WS_CONF"
    sed -i "/external_api.js/i \ \ \ \ location = \/interface_config.js {" "$WS_CONF"
    sed -i "/external_api.js/i \ \ \ \ \ \ \ \ alias \/etc\/jitsi\/meet\/$DOMAIN-interface_config.js;" "$WS_CONF"
    sed -i "/external_api.js/i \ \ \ \ }" "$WS_CONF"
    sed -i "/external_api.js/i \\\n" "$WS_CONF"
    systemctl reload nginx
else
    printf "No interface_config.js configuration done to server file,"
    printf " please report to:"
    printf "    -> https://forge.switnet.net/switnet/quick-jibri-installer/issues"
fi
sleep .1
#Jigasi w/VOSK backend.
if [ "$ENABLE_TRANSCRIPT" = "yes" ]; then
    printf "\nJigasi with VOSK backend will be enabled."
    if [ "$MODE" = "debug" ]; then
        bash "$PWD"/jigasi-vosk-backend.sh -m debug
    else
        bash "$PWD"/jigasi-vosk-backend.sh
    fi
fi
sleep .1
#Prevent JMS conecction issue
if [ -z "$(awk "/127.0.0.1/&&/$DOMAIN/{print\$1}" /etc/hosts)" ];then
    sed -i "/127.0.0.1/a \\
127.0.0.1       $DOMAIN" /etc/hosts
else
  echo "Local host already in place..."
fi

check_snd_driver

echo "
########################################################################
                    Installation complete!!
           for customized support: http://switnet.net
########################################################################
"
apt-get -y autoremove
apt-get autoclean

echo "Rebooting in..."
wait_seconds 15
}  > >(tee -a qj-installer.log) 2> >(tee -a qj-installer.log >&2)
reboot
