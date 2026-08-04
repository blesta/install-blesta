#!/usr/bin/env bash

# The whole script runs inside main(), called on the last line. When piped
# (curl | bash), bash reads the script source from stdin as it executes;
# wrapping the body in a function makes bash parse it all up front, so the
# exec < /dev/tty below can't cut the parser off from the rest of the
# script, and a partially-downloaded script fails to parse instead of
# running half-way.
main() {

# When piped (curl | bash), stdin is the script itself — reattach to the
# terminal so interactive prompts work instead of hitting EOF and looping.
if [ ! -t 0 ]; then
    # Test-open /dev/tty in a subshell: it can exist yet fail to open when
    # there is no controlling terminal (CI, cron, some containers).
    if (exec < /dev/tty) 2>/dev/null; then
        exec < /dev/tty
    else
        echo "Error: This installer is interactive and requires a terminal." >&2
        echo "No TTY is available. Download the script and run it directly:" >&2
        echo "  curl -fsSLO https://raw.githubusercontent.com/blesta/install-blesta/main/install-blesta.sh && bash install-blesta.sh" >&2
        exit 1
    fi
fi

# Check if the script is run with root privileges
if [ "$EUID" -ne 0 ]
  then echo "Please run as root on a fresh minimal install of Almalinux 8, 9, or 10."
  exit
fi

# Print a warning
print_banner() {
    echo -e "\e[1;31m"  # Red color, bold
    echo "####################################################################"
    echo "#                ____  _     _____ ____ _____  _                   #"
    echo "#               | __ )| |   | ____/ ___|_   _|/ \                  #"
    echo "#               |  _ \| |   |  _| \___ \ | | / _ \                 #"
    echo "#               | |_) | |___| |___ ___) || |/ ___ \                #"
    echo "#               |____/|_____|_____|____/ |_/_/   \_\               #"
    echo "#                                                                  #"
    echo "####################################################################"
    echo "#                                                                  #"
    echo "#         WARNING: This script should ONLY be run on               #"
    echo "#         a FRESH MINIMAL INSTALLATION of AlmaLinux 8, 9, or 10!   #"
    echo "#                                                                  #"
    echo "####################################################################"
    echo -e "\e[0m"  # Reset color
}

# Call the function to display the banner
print_banner

# For Almalinux 8, 9, or 10 only
almarelease=$(cat /etc/almalinux-release)
if [[ $almarelease =~ 'release 10' ]]
then
  echo 'Running Almalinux 10'
elif [[ $almarelease =~ 'release 9' ]]
then
  echo 'Running Almalinux 9'
elif  [[ $almarelease =~ 'release 8' ]]
then
  echo 'Running Almalinux 8'
else
  echo 'Not running Almalinux 8, 9, or 10, exiting...'
  exit 1
fi

# Check if Blesta is already installed
if [ -e "/home/blesta/public_html/config/blesta.php" ]; then
 printf "\n /!\ Existing installation detected! Exiting /!\ \\n\n"
exit 1
fi

# Function to check if input is not empty
validate_not_empty() {
    if [ -z "$1" ]; then
        echo -e "\e[34mPlease enter a value for $2.\e[0m"
        return 1
    fi
    return 0
}

# Function to validate email address
validate_email() {
    local email=$1
    local email_regex="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    if [[ ! $email =~ $email_regex ]]; then
        echo -e "\e[34mPlease enter a valid email address.\e[0m"
        return 1
    fi
    return 0
}

# Function to validate if input is a valid Fhostname
validate_fqdn() {
    local hostname="$1"
    if [[ "$hostname" =~ ^([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])(\.([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9]))+$ ]]; then
        return 0
    else
        return 1
    fi
}

# Loop until a valid hostname is provided
while true; do
    # Prompt for Hostname (blue color)
    echo -e "\e[32mPlease enter the Hostname (e.g. account.domain.com) It MUST RESOLVE to this server!:\e[0m"
    read hostname || { echo "No input available (EOF). Exiting." >&2; exit 1; }

    # Validate hostname is not empty
    if ! validate_not_empty "$hostname" "Hostname"; then
        continue
    fi

    # Validate hostname is a valid FQDN
    if ! validate_fqdn "$hostname"; then
        echo "Error: '$hostname' is not a valid FQDN. Please try again."
    else
        echo "Hostname '$hostname' is valid."
        break
    fi
done

# Rest of the things are for Blesta
echo -e "\e[32mThe following information is for your first Staff Account:\e[0m"

# Prompt for Email Address (blue color)
while true; do
    echo -e "\e[32mPlease enter your Email Address:\e[0m"
    read email_address || { echo "No input available (EOF). Exiting." >&2; exit 1; }
    validate_not_empty "$email_address" "Email Address" || continue
    validate_email "$email_address" || continue
    break
done

# Prompt for First Name (blue color)
echo -e "\e[32mPlease enter your First Name:\e[0m"
read first_name
validate_not_empty "$first_name" "First Name" || { echo "Exiting due to empty input."; exit 1; }

# Prompt for Last Name (blue color)
echo -e "\e[32mPlease enter your Last Name:\e[0m"
read last_name
validate_not_empty "$last_name" "Last Name" || { echo "Exiting due to empty input."; exit 1; }

# Prompt for License Key (blue color, can be left blank)
echo -e "\e[32mPlease enter the License Key (or press Enter to fetch a trial license):\e[0m"
read license_key

# Reset color
echo -e "\e[0m"

# Echo all collected information for verification
echo "Hostname: $hostname"
#echo "Domain: $domain"
echo "Email Address: $email_address"
echo "First Name: $first_name"
echo "Last Name: $last_name"
echo "License Key: ${license_key:-Will try to fetch a trial license}"

echo -e "\e[1;31m"
echo "Is the provided information correct? (Type 'y' to proceed)"
echo -e "\e[0m"
read response

if [ "${response,,}" = "y" ]; then
    echo "Proceeding..."
else
    echo "Information not confirmed. Script will now exit."
    exit 1
fi

# No selinux
setenforce 0
# Target the real config file (/etc/sysconfig/selinux is a symlink to it);
# the previous `sed -c` form was an invalid GNU sed option and never persisted
# the change, so SELinux returned to enforcing on reboot.
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config

# Configure firewalld: allow SSH/HTTP/HTTPS ingress, everything egress.
# Keeping 3306 (MariaDB) and 6379 (Redis/Valkey) closed guarantees neither
# is reachable externally. Must run before certbot (HTTP-01 needs port 80).
echo "Configuring firewalld..."
dnf install firewalld -y
systemctl enable firewalld
systemctl start firewalld
firewall-cmd --permanent --zone=public --add-service=http
firewall-cmd --permanent --zone=public --add-service=https
firewall-cmd --permanent --zone=public --add-service=ssh
firewall-cmd --permanent --zone=public --remove-service=cockpit || true
firewall-cmd --permanent --zone=public --remove-service=dhcpv6-client || true
firewall-cmd --reload

# Update to the latest release
echo "Updating system packages..."
dnf update -y
dnf install epel-release -y
dnf install htop iftop nano wget zip unzip rsync which tar util-linux cronie -y

# Make sure the cron daemon runs now and after reboot (minimal cloud images
# may not ship cronie); Blesta's cron job depends on it
systemctl enable --now crond

# Create 'blesta' user
echo "Creating user 'blesta'..."
useradd -m -s /bin/bash blesta

# Create document root directory
echo "Creating document root web directory..."
mkdir -p /home/blesta/public_html
chown blesta:blesta /home/blesta/public_html
chmod 755 /home/blesta/public_html

# Install Apache and Certbot
echo "Installing Apache and Certbot..."
dnf install httpd httpd-tools mod_ssl certbot python3-certbot-apache -y

# Create document root directory
echo "Creating document root directory..."
mkdir -p /home/blesta/public_html
chown blesta:blesta /home/blesta/public_html
chmod 755 /home/blesta/public_html


# Configure Apache to run as 'blesta' user
echo "Configuring Apache to run as 'blesta'..."
cat << EOF > /etc/httpd/conf.d/blesta.conf
<VirtualHost *:80>
    ServerName $hostname
    ServerAdmin webmaster@$hostname
    DocumentRoot /home/blesta/public_html

    <FilesMatch \.php$>
        SetHandler "proxy:unix:/var/opt/remi/php82/run/php-fpm/www.sock|fcgi://localhost/"
    </FilesMatch>

    <Directory /home/blesta/public_html>
        Options Indexes FollowSymLinks MultiViews
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog /var/log/httpd/blesta_error.log
    CustomLog /var/log/httpd/blesta_access.log combined
</VirtualHost>
EOF

# Install MariaDB
dnf install mariadb-server mariadb -y

# Install Redis (EL8/9) or Valkey (EL10) for Blesta caching. Both bind to
# 127.0.0.1 with protected-mode on by default, so no config changes are
# needed for localhost-only operation.
if [[ $almarelease =~ 'release 10' ]]; then
    echo "Installing Valkey..."
    dnf install valkey -y
    cache_service=valkey
else
    echo "Installing Redis..."
    # EL8's default module stream is redis:5; enable redis:6 for parity with
    # EL9 (a no-op failure on EL9, which has no redis module)
    if [[ $almarelease =~ 'release 8' ]]; then
        dnf module enable redis:6 -y
    fi
    dnf install redis -y
    cache_service=redis
fi
systemctl enable "$cache_service"
systemctl start "$cache_service"

# Install PHP 8.2
. /etc/os-release && dnf -y install https://rpms.remirepo.net/enterprise/remi-release-$(rpm -E %$ID).rpm && dnf clean all
dnf install php82-php-{cli,pdo,fpm,zip,gd,xml,mysqlnd,opcache,mbstring,bcmath,pear,gmp,intl,imap,pecl-mailparse,ioncube-loader,soap,pecl-redis6} -y

# Provide a bare `php` on PATH. Blesta's background upgrader falls back to
# `php` when PHP_BINARY is the FPM binary; the SCL install only provides
# /usr/bin/php82, so without this symlink the background upgrade cannot start.
ln -sf /usr/bin/php82 /usr/local/bin/php

# Update php.ini
export PHP_INI_PATH=/etc/opt/remi/php82/php.ini
sed -i 's/memory_limit = 128M/memory_limit = 512M/' $PHP_INI_PATH
sed -i 's/max_execution_time = 30/max_execution_time = 120/' $PHP_INI_PATH
sed -i 's/;max_input_vars = 1000/max_input_vars = 8000/' $PHP_INI_PATH
sed -i 's/expose_php = On/expose_php = Off/' $PHP_INI_PATH
sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 100M/' $PHP_INI_PATH
sed -i 's/post_max_size = 8M/post_max_size = 100M/' $PHP_INI_PATH
sed -i 's/register_argc_argv = Off/register_argc_argv = On/' $PHP_INI_PATH

# Update www.conf
export PHP_WWW_PATH=/etc/opt/remi/php82/php-fpm.d/www.conf
sed -i 's/user = apache/user = blesta/' $PHP_WWW_PATH
sed -i 's/group = apache/group = blesta/' $PHP_WWW_PATH
sed -i 's/listen.acl_users = apache/;listen.acl_users = apache/' $PHP_WWW_PATH
sed -i 's/;listen.owner = nobody/listen.owner = blesta/' $PHP_WWW_PATH
sed -i 's/;listen.group = nobody/listen.group = blesta/' $PHP_WWW_PATH
# Give FPM workers a real PATH. FPM clears the environment by default, which
# breaks exec()'d commands (e.g. Blesta's upgrade dependency checks via `which`).
sed -i 's~^;env\[PATH\].*~env[PATH] = /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin~' $PHP_WWW_PATH
# Fallback: if the packaged www.conf had no commented env[PATH] line to
# uncomment, append one so FPM always gets a PATH
grep -q '^env\[PATH\]' $PHP_WWW_PATH || echo 'env[PATH] = /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin' >> $PHP_WWW_PATH

# Update httpd.conf
export HTTP_CFG_PATH=/etc/httpd/conf/httpd.conf
sed -i 's/User apache/User blesta/' $HTTP_CFG_PATH
sed -i 's/Group apache/Group blesta/' $HTTP_CFG_PATH

systemctl enable httpd
systemctl enable mariadb
systemctl enable php82-php-fpm
systemctl start httpd
systemctl start mariadb
systemctl restart php82-php-fpm

# Obtain Let's Encrypt certificate
echo "Obtaining Let's Encrypt certificate for $hostname..."
certbot --apache -d "$hostname" --non-interactive --agree-tos --email "$email_address" || {
    echo "Certbot failed. Check /var/log/letsencrypt/letsencrypt.log for details."
    exit 1
}

# Enable and start automatic certificate renewal (EPEL certbot uses a
# systemd timer; package install enables it via preset but does not start it)
echo "Enabling automatic Let's Encrypt certificate renewal..."
systemctl enable --now certbot-renew.timer
certbot renew --dry-run

# Restart Apache to apply changes
systemctl restart httpd

# Generate a random mysql password
mysqlrootpass=`< /dev/urandom tr -dc A-Za-z0-9 | head -c12`
mysqlblestapass=`< /dev/urandom tr -dc A-Za-z0-9 | head -c12`

# echo $mysqlrootpass
# echo $mysqlblestapass
# Write the root password to a file
echo "Writing root password to /root/.mysqlpass..."
echo "$mysqlrootpass" | sudo tee /root/.mysqlpass > /dev/null
chmod 600 /root/.mysqlpass

# Secure MariaDB installation by setting root password
echo "Securing MariaDB installation..."
sudo mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '$mysqlrootpass';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

echo "MariaDB secured with root password."

# Download the latest version of Blesta
su - blesta -c "cd /home/blesta/; mkdir /home/blesta/tmp/; cd /home/blesta/tmp/; wget https://www.blesta.com/latest.zip; unzip latest.zip; mv uploads /home/blesta/; mv blesta/* /home/blesta/public_html/; mv blesta/.htaccess /home/blesta/public_html/;"

# Enable the Redis cache block in the config template before install runs, so
# the generated config/blesta.php starts with Redis caching enabled. The
# defaults (127.0.0.1:6379, no password) match the Redis/Valkey install above.
# Blesta falls back silently to file caching if Redis is unreachable.
# The block only exists in Blesta 6.0+ templates; warn instead of silently
# doing nothing if an older release was downloaded.
if grep -q "Configure::set('Blesta.redis'" /home/blesta/public_html/config/blesta-new.php; then
    sed -i "/Configure::set('Blesta.redis'/,/^\/\/ \]);/ s|^// ||" /home/blesta/public_html/config/blesta-new.php
else
    echo "WARNING: No Blesta.redis block found in config template (Blesta 6.0+ only); Redis caching NOT enabled."
fi

# Initiate install of Blesta
echo "Creating MySQL database user and password for Blesta..."

# Create the database, user, and assign privileges
mysql -u root -p"$mysqlrootpass" <<EOF
CREATE DATABASE blesta;
CREATE USER 'blesta'@'localhost' IDENTIFIED BY '$mysqlblestapass';
GRANT ALL PRIVILEGES ON blesta.* TO 'blesta'@'localhost';
FLUSH PRIVILEGES;
EOF

# Check if the operation was successful
if [ $? -eq 0 ]; then
    echo "Database 'blesta' created, user 'blesta' added with the following password:"
    echo "Password: $mysqlblestapass"
else
    echo "An error occurred while setting up the database and user."
    exit 1
fi

# Begin installation of Blesta
# Generate admin password
blestaadminpass=`< /dev/urandom tr -dc A-Za-z0-9 | head -c8`

# Command
# /usr/bin/php82 /home/blesta/public_html/index.php install -dbhost localhost -dbport 3306 -dbname blesta -dbuser blesta -dbpass $mysqlblestapass -hostname $hostname -docroot "/home/blesta/public_html/" -domain $domain -licensekey $license_key -firstname $first_name -lastname $last_name -email $email_address -username admin -password $blestaadminpass
echo "Installing Blesta"
#su - blesta -c "cd /home/blesta/public_html/; /usr/bin/php82 /home/blesta/public_html/index.php install -dbhost localhost -dbport 3306 -dbname blesta -dbuser blesta -dbpass $mysqlblestapass -hostname $hostname -docroot "/home/blesta/public_html/" -domain $domain -licensekey $license_key -firstname $first_name -lastname $last_name -email $email_address -username admin -password $blestaadminpass"

# Check if license key length is at least 20 characters
if [ ${#license_key} -ge 20 ]; then
    license_key_option="-licensekey $license_key"
else
    license_key_option=""
fi

# Execute the installation command with or without license key option
su - blesta -c "cd /home/blesta/public_html/; /usr/bin/php82 /home/blesta/public_html/index.php install -dbhost localhost -dbport 3306 -dbname blesta -dbuser blesta -dbpass $mysqlblestapass -hostname $hostname -docroot /home/blesta/public_html/ -domain $hostname $license_key_option -firstname \"$first_name\" -lastname \"$last_name\" -email $email_address -username admin -password $blestaadminpass"

# Point Blesta's temp_dir outside systemd PrivateTmp. php-fpm runs with
# PrivateTmp=true, so /tmp is a private namespace: upgrade artifacts written
# there are invisible from SSH and destroyed on an FPM restart.
echo "Setting Blesta temp directory to /home/blesta/tmp/..."
mysql -u root -p"$mysqlrootpass" blesta -e "UPDATE settings SET value='/home/blesta/tmp/' WHERE \`key\`='temp_dir';"

echo "Creating a cron job"
# * * * * * /usr/bin/php82 -q /home/blesta/public_html/index.php cron > /dev/null 2>&1
echo "* * * * * /usr/bin/php82 -q /home/blesta/public_html/index.php cron > /dev/null 2>&1" | sudo -u blesta crontab -


## Output admin user and password and URL
echo -e "\e[32mVisit https://$hostname/admin/ to login to Blesta.\e[0m"
echo -e "\e[32mHere are your credentials, save them somewhere safe.\e[0m"
echo -e "\e[32mUsername: admin\e[0m"
echo -e "\e[32mPassword: $blestaadminpass\e[0m"

}

# Call and exit on one line: after stdin is redirected to the terminal,
# bash must never come back to stdin looking for more script to run.
main "$@"; exit $?


