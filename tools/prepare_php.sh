#!/bin/bash
# Automated PHP environment build for Nextcloud.
# SwITNet Ltd © - 2024, https://switnet.net/
# GPLv3 or later.

PHPVER=$1
STABLE_PHP="$(apt-cache madison php|grep -v ppa|awk -F'[:+]' 'NR==1{print $2}')"
DISTRO_RELEASE="$(lsb_release -sc)"
PHP_REPO="$(apt-cache policy | awk '/http/&&/php/{print$2}' | awk -F "/" 'NR==1{print$5}')"
PHP_REPO_URL="http://ppa.launchpad.net/ondrej/php/ubuntu"
PHP_FPM_DIR="/etc/php/$PHPVER/fpm"
PHP_INI="$PHP_FPM_DIR/php.ini"
PHP_CONF="/etc/php/$PHPVER/fpm/pool.d/www.conf"
TMP_GPG_REPO="$(mktemp -d)"

if [ $# -ne 1 ]; then
  echo "Usage: $0 8.2"
  exit 1
fi

install_aval_package() {
for i in $1
  do
     if [ -z "$(apt-cache madison "$i" 2>/dev/null)" ]; then
     echo " > Package $i not available on repo."
     else
     echo " > Add package $i to the install list"
     packages="$packages $i"
     fi
 done
 echo "$packages"
 apt-get -y install $packages #< don't quote.
 packages=""
}

add_gpg_keyring() {
apt-key adv --recv-keys --keyserver keyserver.ubuntu.com "$1"
apt-key export "$1" | gpg --dearmour | tee "$TMP_GPG_REPO"/"$1".gpg >/dev/null
apt-key del "$1"
mv "$TMP_GPG_REPO"/"$1".gpg /etc/apt/trusted.gpg.d/
}

add_php_repo() {
if [ "$PHP_REPO" = "php" ]; then
    echo "PHP $PHPVER already installed"
    apt-get -q2 update
    apt-get -yq2 dist-upgrade
else
    echo "# Adding Ondrej PHP $PHPVER PPA Repository"
    add_gpg_keyring E5267A6C
    echo "deb [arch=amd64] $PHP_REPO_URL $DISTRO_RELEASE main" | \
    tee /etc/apt/sources.list.d/php"$PHPVER".list
    apt-get update -q2
fi
}

add_php_repo

install_aval_package " \
            imagemagick \
            php$PHPVER-fpm \
            php$PHPVER-bcmath \
            php$PHPVER-bz2 \
            php$PHPVER-cli \
            php$PHPVER-cgi \
            php$PHPVER-curl \
            php$PHPVER-gd \
            php$PHPVER-gmp \
            php$PHPVER-imagick \
            php$PHPVER-intl \
            php$PHPVER-json \
            php$PHPVER-ldap \
            php$PHPVER-mbstring \
            php$PHPVER-pgsql \
            php$PHPVER-redis \
            php$PHPVER-soap \
            php$PHPVER-xml \
            php$PHPVER-xmlrpc \
            php$PHPVER-zip \
            redis-server \
            unzip \
            "

#System related
install_ifnot smbclient
sed -i "s|.*env\[HOSTNAME\].*|env\[HOSTNAME\] = \$HOSTNAME|" "$PHP_CONF"
sed -i "s|.*env\[PATH\].*|env\[PATH\] = /usr/local/bin:/usr/bin:/bin|" "$PHP_CONF"
sed -i "s|.*env\[TMP\].*|env\[TMP\] = /tmp|" "$PHP_CONF"
sed -i "s|.*env\[TMPDIR\].*|env\[TMPDIR\] = /tmp|" "$PHP_CONF"
sed -i "s|.*env\[TEMP\].*|env\[TEMP\] = /tmp|" "$PHP_CONF"
sed -i "s|;clear_env = no|clear_env = no|" "$PHP_CONF"

echo "
Tunning PHP.ini...
"
# Change values in php.ini (increase max file size)
# max_execution_time
sed -i "s|max_execution_time =.*|max_execution_time = 3500|g" "$PHP_INI"
# max_input_time
sed -i "s|max_input_time =.*|max_input_time = 3600|g" "$PHP_INI"
# memory_limit
sed -i "s|memory_limit =.*|memory_limit = 512M|g" "$PHP_INI"
# post_max
sed -i "s|post_max_size =.*|post_max_size = 1025M|g" "$PHP_INI"
# upload_max
sed -i "s|upload_max_filesize =.*|upload_max_filesize = 1024M|g" "$PHP_INI"

phpenmod opcache
{

echo "# OPcache settings for Nextcloud"
echo "opcache.enable=1"
echo "opcache.enable_cli=1"
echo "opcache.interned_strings_buffer=8"
echo "opcache.max_accelerated_files=10000"
echo "opcache.memory_consumption=256"
echo "opcache.save_comments=1"
echo "opcache.revalidate_freq=1"
echo "opcache.validate_timestamps=1"
} >> "$PHP_INI"

update-alternatives --set php           /usr/bin/php"$STABLE_PHP"
update-alternatives --set php-fpm.sock  /run/php/php"$STABLE_PHP"-fpm.sock
update-alternatives --set php-cgi      	/usr/bin/php-cgi"$STABLE_PHP"
update-alternatives --set php-cgi-bin   /usr/lib/cgi-bin/php"$STABLE_PHP"
update-alternatives --set phar          /usr/bin/phar"$STABLE_PHP"
update-alternatives --set phar.phar     /usr/bin/phar.phar"$STABLE_PHP"

systemctl restart php"$PHPVER"-fpm.service
