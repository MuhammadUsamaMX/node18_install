#!/bin/bash

# Log file location
log_file="/var/log/script.log"

# Function to log messages
log() {
    local message="$1"
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $message" | sudo tee -a "$log_file"
}

# Create the log file and set permissions
sudo touch "$log_file"
sudo chmod 644 "$log_file"
log "Log file created and permissions set."

# Function to check if the OS is Ubuntu and version is 22.04 or above
is_supported_ubuntu_version() {
    if [ -n "$(lsb_release -a 2>/dev/null | grep 'Ubuntu')" ]; then
        ubuntu_version=$(lsb_release -r | awk '{print $2}')
        if [ "$(echo "$ubuntu_version >= 22.04" | bc)" -eq 1 ]; then
            return 0
        fi
    fi
    return 1
}

# Function to check if the script is run with root privileges
is_root() {
    if [ "$EUID" -eq 0 ]; then
        return 0
    fi
    return 1
}

# Function to install dependencies
install_dependencies() {
    log "Installing dependencies..."
    sudo apt update
    sudo apt install -y lsb-release curl mysql-client certbot iptables curl wget sudo nano zip iptables ufw
    log "Dependencies installed."
    sleep 3
    clear
}

# Function to display IP information
ipinfo() {
    curl -s ifconfig.me
}

# Ask the user for the domain name
get_domain_name() {
    read -p "Enter the domain name: " domain_name
}

# Function to prompt user for confirmation
confirm() {
    read -p "Type 'yes' to make sure your $domain_name and IP are not proxied in Cloudflare (Auto SSL): " response
    if [ "$response" != "yes" ]; then
        echo "Aborted. Make sure your domain and IP are not proxied in Cloudflare."
        exit 1
    fi
    sleep 3
    clear
}

# Function to flush iptables rules and allow port 22, 80, 443
iptables_flush() {
    echo -e "\e[92mFlushing iptables rules and allowing ports 22, 80, 443...\e[0m"

    # Flush existing rules
    iptables -F && iptables -A INPUT -p tcp --dport 22 -j ACCEPT && iptables -A INPUT -p tcp --dport 80 -j ACCEPT && iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    
    sleep 3
    clear
}
#Fetch cloudflare IPs
fetch_cloudflare_ips() {
    url="https://www.cloudflare.com/ips-v4/"
    ip_ranges=$(curl -s "$url")
    echo "$ip_ranges"
}

# Function to install RainLoop Webmail
install_rainloop() {
    echo -e "\e[92mOnly use subddomain for RainLoop installation (like webmail.domain.com)...\e[0m"
    
    get_domain_name  # Ask the user for the domain name
    
    confirm #Ask for cloudflare non proxied domain that point to IP
    
    iptables_flush  # Flush iptables rules and allow essential ports
    curl -sL https://repository.rainloop.net/installer.php | sudo php
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

    echo -e "\e[92mInstalling RainLoop...\e[0m"
    cd /var/www/$domain_name
    

    echo -e "\e[92mUpdating /etc/hosts file for domain name resolution...\e[0m"
    echo "$(ipinfo)" "$domain_name" | sudo tee -a /etc/hosts

    echo -e "\e[92mObtaining SSL certificate from Let's Encrypt...\e[0m"
    
    # Clear existing rules & Allow SSH & Block all HTTP and HTTPS Trafic
    iptables -F && iptables -A INPUT -p tcp --dport 22,80,443/tcp -j ACCEPT

    #Getting SSL
    sudo certbot --apache -d $domain_name -m admin@$domain_name --agree-tos

    echo -e "\e[92mRainLoop installation complete.\e[0m"
    sleep 5
}

