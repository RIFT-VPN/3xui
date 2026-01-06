#!/bin/bash

# Цвета для красивого вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

clear
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}   СКРИПТ УСТАНОВКИ ФЕРМЫ 3X-UI (AUTO-SETUP)   ${NC}"
echo -e "${CYAN}   v3.0 | BBR + IPv6 Disable + Docker + SSL     ${NC}"
echo -e "${CYAN}================================================${NC}"

# 0. Определение IP сервера
SERVER_IP=$(curl -s -4 ifconfig.me)
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(curl -s -4 icanhazip.com)
fi
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(hostname -I | awk '{print $1}')
fi

echo -e "${MAGENTA}>>> Ваш IP адрес: $SERVER_IP ${NC}"
echo -e ""

# 1. Настройка системы (BBR + IPv6 Disable)
echo -e "${YELLOW}>>> [1/8] Настройка системы (BBR и откл. IPv6)...${NC}"

# Бэкап конфига
cp /etc/sysctl.conf /etc/sysctl.conf.bak

# Удаляем старые дублирующиеся записи, если есть
sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf
sed -i '/net.ipv6.conf.default.disable_ipv6/d' /etc/sysctl.conf
sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf

# Добавляем новые настройки
cat >> /etc/sysctl.conf <<EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

# Применяем
sysctl -p &>/dev/null
echo -e "${GREEN}IPv6 отключен, BBR активирован!${NC}"

# 2. Обновление системы
echo -e "${YELLOW}>>> [2/8] Обновление списков пакетов...${NC}"
apt update -y

# 3. Установка Docker
echo -e "${YELLOW}>>> [3/8] Проверка Docker...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Docker не найден. Устанавливаю...${NC}"
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Не удалось поставить Docker скриптом. Пробую через apt...${NC}"
        apt install docker.io -y
    fi
else
    echo -e "${GREEN}Docker уже установлен.${NC}"
fi

# Проверка Docker Compose
DOCKER_COMPOSE_CMD=""
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    echo -e "${YELLOW}Устанавливаю Docker Compose...${NC}"
    apt install docker-compose -y
    DOCKER_COMPOSE_CMD="docker-compose"
fi

systemctl enable --now docker

# 4. Ввод данных (Домен, Пароли)
echo -e "${CYAN}------------------------------------------------${NC}"
echo -e "${YELLOW}>>> [4/8] Конфигурация${NC}"

read -p "Введите ваш ДОМЕН (например, site.com): " DOMAIN
if [ -z "$DOMAIN" ]; then
    echo -e "${RED}Домен не введен. Выход.${NC}"
    exit 1
fi

echo -e "${CYAN}--- Единые данные для входа во ВСЕ панели ---${NC}"
read -p "Придумайте ЛОГИН (по умолчанию admin): " NEW_USERNAME
NEW_USERNAME=${NEW_USERNAME:-admin}

read -p "Придумайте ПАРОЛЬ (по умолчанию admin): " NEW_PASSWORD
NEW_PASSWORD=${NEW_PASSWORD:-admin}

# 5. SSL Сертификат
echo -e "${CYAN}------------------------------------------------${NC}"
echo -e "${YELLOW}>>> [5/8] Получение SSL сертификата...${NC}"
apt install certbot -y

# Останавливаем всё, что может занимать 80 порт
systemctl stop nginx 2>/dev/null
systemctl stop apache2 2>/dev/null

certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email

CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

if [ ! -f "$CERT_PATH" ]; then
    echo -e "${RED}ОШИБКА: Сертификат не получен! Проверьте, что домен $DOMAIN направлен на IP $SERVER_IP${NC}"
    exit 1
else
    echo -e "${GREEN}Сертификаты получены успешно!${NC}"
fi

# 6. Количество панелей
echo -e "${CYAN}------------------------------------------------${NC}"
read -p "Сколько панелей установить (1-100): " PANEL_COUNT
if ! [[ "$PANEL_COUNT" =~ ^[0-9]+$ ]] || [ "$PANEL_COUNT" -lt 1 ] || [ "$PANEL_COUNT" -gt 100 ]; then
    echo -e "${RED}Неверное число.${NC}"
    exit 1
fi

BASE_DIR="/root/3x-ui-farm"
mkdir -p $BASE_DIR
cd $BASE_DIR

# 7. Генерация docker-compose.yml
echo -e "${YELLOW}>>> [6/8] Генерация конфига Docker...${NC}"

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

