#!/bin/bash
# Function to log messages
log() {
    # Log file location
    log_file="/var/log/script.log"
    # Create the log file and set permissions
    sudo touch "$log_file"
    sudo chmod 644 "$log_file"
    log "Log file created and permissions set."
    
    local message="$1"
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $message" | sudo tee -a "$log_file"
}
# Function to install dependencies
install_dependencies() {
    log "Installing dependencies..."
    sudo apt update
    curl -fsSL https://raw.githubusercontent.com/MuhammadUsamaMX/node18_install/main/script.sh | sudo -E bash -
    sudo apt install -y lsb-release curl mysql-client certbot iptables curl wget sudo nano zip apache2 mariadb-server certbot python3-certbot-apache php-fpm php-mysql php-curl php-dom php-json php-zip php-gd php-xml php-mbstring php-intl php-opcache nodejs npm
    log "Dependencies installed."
    clear
    echo "Dependencies installed."
    sleep 3
}
# Function to display IP information
ipinfo() {
    curl -s ifconfig.me
}
#Check A record of domain name
check_a_record() {
  if dig +short "$1" | grep -q '^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+'; then
    return 0  # A record exists
  else
    return 1  # A record doesn't exist
  fi
}
# Ask the user for the domain name
get_domain_name() {
    read -p "Enter the domain name: " domain_name
    if check_a_record "$domain_name"; then
      echo "A record exists for $domain_name. Exiting."
      echo "Remove A Record of $domain_name in cloudflare"
      exit 0
    else
      clear
    fi
}
zero_trust{
    #Block ports 80,443,3306 and allow port 22
    iptables -A INPUT -p tcp --dport 80 -j DROP
    iptables -A INPUT -p tcp --dport 443 -j DROP
    iptables -A INPUT -p tcp --dport 3306 -j DROP
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    iptables-save 
    iptables-legacy-save
    cd /tmp/
    curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb && sudo dpkg -i cloudflared.deb
    read -p "\e[92m\e[92mGoto Zero Trust Cloudflare > Access > Tunnel >  Select Shopware Tunnel > Configure > Select Public Hostname > \e[0m\e[91mAdd Public Hostname (\e[0m \e[92msubdomain section emptp > Select domain > Type HTTPS > In url add localhost:443 \e[0m\e[91m save te hostname: \e[0m" accecc_token
    sudo cloudflared service install $accecc_token
}
# Function to generate self-signed SSL certificate
generate_self_signed_ssl() {
    echo -e "\e[92mGenerating a self-signed SSL certificate...\e[0m"
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/selfsigned.key -out /etc/ssl/certs/selfsigned.crt
}
# Function to install RainLoop Webmail
install_rainloop() {
    echo -e "\e[92mOnly use subddomain for RainLoop installation (like webmail.domain.com)...\e[0m"
    get_domain_name  # Ask the user for the domain name
    confirm #Ask for cloudflare non proxied domain that point to IP
    echo -e "\e[92mCreating a directory for RainLoop installation...\e[0m"
    sudo mkdir /var/www/$domain_name
    sudo chown -R www-data:www-data /var/www/$domain_name
    echo -e "\e[92mCreating Apache virtual host configuration...\e[0m"
    vhost_file="/etc/apache2/sites-available/$domain_name.conf"
    echo "<VirtualHost *:80>
    ServerName $domain_name
    DocumentRoot /var/www/$domain_name
    ErrorLog \${APACHE_LOG_DIR}/$domain_name_error.log
    CustomLog \${APACHE_LOG_DIR}/$domain_name_access.log combined 
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/selfsigned.crt
    SSLCertificateKeyFile /etc/ssl/private/selfsigned.key
    <Directory /var/www/$domain_name>
        Options -Indexes +FollowSymLinks +MultiViews
        AllowOverride All
        Require all granted
    </Directory>
    # Block access to the 'data' directory
    <Directory /var/www/$domain_name/data>
        Order deny,allow
        Deny from all
    </Directory>
    # For PHP 8.1
    <FilesMatch \.php$>
        SetHandler \"proxy:unix:/run/php/php8.1-fpm.sock|fcgi://localhost/\"
    </FilesMatch>
    </VirtualHost>" | sudo tee $vhost_file

    echo -e "\e[92mEnabling the new virtual host...\e[0m"
    sudo a2ensite $domain_name.conf
    echo -e "\e[92mRestarting Apache...\e[0m"
    sudo systemctl restart apache2
    echo -e "\e[92mUpdating /etc/hosts file for domain name resolution...\e[0m"
    echo "$(ipinfo)" "$domain_name" | sudo tee -a /etc/hosts
    echo -e "\e[92mInstalling RainLoop...\e[0m"
    cd /var/www/$domain_name
    curl -sL https://repository.rainloop.net/installer.php | sudo php
    echo "\e[92mGoto Zero Trust Cloudflare > Access > Tunnel >  Select Shopware Tunnel > Configure > Select Public Hostname > \e[0m\e[91mAdd Public Hostname (\e[0m \e[92mAdd webmail as a subdomain > Select domain > Type HTTPS> In url add localhost:443 \e[0m\e[91m save te hostname: \e[0m"    
    while true; do
        read -p "Type Y to Confirm: " zero_input
    if [ "$response" == "Y" ]; then
        break
    else
        echo "Please type 'Y' to confirm the above steps is done."
    fi
    done
    echo -e "\e[92mRainLoop installation complete.\e[0m"
    sleep 5
}
# Function to install Shopware
install_shopware() {
    get_domain_name  # Ask the user for the domain name
    read -p "Type 'yes' to make sure your $domain_name don't have any A record in Cloudflare: " response
    if [ "$response" != "yes" ]; then
        echo "Aborted. Make sure your $domain_name don't have any A record in Cloudflare."
        exit 1
    fi
    echo -e "\e[92mInstalling Shopware 6...\e[0m"
    sleep 2
    clear    
    echo -e "\e[92mEditing php.ini settings...\e[0m"
    sleep 2
    sudo sed -i 's/memory_limit = .*/memory_limit = 512M/' /etc/php/8.1/fpm/php.ini
    sudo sed -i 's/upload_max_filesize = .*/upload_max_filesize = 20M/' /etc/php/8.1/fpm/php.ini
    sudo sed -i 's/max_execution_time = .*/max_execution_time = 300/' /etc/php/8.1/fpm/php.ini
    echo -e "\e[92mCreating a directory for Shopware installation...\e[0m"
    sudo mkdir -p /var/www/$domain_name
    echo -e "\e[92mDownloading Shopware 6 Installer...\e[0m"
    sudo wget https://github.com/shopware/web-recovery/releases/latest/download/shopware-installer.phar.php -P /var/www/$domain_name
    echo -e "\e[92mChanging ownership of /var/www/$domain_name...\e[0m"
    sudo chown -R www-data:www-data /var/www/$domain_name
    echo -e "\e[92mSetting permissions for /var/www/$domain_name...\e[0m"
    sudo chmod -R 755 /var/www/$domain_name
    echo -e "\e[92mCreating a new vhost for Shopware in Apache...\e[0m"
    vhost_file="/etc/apache2/sites-available/$domain_name.conf"
    echo "<VirtualHost *:80>
    ServerAdmin webmaster@$domain_name
    DocumentRoot /var/www/$domain_name
    ErrorLog \${APACHE_LOG_DIR}/$domain_name_error.log
    CustomLog \${APACHE_LOG_DIR}/$domain_name_access.log combined
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/selfsigned.crt
    SSLCertificateKeyFile /etc/ssl/private/selfsigned.key
    <Directory /var/www/$domain_name>
        Options -Indexes +FollowSymLinks +MultiViews
        AllowOverride All
        Order allow,deny
        allow from all
    </Directory>
    # For PHP 8.1
    <FilesMatch \.php$>
        SetHandler \"proxy:unix:/run/php/php8.1-fpm.sock|fcgi://localhost/\"
    </FilesMatch>
    RewriteEngine on
    RewriteCond %{SERVER_NAME} =$domain_name
    RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
    </VirtualHost>" | sudo tee $vhost_file
    
    echo -e "\e[92mEnabling the new virtual host...\e[0m"
    sudo a2ensite $domain_name.conf
    echo -e "\e[92mEnabling Rewrite Module and PHP-FPM of Apache2...\e[0m"
    sudo a2enmod rewrite
    sudo a2enmod proxy_fcgi setenvif
    sudo sed -i 's/;opcache.memory_consumption=128/opcache.memory_consumption=256/' /etc/php/8.1/cli/php.ini
    sudo sed -i 's/memory_limit =.*/memory_limit = 512M/' /etc/php/8.1/cli/php.ini
    sudo systemctl restart php8.1-fpm
    echo -e "\e[92mRestarting Apache...\e[0m"
    sudo systemctl restart apache2
    echo -e "\e[92mUpdating the /etc/hosts file for Domain name resolution...\e[0m"
    echo "$(ipinfo)" "$domain_name" | sudo tee -a /etc/hosts
    echo -e "\e[92mConfiguring SSL certificate using Let's Encrypt...\e[0m"
    sleep 2
    #Genrate self-assign SSL
    generate_self_signed_ssl
    echo -e "\e[92mGenerating a random password for the database...\e[0m"
    db_password=$(openssl rand -base64 12)
    echo -e "\e[92mCreating database and user...\e[0m"
    sudo mysql -uroot -e "CREATE DATABASE shopware;"
    sudo mysql -uroot -e "CREATE USER shopware@'localhost' IDENTIFIED BY '$db_password';"
    sudo mysql -uroot -e "GRANT ALL PRIVILEGES ON shopware.* TO shopware@'localhost';"
    sudo mysql -uroot -e "FLUSH PRIVILEGES;"
    echo -e "\e[92mRestarting Apache one more time...\e[0m"
    sudo systemctl restart apache2
    #Setup Zero Trust 
    log "Starting cloudflare setup."        
    echo -e "\e[92mSetup Zero Trust...\e[0m"
    sleep 2
    zero_trust
    log "Cloudflare setup Completed"
    clear
    echo -e "\e[92mYou can access the Shopware installer at https://$domain_name/shopware-installer.phar.php/install\e[0m"
    while true; do
    read -p "\e[92mType 'yes' to confirm successful installation of Shopware 6 on $domain_name with Shopware installer: \e[0m" response
    if [ "$response" == "yes" ]; then
        break
    else
        echo "Please type 'yes' to confirm the successful installation."
    fi
    done
    clear
    echo -e "\e[91mAfter the first installer, press 'yes' to remove the 'public' after $domain_name that is not changeable after installation\e[0m"
# Set the path to your web root directory
web_root="/var/www/$domain_name"
# Create or modify the .htaccess file
htaccess_file="$web_root/.htaccess"
# Add or update the .htaccess rules
cat > "$htaccess_file" <<EOL
RewriteEngine On
RewriteRule ^public/(.*)$ /$1 [L,NC]
EOL
echo "Rewrite rules have been added to $htaccess_file"  
while true; do
    read -p "Enter 'yes' to make the change: " user_input
    if [ "$user_input" = "yes" ]; then
        sudo sed -i "s/DocumentRoot \/var\/www\/$domain_name/DocumentRoot \/var\/www\/$domain_name\/public/g" /etc/apache2/sites-available/$domain_name-le-ssl.conf
        sudo sed -i "s/DocumentRoot \/var\/www\/$domain_name/DocumentRoot \/var\/www\/$domain_name\/public/g" /etc/apache2/sites-available/$domain_name.conf
        #Restart Apache2
        sudo systemctl restart apache2
        clear
        #print DB Details
        echo -e "\e[92mDatabase Name: shopware\e[0m"
        echo -e "\e[92mDatabase User: shopware\e[0m"
        echo -e "\e[92mDatabase Password: $db_password\e[0m"
        # Create the credentials.txt file
        echo -e "# Print DB Details\nDatabase Name: shopware\nDatabase User: shopware\nDatabase Password: $db_password" > credentials.txt
        echo -e "\e[92mChanges have been made. You can access the 2nd Shopware installer at https://$domain_name/installer/database-configuration\e[0m"
        while true; do
                read -p "After installing Shopware from the 2nd installer, press 'y': " user_input
                if [ "$user_input" == "y" ]; then
                    break
                fi
        done
        break
    fi
done
}

# Main script
PS3="Select an option: "
options=("Install Shopware" "Install Shopware with RainLoop Webmail" "Quit")
select option in "${options[@]}"; do
    case $REPLY in
    1)
        log "Starting Shopware installation."
        install_dependencies  # Install dependencies
        log "Dependencies installed."
        install_shopware
        log "Shopware installation completed."
        exit
        ;;
    2)
        log "Dependencies logs Start."
        install_dependencies  # Install dependencies
        log "Dependencies installed."
        log "Starting Shopware installation."
        install_shopware      # Install shopware6
        log "Shopware installation completed."
        log "Starting RainLoop Webmail installation."
        install_rainloop      # Install webmail_rainloop
        log "RainLoop Webmail installation completed."
        exit
        ;;
    3)
        log "Script terminated."
        exit
        ;;
    *)
        log "Invalid option. Please select a valid option."
        ;;
    esac
done
