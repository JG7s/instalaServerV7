#!/bin/bash

###############################################################
# Desenvolvido por Bruno Borba | suporte@connectbix.com.br ####
###############################################################

echo # Instala banco de dados PostgreeSQL 16 com Timescaledb no Debian 12 para Zabbix 7.0 LTS com Nginx

echo ####################################################
echo # "Atualizando arquivo /etc/apt/source.list" #######
echo ####################################################

IP_ZABBIX_BANCO="172.17.1.2"


sed -i 's|deb http://deb.debian.org/debian/ bookworm main non-free-firmware|& contrib non-free|' /etc/apt/sources.list
sed -i 's|deb-src http://deb.debian.org/debian/ bookworm main non-free-firmware|& contrib non-free|' /etc/apt/sources.list
sed -i 's|deb http://security.debian.org/debian-security bookworm-security main non-free-firmware|& contrib non-free|' /etc/apt/sources.list
sed -i 's|deb-src http://security.debian.org/debian-security bookworm-security main non-free-firmware|& contrib non-free|' /etc/apt/sources.list
sed -i 's|deb http://deb.debian.org/debian/ bookworm-updates main non-free-firmware|& contrib non-free|' /etc/apt/sources.list
sed -i 's|deb-src http://deb.debian.org/debian/ bookworm-updates main non-free-firmware|& contrib non-free|' /etc/apt/sources.list

echo "Atualizando Linux"
apt update -y
apt upgrade -y
apt update -y


echo "Tunning no Kernel"
apt install firmware-linux firmware-linux-free firmware-linux-nonfree -y

echo "Instalando o chrony"
apt install -y chrony
systemctl enable --now chrony
systemctl start chronyd

#timedatectl set-timezone America/Manaus

echo "### Instala dependencias ###"
apt-get install vim wget curl tcpdump perl sshpass telnet gnupg gnupg2 apt-transport-https sudo nmap snmpd snmp snmptrapd libsnmp-perl perl libxml-simple-perl snmp-mibs-downloader python3-pip libsnmp-dev build-essential bash-completion htop traceroute software-properties-common expect fping pv lsb-release ncdu -y

echo " ### Gerando locais para en_US.UTF-8 e pt_BR.UTF-8 ### "
sudo apt install -y locales
sudo sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
sudo locale-gen

echo # Adiciona o repositório do PostgreSQL 16
sudo sh -c 'echo "deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
apt update -y

sudo apt install -y postgresql-client-16

echo Reinicia o PostgreeSQL
#systemctl enable --now postgresql


echo ############## Adicionado as permissões do Zabbix Server no sudo visudo  ##############
echo 'zabbix ALL=(ALL:ALL) NOPASSWD:/usr/bin/nmap' | sudo tee -a /etc/sudoers
echo 'zabbix ALL=(ALL:ALL) NOPASSWD:/usr/lib/zabbix/externalscripts' | sudo tee -a /etc/sudoers


echo  Instala o Nginx

sudo apt install nginx -y
sed -i 's/# server_tokens/server_tokens/' /etc/nginx/nginx.conf
systemctl enable --now nginx
systemctl restart nginx


echo # Instala o PHP e módulos
sudo apt -y install --no-install-recommends php php-{fpm,cli,mysql,pear,gd,gmp,bcmath,mbstring,curl,xml,zip,json,pgsql}

echo # Detectando a versão do PHP instalada #
PHP_VERSION=$(php -r "echo PHP_MAJOR_VERSION . '.' . PHP_MINOR_VERSION;")
systemctl enable --now php$PHP_VERSION-fpm


## Aumentar o limite de tempo de execução e o tamanho máximo de upload no PHP ##
# Edita as configurações no php.ini usando sed
sed -i 's/^max_execution_time = .*/max_execution_time = 600/' /etc/php/8.2/fpm/php.ini
sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 100M/' /etc/php/8.2/fpm/php.ini


echo  Reinicia o serviço PHP-FPM para aplicar as alterações
systemctl restart php8.2-fpm


echo Adiciona o repositório do Zabbix 7.0.2 LTS para Debian 12
wget https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_7.0-2+debian12_all.deb
sudo dpkg -i zabbix-release_7.0-2+debian12_all.deb
sudo apt update -y
sudo apt upgrade -y
sudo apt update -y


echo # Instalando Zabbix server, frontend, agent #
apt install zabbix-server-pgsql zabbix-frontend-php php$PHP_VERSION-pgsql zabbix-nginx-conf zabbix-sql-scripts zabbix-agent zabbix-sender -y


echo ############### envio de relatórios ###############
sudo apt install -y zabbix-web-service


echo # Insere o banco de dados inicial do Zabbix automaticamente
zcat /usr/share/zabbix-sql-scripts/postgresql/server.sql.gz | psql -h $IP_ZABBIX_BANCO -d zabbix -U zabbix -w --password



#echo verifique com o comando psql diretamente (sem o zcat) para confirmar se você consegue conectar-se ao servidor
#PGPASSWORD="1234@Mudar" psql -h 192.168.1.11 -d zabbix -U zabbix -c "\dt"



echo # Configura o Zabbix Server
sudo sed -i 's/# DBPassword=/DBPassword=1234@Mudar/' /etc/zabbix/zabbix_server.conf
sed -i "s/^# DBHost=localhost/DBHost=$IP_ZABBIX_BANCO/g" /etc/zabbix/zabbix_server.conf

echo # Configurações adicionais do PHP para o Zabbix Frontend
echo "php_value[date.timezone] = America/Sao_Paulo" >> /etc/zabbix/php-fpm.conf
# Edita o valor de php_value[upload_max_filesize]
sed -i 's/^php_value\[upload_max_filesize\].*/php_value[upload_max_filesize] = 100M/' /etc/zabbix/php-fpm.conf


echo # Configura Nginx para ouvir na porta 8080 (IPv4 e IPv6)
sudo sed -i 's/#\s*listen\s*8080;/listen 8080;/' /etc/zabbix/nginx.conf
sudo sed -i '/listen 8080;/a listen [::]:8080;' /etc/zabbix/nginx.conf


# Configurar o PHP para o Zabbix frontend
#vim /etc/php/8.2/fpm/php.ini

sed -i "s/max_execution_time = 30/max_execution_time = 300/" /etc/php/8.2/fpm/php.ini
sed -i "s/memory_limit = 128M/memory_limit = 256M/" /etc/php/8.2/fpm/php.ini
sed -i "s/post_max_size = 8M/post_max_size = 16M/" /etc/php/8.2/fpm/php.ini
sed -i "s/upload_max_filesize = 2M/upload_max_filesize = 16M/" /etc/php/8.2/fpm/php.ini
sed -i "s/;date.timezone =/date.timezone = UTC/" /etc/php/8.2/fpm/php.ini


#Inicia Zabbix Server agente e processos
echo "############## Inicia Zabbix Server agente e processos ##############"

systemctl enable --now zabbix-server zabbix-agent nginx php${PHP_VERSION}-fpm
systemctl restart zabbix-server zabbix-agent nginx php${PHP_VERSION}-fpm


wget remontti.com.br/debian; bash debian; su -

echo " ## Instalação Finalizada ## "
