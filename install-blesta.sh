#!/usr/bin/env bash

# Check if the script is run with root privileges
if [ "$EUID" -ne 0 ]
  then echo "Please run as root on a fresh minimal install of Almalinux 8 or 9."
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
    echo "#         a FRESH MINIMAL INSTALLATION of AlmaLinux 8 or 9!        #"
    echo "#                                                                  #"
    echo "####################################################################"
    echo -e "\e[0m"  # Reset color
}

# Call the function to display the banner
print_banner

# For Almalinux 8 or 9 only
almarelease=$(cat /etc/almalinux-release)
if [[ $almarelease =~ 'release 9' ]]
then
  echo 'Running Almalinux 9'
elif  [[ $almarelease =~ 'release 8' ]]
then
  echo 'Running Almalinux 8'
else
  echo 'Not running Almalinux 8 or 9, exiting...'
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
    read hostname

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
    read email_address
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
sed -c -i "s/\SELINUX=.*/SELINUX=disabled/" /etc/sysconfig/selinux

# Disable firewalld
if systemctl is-active --quiet firewalld; then
    echo "Firewalld is running. Stopping and disabling it."
    systemctl stop firewalld
    systemctl disable firewalld
else
    echo "Firewalld is not running."
fi

# Update to the latest release
echo "Updating system packages..."
dnf update -y
dnf install epel-release -y
dnf install htop iftop nano wget zip unzip -y

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

# Install PHP 8.2
. /etc/os-release && dnf -y install https://rpms.remirepo.net/enterprise/remi-release-$(rpm -E %$ID).rpm && dnf clean all
dnf install php82-php-{cli,pdo,fpm,zip,gd,xml,mysqlnd,opcache,mbstring,bcmath,pear,gmp,intl,imap,pecl-mailparse,ioncube-loader,soap} -y

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

# Update httpd.conf
export HTTP_CFG_PATH=/etc/httpd/conf/httpd.conf
sed -i 's/User apache/User blesta/' $HTTP_CFG_PATH
sed -i 's/Group apache/Group blesta/' $HTTP_CFG_PATH

systemctl enable httpd
systemctl enable mariadb
systemctl start httpd
systemctl start mariadb
systemctl restart php82-php-fpm

# Obtain Let's Encrypt certificate
echo "Obtaining Let's Encrypt certificate for $hostname..."
certbot --apache -d "$hostname" --non-interactive --agree-tos --email "webmaster@$hostname" || {
    echo "Certbot failed. Check /var/log/letsencrypt/letsencrypt.log for details."
    exit 1
}

# Ensure the Let's Encrypt renewal cron job is set up
echo "Setting up Let's Encrypt certificate renewal..."
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
su - blesta -c "cd /home/blesta/public_html/; /usr/bin/php82 /home/blesta/public_html/index.php install -dbhost localhost -dbport 3306 -dbname blesta -dbuser blesta -dbpass $mysqlblestapass -hostname $hostname -docroot /home/blesta/public_html/ -domain $hostname $license_key_option -firstname $first_name -lastname $last_name -email $email_address -username admin -password $blestaadminpass"

echo "Creating a cron job"
# * * * * * /usr/bin/php82 -q /home/blesta/public_html/index.php cron > /dev/null 2>&1
echo "* * * * * /usr/bin/php82 -q /home/blesta/public_html/index.php cron > /dev/null 2>&1" | sudo -u blesta crontab -


## Output admin user and password and URL
echo -e "\e[32mVisit https://$hostname/admin/ to login to Blesta.\e[0m"
echo -e "\e[32mHere are your credentials, save them somewhere safe.\e[0m"
echo -e "\e[32mUsername: admin\e[0m"
echo -e "\e[32mPassword: $blestaadminpass\e[0m"