# 8. Интерактивная настройка
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}   НАЧАЛО НАСТРОЙКИ ПАНЕЛЕЙ ПО ОЧЕРЕДИ ($PANEL_COUNT шт.)   ${NC}"
echo -e "${CYAN}================================================${NC}"
echo -e "${RED}ВАЖНО:${NC} Не закрывайте этот скрипт."
echo -e "Мы будем запускать панели по одной, вы будете менять порты в браузере."

# Очистка перед стартом
$DOCKER_COMPOSE_CMD down &>/dev/null

for (( i=1; i<=PANEL_COUNT; i++ ))
do
    # РАСЧЕТ ПОРТОВ
    # Panel: 2053, 2054...
    TARGET_PANEL_PORT=$((2052 + i))
    # Sub: 4053, 4054...
    TARGET_SUB_PORT=$((4052 + i))
    # API: 60001, 60002...
    API_PORT=$((60000 + i))
    # Metrics: 10001, 10002...
    METRICS_PORT=$((10000 + i))

    echo -e "${CYAN}------------------------------------------------${NC}"
    echo -e "${YELLOW}>>> [ Панель $i из $PANEL_COUNT ]${NC}"
    
    mkdir -p xui$i
    
    # Запуск
    $DOCKER_COMPOSE_CMD up -d xui$i
    
    echo -e ""
    echo -e "${GREEN}>>> Панель № $i запущена! Действуйте:${NC}"
    echo -e "1. Откройте браузер: ${MAGENTA}http://$SERVER_IP:2053${NC}"
    echo -e "   (Логин/Пароль: admin / admin)"
    echo -e ""
    echo -e "2. Перейдите в ${CYAN}Настройки панели (Panel Settings)${NC}:"
    echo -e "   Поля для замены:"
    echo -e "   -> Порт панели:      ${RED}$TARGET_PANEL_PORT${NC}"
    echo -e "   -> Логин:            ${GREEN}$NEW_USERNAME${NC}"
    echo -e "   -> Пароль:           ${GREEN}$NEW_PASSWORD${NC}"
    echo -e "   -> URL root path:    (оставь пустым /)"
    echo -e "   -> Путь к Cert:      ${YELLOW}$CERT_PATH${NC}"
    echo -e "   -> Путь к Key:       ${YELLOW}$KEY_PATH${NC}"
    echo -e "   * Нажмите Сохранить (Save), но ${RED}НЕ перезагружайте!${NC}"
    echo -e ""
    echo -e "3. Перейдите в ${CYAN}Настройки Xray (Xray Configuration)${NC}:"
    echo -e "   -> Найдите \"port\": ... и замените на: ${RED}$API_PORT${NC}"
    echo -e "   -> Найдите \"listen\": ... 11111 и замените на: ${RED}127.0.0.1:$METRICS_PORT${NC}"
    echo -e "   * Нажмите Сохранить."
    echo -e ""
    echo -e "4. ${GREEN}Важно:${NC} Если есть поле 'Порт подписки' (Sub Port) в настройках,"
    echo -e "   установите его на: ${RED}$TARGET_SUB_PORT${NC}"
    echo -e ""
    echo -e "5. Нажмите кнопку ${RED}Перезапустить панель (Restart Panel)${NC}."
    echo -e "   (Сайт перестанет открываться — так и должно быть)."
    echo -e ""
    
    while true; do
        read -p "Вы сделали все настройки для панели $i? (y/n): " yn
        case $yn in
            [Yy]* ) break;;
            [Nn]* ) echo "Жду...";;
            * ) echo "Напишите y или n";;
        esac
    done

    echo -e "${YELLOW}>>> Выключаю панель $i...${NC}"
    $DOCKER_COMPOSE_CMD stop xui$i
done

# 9. Финал
echo -e "${CYAN}================================================${NC}"
echo -e "${YELLOW}>>> [8/8] Запускаю все панели (это может занять время)...${NC}"
$DOCKER_COMPOSE_CMD up -d

echo -e "${CYAN}================================================${NC}"
echo -e "${GREEN}   УСТАНОВКА ЗАВЕРШЕНА!   ${NC}"
echo -e "${CYAN}================================================${NC}"
echo -e "Ваши данные:"
echo -e "Логин:  ${GREEN}$NEW_USERNAME${NC}"
echo -e "Пароль: ${GREEN}$NEW_PASSWORD${NC}"
echo -e ""
echo -e "Ссылки для входа (HTTPS):"

for (( i=1; i<=PANEL_COUNT; i++ ))
do
    TARGET_PANEL_PORT=$((2052 + i))
    TARGET_SUB_PORT=$((4052 + i))
    echo -e "[$i] https://$DOMAIN:$TARGET_PANEL_PORT  (Sub Port: $TARGET_SUB_PORT)"
done
echo -e "${CYAN}================================================${NC}"
