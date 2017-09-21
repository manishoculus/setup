#!/bin/sh
#var siteName;
if [ -z "$1" ]; then siteName="testsite.com"; else siteName=$1; fi 
if [ -z "$2" ]; then dbName="wordpress"; else dbName=$2; fi 
if [ -z "$3" ]; then dbUser="admin"; else dbUser=$3; fi 
if [ -z "$4" ]; then dbPass="#P@$$w0rd#db"; else dbPass=$4; fi 
if [ -z "$5" ]; then ftpUser="ftpUser"; else ftpUser=$5; fi 
if [ -z "$6" ]; then ftpPass="ftpPass"; else ftpPass=$6; fi 

# set the debian sources
echo "deb http://packages.dotdeb.org wheezy-php55 all" >> /etc/apt/sources.list
echo "deb-src http://packages.dotdeb.org wheezy-php55 all" >> /etc/apt/sources.list
curl http://repo.varnish-cache.org/debian/GPG-key.txt | apt-key add -
echo "deb http://repo.varnish-cache.org/debian/ wheezy varnish-4.0" >> /etc/apt/sources.list
wget http://www.dotdeb.org/dotdeb.gpg
cat dotdeb.gpg | sudo apt-key add -

# install debian packages
apt-get -y update
apt-get -y upgrade

#apt-get -y install php5 php5-fpm php-pear php5-common php5-mcrypt php5-mysql php5-cli php5-gd php-apc
apt-get -y install php5 php5-fpm php-pear php5-common php5-mcrypt php5-mysql php5-cli php5-gd curl libcurl3 libcurl3-dev php5-curl
apt-get -y install nginx
#apt-get -y install redis-server
export DEBIAN_FRONTEND=noninteractive
apt-get -q -y install mysql-server mysql-client
apt-get -y install varnish
apt-get -y install vsftpd


# ==============================================================
# Nginx configuration
# Get the configured nginx.conf and replace the nginx.conf
# ==============================================================
wget https://raw.githubusercontent.com/manishoculus/setup/master/linode/nginx/vps-nginx.conf
wget https://raw.githubusercontent.com/manishoculus/setup/master/linode/nginx/app.conf
wget https://raw.githubusercontent.com/manishoculus/setup/master/linode/nginx/default-sites-available.conf
sed -i "s/DOMAIN/$siteName/g" vps-nginx.conf 
sed -i "s/DOMAIN/$siteName/g" app.conf 
sed -i "s/DOMAIN/$siteName/g" default-sites-available.conf 
# back up the original file
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.orig
mv vps-nginx.conf /etc/nginx/nginx.conf
mv app.conf /etc/nginx/sites-available/$siteName.conf 
ln -s /etc/nginx/sites-available/$siteName.conf /etc/nginx/sites-enabled/$siteName.conf
mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.orig
mv default-sites-available.conf /etc/nginx/sites-available/default


# ==============================================================
# php5-fpm configuration
# ==============================================================
wget https://raw.githubusercontent.com/manishoculus/setup/master/linode/php5-fpm/fpm-app.conf
wget https://raw.githubusercontent.com/manishoculus/setup/master/linode/php5-fpm/apc.ini
sed -i "s/DOMAIN/$siteName/g" fpm-app.conf 
mv fpm-app.conf /etc/php5/fpm/pool.d/$siteName.conf
mv /etc/php5/fpm/pool.d/www.conf /etc/php5/fpm/pool.d/www.conf.tmp
mv apc.ini /etc/php5/fpm/conf.d


# ==============================================================
# Varnish configuration
# Get the configured wordpress.vcl and replace the default.vcl
# ==============================================================
wget https://raw.githubusercontent.com/manishoculus/setup/master/linode/varnish/4.0/default.vcl
wget https://raw.githubusercontent.com/manishoculus/setup/master/linode/varnish/varnish.txt
mv /etc/varnish/default.vcl /etc/varnish/default.vcl.orig
mv wordpress.vcl /etc/varnish/default.vcl

mv /etc/default/varnish /etc/default/varnish.orig
mv varnish.txt /etc/default/varnish


# ==============================================================
# Wordpress Installation
# ==============================================================
# get latest wordpress version
#mkdir -p /var/www/$siteName
#cd /var/www/$siteName
mkdir -p /var/www/$siteName/logs
wget http://wordpress.org/latest.tar.gz
tar -zxvf latest.tar.gz
mv wordpress/* /var/www/$siteName
wget https://raw.githubusercontent.com/manishoculus/setup/master/linode/wordpress/wp-config.php
curl -sS https://api.wordpress.org/secret-key/1.1/salt/ >> wp-config.php
echo "require_once(ABSPATH . 'wp-settings.php');" >> wp-config.php
mv wp-config.php /var/www/$siteName
rm latest.tar.gz
rm -rf wordpress

wget https://raw.githubusercontent.com/manishoculus/setup/master/linode/wordpress/vsftpd.conf
mv vsftpd.conf /etc/
useradd ftpUser --home /var/www/$siteName
echo -e "pass\n$ftpPass" | passwd ftpUser
echo "$ftpUser" >> /etc/vsftpd.chroot_list
chown -R ftpUser /var/www/$siteName
# set up mysql db for wordpress
dbscript="CREATE DATABASE IF NOT EXISTS wordpress;GRANT ALL PRIVILEGES ON $dbName.* TO $dbUser@localhost IDENTIFIED BY '$dbPass' WITH GRANT OPTION;FLUSH PRIVILEGES;"
echo $dbscript | mysql -u root


# ==============================================================
#set up logging (nginx and varnish)
# ==============================================================
#set up logrotate
wget https://raw.githubusercontent.com/manishoculus/setup/master/linode/nginx/nginx-logrotate.conf
wget https://raw.githubusercontent.com/manishoculus/setup/master/linode/varnish/varnish-logrotate.conf
sed -i "s/DOMAIN/$siteName/g" nginx-logrotate.conf 
sed -i "s/DOMAIN/$siteName/g" varnish-logrotate.conf 
mv nginx-logrotate.conf /etc/logrotate.d/nginx
mv varnish-logrotate.conf /etc/logrotate.d/varnish

echo "/etc/init.d/php5-fpm restart" >> /etc/rc.local
echo "/etc/init.d/nginx restart" >> /etc/rc.local
echo "/etc/init.d/varnish restart" >> /etc/rc.local
echo "varnishncsa -a -w /var/www/$siteName/logs/varnish-access.log -D -P /var/run/varnishncsa.pid" >> /etc/rc.local
/etc/init.d/php5-fpm restart
/etc/init.d/nginx restart
/etc/init.d/varnish restart
/etc/init.d/vsftpd restart


#start varnish logging:
varnishncsa -a -w /var/www/$siteName/logs/varnish-access.log -D -P /var/run/varnishncsa.pid
