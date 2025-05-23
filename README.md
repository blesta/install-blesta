# Blesta bash installer
install-blesta.sh is a bash script installer. It should be run on a fresh minimal install
of AlmaLinux 9.

1. Deploy a new minimal install of AlmaLinux 9
2. Make sure your hostname, e.g. account.domain.com resolves to the server.
3. Run ./install-blesta.sh as root and Follow the prompts.

To run:
````
dnf install curl -y
curl https://raw.githubusercontent.com/blesta/install-blesta/main/install-blesta.sh | sh -s -- --verbose
````

# What does the script do?
- Installs all dependencies
- Installs Apache, PHP 8.2, and MariaDB to recommended requirements.
- Fetches a Let's Encrypt certificate via Certbot
- Installs Blesta and sets a cron job

# Final Output
Final output will look something like the following:

Visit https://account.domain.com/admin/ to login to Blesta.
Here are your credentials, save them somewhere safe.
Username: admin
Password: z9aralEy

It's recommended you change your password after logging in.

