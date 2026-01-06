#!/bin/bash

# Цвета и стили
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# Функция ожидания завершения процессов apt
wait_for_apt() {
    while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        echo -ne "${RED}⏳ Ждем завершения системных обновлений...${NC}\r"
        sleep 2
    done
}

clear
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}   🚀 3X-UI MULTI-INSTALLER (v6.0 FINAL)       ${NC}"
echo -e "${CYAN}================================================${NC}"

# 0. Определение IP
SERVER_IP=$(curl -s -4 ifconfig.me)
if [ -z "$SERVER_IP" ]; then SERVER_IP=$(hostname -I | awk '{print $1}'); fi
echo -e "${MAGENTA}>>> IP сервера: $SERVER_IP ${NC}"

# 1. Оптимизация системы
echo -e "${YELLOW}>>> [1/8] Оптимизация (BBR + IPv6 off)...${NC}"
wait_for_apt
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

# 2. Обновление пакетов
echo -e "${YELLOW}>>> [2/8] Обновление системы...${NC}"
wait_for_apt
killall unattended-upgr 2>/dev/null
rm /var/lib/apt/lists/lock 2>/dev/null
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
fi
if ! command -v docker-compose &> /dev/null; then
    apt install docker-compose -y
fi
systemctl enable --now docker
if docker compose version &> /dev/null; then DOCKER_CMD="docker compose"; else DOCKER_CMD="docker-compose"; fi

# 4. Ввод данных
echo -e "${YELLOW}>>> [4/8] Конфигурация${NC}"
read -p "📝 Введите ваш ДОМЕН: " DOMAIN
if [ -z "$DOMAIN" ]; then echo "❌ Нет домена. Выход."; exit 1; fi

echo -e "${BLUE}--- Данные администратора (единые для всех) ---${NC}"
read -p "👤 Логин: " NEW_USERNAME
NEW_USERNAME=${NEW_USERNAME:-admin}
read -p "🔑 Пароль: " NEW_PASSWORD
NEW_PASSWORD=${NEW_PASSWORD:-admin}

# 5. SSL
echo -e "${YELLOW}>>> [5/8] Выпуск сертификатов SSL...${NC}"
wait_for_apt
apt install certbot -y
systemctl stop nginx 2>/dev/null
systemctl stop apache2 2>/dev/null
certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email
CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

if [ ! -f "$CERT_PATH" ]; then
    echo -e "${RED}❌ Ошибка: Сертификат не создан. Проверьте DNS запись домена.${NC}"
    exit 1
fi

# 6. Количество панелей
read -p "🔢 Сколько панелей установить (1-100): " PANEL_COUNT
BASE_DIR="/root/3x-ui-farm"
mkdir -p $BASE_DIR
cd $BASE_DIR

# 7. Генерация Docker Compose
echo -e "${YELLOW}>>> [6/8] Создание контейнеров...${NC}"
cat > docker-compose.yml <<EOF
version: '3'
services:
EOF
for (( i=1; i<=PANEL_COUNT; i++ )); do
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
echo -e "${CYAN}   🛠 РУЧНАЯ НАСТРОЙКА ПОРТОВ ($PANEL_COUNT шт.)   ${NC}"
echo -e "${CYAN}================================================${NC}"

$DOCKER_CMD down &>/dev/null

