#!/bin/bash

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Функция ожидания освобождения apt
wait_for_apt() {
    echo -e "${YELLOW}>>> Проверка блокировок apt...${NC}"
    while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        echo -ne "${RED}Ждем завершения системных обновлений... (это может занять пару минут)${NC}\r"
        sleep 3
    done
    echo -e "${GREEN}>>> Блокировки сняты! Продолжаем.${NC}"
}

clear
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}   СКРИПТ УСТАНОВКИ ФЕРМЫ 3X-UI (v4.0 Final)   ${NC}"
echo -e "${CYAN}================================================${NC}"

# 0. Определение IP
SERVER_IP=$(curl -s -4 ifconfig.me)
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
fi
echo -e "${MAGENTA}>>> IP сервера: $SERVER_IP ${NC}"

# 1. Настройка системы
echo -e "${YELLOW}>>> [1/8] Настройка BBR и отключение IPv6...${NC}"
wait_for_apt # Ждем блокировку

# Отключение IPv6 и включение BBR
sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf
sed -i '/net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.conf
sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf

cat >> /etc/sysctl.conf <<EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
sysctl -p &>/dev/null

# 2. Обновление
echo -e "${YELLOW}>>> [2/8] Обновление пакетов...${NC}"
wait_for_apt
# Если процесс обновления завис намертво, убиваем его
killall unattended-upgr 2>/dev/null
rm /var/lib/apt/lists/lock 2>/dev/null
rm /var/cache/apt/archives/lock 2>/dev/null
rm /var/lib/dpkg/lock* 2>/dev/null

apt update -y
wait_for_apt

# 3. Docker
echo -e "${YELLOW}>>> [3/8] Установка Docker...${NC}"
wait_for_apt
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    if ! command -v docker &> /dev/null; then
        apt install docker.io -y
    fi
fi

DOCKER_COMPOSE_CMD=""
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    apt install docker-compose -y
    DOCKER_COMPOSE_CMD="docker-compose"
fi
systemctl enable --now docker

# 4. Данные
echo -e "${YELLOW}>>> [4/8] Ввод данных${NC}"
read -p "Введите ДОМЕН: " DOMAIN
if [ -z "$DOMAIN" ]; then echo "Нет домена. Выход."; exit 1; fi

echo -e "${CYAN}--- Единый вход для всех панелей ---${NC}"
read -p "Логин (Admin): " NEW_USERNAME
NEW_USERNAME=${NEW_USERNAME:-admin}
read -p "Пароль (Admin): " NEW_PASSWORD
NEW_PASSWORD=${NEW_PASSWORD:-admin}

# 5. SSL
echo -e "${YELLOW}>>> [5/8] Получение SSL...${NC}"
wait_for_apt
apt install certbot -y

systemctl stop nginx 2>/dev/null
systemctl stop apache2 2>/dev/null

# ВОТ ЗДЕСЬ ФЛАГИ ДЛЯ ОТКЛЮЧЕНИЯ ВОПРОСОВ
certbot certonly --standalone -d "$DOMAIN" \
--non-interactive \
--agree-tos \
--register-unsafely-without-email

CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

if [ ! -f "$CERT_PATH" ]; then
    echo -e "${RED}Ошибка SSL! Проверьте, что домен $DOMAIN смотрит на $SERVER_IP${NC}"
    exit 1
fi

# 6. Кол-во панелей
read -p "Количество панелей (1-100): " PANEL_COUNT

BASE_DIR="/root/3x-ui-farm"
mkdir -p $BASE_DIR
cd $BASE_DIR

# 7. Конфиг
echo -e "${YELLOW}>>> [6/8] Генерация конфига...${NC}"
cat > docker-compose.yml <<EOF
version: '3'
services:
EOF

for (( i=1; i<=PANEL_COUNT; i++ ))
do
    cat >> docker-compose.yml <<EOF
  xui$i:
    image: ghcr.io/mhsanaei/3x-ui:latest
    container_name: xui$i
    volumes:
      - ./xui$i:/etc/x-ui
      - ./xui$i/cert:/root/cert
      - /etc/letsencrypt:/etc/letsencrypt
    network_mode: host
    restart: always
    tty: true

EOF
done

# 8. Интерактив
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}   НАСТРОЙКА ПАНЕЛЕЙ ПО ОЧЕРЕДИ   ${NC}"
echo -e "${CYAN}================================================${NC}"

$DOCKER_COMPOSE_CMD down &>/dev/null

for (( i=1; i<=PANEL_COUNT; i++ ))
do
    TARGET_PANEL_PORT=$((2052 + i))
    TARGET_SUB_PORT=$((4052 + i))
    API_PORT=$((60000 + i))
    METRICS_PORT=$((10000 + i))

    echo -e "${YELLOW}>>> [ Панель $i / $PANEL_COUNT ]${NC}"
    mkdir -p xui$i
    $DOCKER_COMPOSE_CMD up -d xui$i
    
    echo -e "${GREEN}1. Браузер:${NC} ${MAGENTA}http://$SERVER_IP:2053${NC} (admin/admin)"
    echo -e "${GREEN}2. Настройки панели:${NC}"
    echo -e "   Порт: ${RED}$TARGET_PANEL_PORT${NC} | Логин: ${GREEN}$NEW_USERNAME${NC} | Пароль: ${GREEN}$NEW_PASSWORD${NC}"
    echo -e "   Cert: ${YELLOW}$CERT_PATH${NC}"
    echo -e "   Key:  ${YELLOW}$KEY_PATH${NC}"
    echo -e "   (Сохрани, но НЕ перезагружай)"
    echo -e "${GREEN}3. Настройки Xray:${NC}"
    echo -e "   port -> ${RED}$API_PORT${NC}"
    echo -e "   listen 11111 -> ${RED}127.0.0.1:$METRICS_PORT${NC}"
    echo -e "   (Сохрани)"
    echo -e "${GREEN}4. Порт подписки:${NC} ${RED}$TARGET_SUB_PORT${NC} (если есть)"
    echo -e "${GREEN}5. Жми 'Перезапустить панель'${NC}"
    
    while true; do
        read -p "Готово? (y/n): " yn
        case $yn in
            [Yy]* ) break;;
            * ) echo "Напишите y";;
        esac
    done

    $DOCKER_COMPOSE_CMD stop xui$i
done

# 9. Финал
echo -e "${YELLOW}>>> [8/8] Запуск всех панелей...${NC}"
$DOCKER_COMPOSE_CMD up -d

echo -e "${GREEN}ГОТОВО!${NC}"
echo -e "Данные: $NEW_USERNAME / $NEW_PASSWORD"
for (( i=1; i<=PANEL_COUNT; i++ ))
do
    TARGET_PANEL_PORT=$((2052 + i))
    echo -e "Панель $i: https://$DOMAIN:$TARGET_PANEL_PORT"
done
