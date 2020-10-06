#!/bin/bash
if [ -f .env ]; then
    source .env
fi

wget -nc https://en-gb.wordpress.org/latest-en_GB.zip

az group create --name $RESOURCE_GROUP_NAME --location $LOCATION
az appservice plan create --name $SERVICE_PLAN_NAME --resource-group $RESOURCE_GROUP_NAME  \
    --sku $SERVICE_PLAN_SKU --is-linux
az webapp create --resource-group $RESOURCE_GROUP_NAME  --plan $SERVICE_PLAN_NAME  --name $WEB_APP_NAME \
    --runtime "PHP|7.3"
# set "project" so that Kudu will expand the wordpress subfolder into the root of our site
az webapp config appsettings set --resource-group $RESOURCE_GROUP_NAME --name $WEB_APP_NAME \
    --settings project=wordpress

az webapp config appsettings set --resource-group $RESOURCE_GROUP_NAME --name $WEB_APP_NAME \
    --settings MYSQL_SSL_CA=$MARIADB_CERT_FOLDER/$MARIADB_CERT_FILENAME
az webapp deployment source config-zip --resource-group $RESOURCE_GROUP_NAME --name $WEB_APP_NAME --src latest-en_GB.zip


az mariadb server create  --location $LOCATION --resource-group $RESOURCE_GROUP_NAME --name $MARIADB_SERVER_NAME \
    --admin-user $MARIADB_ADMIN_USER --admin-password $MARIADB_ADMIN_PASSWORD  --sku-name $MARIADB_SKU

az mariadb server firewall-rule create --resource-group $RESOURCE_GROUP_NAME --server-name $MARIADB_SERVER_NAME  \
    --name allowazure --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0

az mariadb db create --name $WORDPRESS_DB_NAME --resource-group $RESOURCE_GROUP_NAME --server-name $MARIADB_SERVER_NAME 

# hitting the website seems to have some effect on ssh!
wget -O/dev/null -q $WEB_APP_NAME.azurewebsites.net
sleep 10s
az webapp create-remote-connection --name $WEB_APP_NAME --resource-group $RESOURCE_GROUP_NAME  -p 54321 &
sleep 10s

expect <(cat <<EOF

spawn ssh -o "UserKnownHostsFile=/dev/null" -o "StrictHostKeyChecking=no" -p 54321 root@localhost \
{wget -nc -P $MARIADB_CERT_FOLDER https://cacerts.digicert.com/$MARIADB_CERT_FILENAME && \
mysql -h  $MARIADB_SERVER_NAME.mariadb.database.azure.com -u $MARIADB_ADMIN_USER@ $MARIADB_SERVER_NAME -p$MARIADB_ADMIN_PASSWORD --ssl \
-e "CREATE DATABASE IF NOT EXISTS $WORDPRESS_DB_NAME character set utf8 collate utf8_unicode_ci;"\
"CREATE USER IF NOT EXISTS '$WORDPRESS_DB_USER'@'%' IDENTIFIED  BY '$WORDPRESS_DB_PASSWORD';"\
"GRANT ALL ON $WORDPRESS_DB_NAME.* to '$WORDPRESS_DB_USER'@'%';" && \
wget -nc https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
chmod +x wp-cli.phar && \
mv wp-cli.phar wp
}
expect "assword:"
send "Docker!\r"
wait 
EOF
)
kill $(pgrep -f "webapp create-remote-connection")

## mysql -h dbserver-ahfdskf.mariadb.database.azure.com -u BOSS_HOGG@dbserver-ahfdskf  -p --ssl  