for (( i=1; i<=PANEL_COUNT; i++ )); do
    # Расчет портов
    TP=$((2052 + i))   # Target Panel Port (2053, 2054...)
    TSP=$((4052 + i))  # Target Sub Port (4053, 4054...)
    API=$((60000 + i)) # API Port
    MET=$((10000 + i)) # Metrics Port

    echo -e "${YELLOW}>>> Запуск панели № $i...${NC}"
    mkdir -p xui$i
    $DOCKER_CMD up -d xui$i &>/dev/null
    sleep 3

    echo -e ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║             НАСТРОЙКА ПАНЕЛИ № $i (ИЗ $PANEL_COUNT)                      ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo -e " 1. Открой браузер: ${MAGENTA}http://$SERVER_IP:2053${NC}"
    echo -e "    Логин: admin / Пароль: admin"
    echo -e ""
    echo -e "${BOLD} 2. Перейди в 'Настройки панели' (Panel Settings):${NC}"
    echo -e "    📝 Замени текущие значения на эти:"
    echo -e "    ┌──────────────────────────────────────────────────────────┐"
    echo -e "    │ Порт панели:      ${RED}$TP${NC}                                   │"
    echo -e "    │ Порт подписки:    ${RED}$TSP${NC}                                   │"
    echo -e "    │ Логин:            ${GREEN}$NEW_USERNAME${NC}                                  │"
    echo -e "    │ Пароль:           ${GREEN}$NEW_PASSWORD${NC}                                  │"
    echo -e "    │ Путь Cert:        ${YELLOW}$CERT_PATH${NC} │"
    echo -e "    │ Путь Key:         ${YELLOW}$KEY_PATH${NC}  │"
    echo -e "    └──────────────────────────────────────────────────────────┘"
    echo -e "    💾 Жми 'Save', но ${RED}НЕ ПЕРЕЗАГРУЖАЙ${NC}!"
    echo -e ""
    echo -e "${BOLD} 3. Перейди в 'Настройки Xray' (Xray Configuration):${NC}"
    echo -e "    📝 Замени цифры в коде (JSON):"
    echo -e "    [A] Блок ${BLUE}\"inbounds\"${NC} -> ${BLUE}\"tag\": \"api\"${NC}:"
    echo -e "        \"port\": 62789  --->  ${RED}$API${NC}"
    echo -e ""
    echo -e "    [B] Блок ${BLUE}\"metrics\"${NC} (внизу):"
    echo -e "        \"listen\": \"...11111\"  --->  \"listen\": \"127.0.0.1:${RED}$MET${NC}\""
    echo -e ""
    echo -e "    💾 Жми 'Save'."
    echo -e ""
    echo -e "${BOLD} 4. Финал:${NC}"
    echo -e "    🔥 Жми кнопку ${RED}Restart Panel${NC}."
    echo -e "    (Сайт отключится — это нормально)."
    echo -e ""
    
    while true; do
        read -p "✅ Сделал? (y/n): " yn
        case $yn in
            [Yy]* ) break;;
            * ) echo "Жми y, когда закончишь.";;
        esac
    done

    echo -e "${YELLOW}>>> Выключаю панель $i...${NC}"
    $DOCKER_CMD stop xui$i &>/dev/null
done

# 9. Финальный запуск и отчет
echo -e "${YELLOW}>>> [8/8] Запуск всей фермы...${NC}"
$DOCKER_CMD up -d &>/dev/null

# Генерация отчета в файл
REPORT_FILE="/root/panels_info.txt"
echo "=== ОТЧЕТ ПО УСТАНОВЛЕННЫМ ПАНЕЛЯМ 3X-UI ===" > $REPORT_FILE
echo "Домен: $DOMAIN" >> $REPORT_FILE
echo "Общий логин: $NEW_USERNAME" >> $REPORT_FILE
echo "Общий пароль: $NEW_PASSWORD" >> $REPORT_FILE
echo "----------------------------------------------" >> $REPORT_FILE

echo -e ""
echo -e "${GREEN}🎉 УСТАНОВКА ЗАВЕРШЕНА! ВСЕ ПАНЕЛИ РАБОТАЮТ.${NC}"
echo -e "📄 Данные сохранены в файл: ${BOLD}/root/panels_info.txt${NC}"
echo -e ""
echo -e "${CYAN}📊 СВОДНАЯ ТАБЛИЦА:${NC}"
printf "%-10s | %-35s | %-15s\n" "Panel #" "URL (HTTPS)" "Sub Port"
echo "------------------------------------------------------------------"

for (( i=1; i<=PANEL_COUNT; i++ )); do
    TP=$((2052 + i))
    TSP=$((4052 + i))
    
    # Вывод на экран
    printf "%-10s | %-35s | %-15s\n" "$i" "https://$DOMAIN:$TP" "$TSP"
    
    # Запись в файл
    echo "Панель #$i" >> $REPORT_FILE
    echo "  URL: https://$DOMAIN:$TP" >> $REPORT_FILE
    echo "  Sub Port: $TSP" >> $REPORT_FILE
    echo "----------------------------------------------" >> $REPORT_FILE
done
echo -e ""