# Function to install Shopware
install_shopware() {
    get_domain_name  # Ask the user for the domain name

    iptables_flush  # Flush iptables rules and allow essential ports

    confirm #Ask for cloudflare non proxied domain that point to IP
    
    echo -e "\e[92mInstalling Shopware 6...\e[0m"

    echo -e "\e[92mUpdating and upgrading packages...\e[0m"
    sudo apt update && sudo apt upgrade -y

    echo -e "\e[92mInstalling necessary packages...\e[0m"
    sudo apt install -y apache2 mariadb-server certbot python3-certbot-apache php-fpm php-mysql php-curl php-dom php-json php-zip php-gd php-xml php-mbstring php-intl php-opcache

    echo -e "\e[92mInstalling Node.js and npm...\e[0m"
    sudo apt install -y curl
    curl -fsSL https://raw.githubusercontent.com/MuhammadUsamaMX/node18_install/main/script.sh | sudo -E bash -
    sudo apt install -y nodejs npm

    echo -e "\e[92mEditing php.ini settings...\e[0m"
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
    sudo a2dissite /etc/apache2/sites-enabled/000-default.conf
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
    
    # Clear existing rules & Allow SSH & Block all HTTP and HTTPS Trafic
    iptables -F && iptables -A INPUT -p tcp --dport 22,80,443/tcp -j ACCEPT

    #Getting SSL
    sudo certbot --apache -d $domain_name -m admin@$domain_name --agree-tos
    sleep 5
    echo -e "\e[92mGenerating a random password for the database...\e[0m"
    db_password=$(openssl rand -base64 12)
    echo -e "\e[92mCreating database and user...\e[0m"
    sudo mysql -uroot -e "CREATE DATABASE shopware;"
    sudo mysql -uroot -e "CREATE USER shopware@'localhost' IDENTIFIED BY '$db_password';"
    sudo mysql -uroot -e "GRANT ALL PRIVILEGES ON shopware.* TO shopware@'localhost';"
    sudo mysql -uroot -e "FLUSH PRIVILEGES;"
    echo -e "\e[92mRestarting Apache one more time...\e[0m"
    sudo systemctl restart apache2
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
        echo -e "# Print DB Details\nDatabase Name: shopware\nDatabase User: shopware\nDatabase Password: $db_password" > /root/credentials.txt
        
       # Inform the user that the file has been created
        echo "Credentials have been saved in credentials.txt"

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

# Function to set up Cloudflare access
cloudflare_setup() {
clear
echo -e "\e[92mSetting up Cloudflare access for $domain_name...\e[0m"

while true; do
    read -p "Type 'y' to make sure your $domain_name and IP are proxied in Cloudflare to prevent IP leaks: " user_input
    if [ "$user_input" == "y" ]; then
        break
    fi
done

#Enable and disable UFW
ufw enable
ufw disable

# Fetch Cloudflare IP ranges
cloudflare_ips=$(fetch_cloudflare_ips)

# Clear existing Cloudflare rules (optional)
iptables -F

#Allow SSH & Block all HTTP and HTTPS Trafic
iptables -A INPUT -p tcp --dport 22 -j ACCEPT && iptables -A INPUT -p tcp --dport 80 -j DROP && iptables -A INPUT -p tcp --dport 443 -j DROP

# Allow incoming traffic from Cloudflare IP ranges in iptables
while IFS= read -r ip_range; do
    iptables -A INPUT -p tcp --dport 80 -s "$ip_range" -j ACCEPT
    iptables -A INPUT -p tcp --dport 443 -s "$ip_range" -j ACCEPT
done <<< "$cloudflare_ips"

iptables-save
iptables-legacy-save

echo -e "\e[92mCloudflare access setup completed for $domain_name.\e[0m"

}


# Main script
#Root permission check

if ! is_root; then
    echo "This script requires root privileges. Please run it with sudo."
    exit 1
fi
# Check the OS and it's version 
if ! is_supported_ubuntu_version; then
    echo "This script is designed to run on Ubuntu 22.4 or above only."
    exit 1
fi

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
        log "Starting cloudflare setup."
        cloudflare_setup      # Setup cloudflare
        log "Cloudflare setup Completed"
        exit
        ;;
    2)
        log "Dependencies logs Start."
        install_dependencies  # Install dependencies
        log "Dependencies installed."
        log "Starting Shopware installation."
        #install_shopware      # Install shopware6
        log "Shopware installation completed."
        log "Starting RainLoop Webmail installation."
        install_rainloop      # Install webmail_rainloop
        log "RainLoop Webmail installation completed."
        log "Starting cloudflare setup."
        #cloudflare_setup      # setup cloudflare
        log "Cloudflare setup Completed"
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
