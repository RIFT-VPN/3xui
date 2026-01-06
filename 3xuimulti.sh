#!/bin/bash

# Цвета
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# Функция ожидания
wait_for_apt() {
    while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        echo -ne "${RED}⏳ Ждем завершения процессов apt...${NC}\r"
        sleep 2
    done
}

clear
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}   🚀 3X-UI MULTI-INSTALLER (v8.0 FINAL)       ${NC}"
echo -e "${CYAN}   + Unique Paths & Custom Ports                ${NC}"
echo -e "${CYAN}================================================${NC}"

# 0. IP
SERVER_IP=$(curl -s -4 ifconfig.me)
if [ -z "$SERVER_IP" ]; then SERVER_IP=$(hostname -I | awk '{print $1}'); fi
echo -e "${MAGENTA}>>> IP: $SERVER_IP ${NC}"

# 1. Оптимизация
echo -e "${YELLOW}>>> [1/8] Оптимизация системы...${NC}"
wait_for_apt
sed -i '/net.ipv6.conf.all.disable_ipv6/d' /etc/sysctl.conf
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
echo -e "${YELLOW}>>> [2/8] Обновление...${NC}"
wait_for_apt
killall unattended-upgr 2>/dev/null
rm /var/lib/apt/lists/lock 2>/dev/null
apt update -y
wait_for_apt

# 3. Docker
echo -e "${YELLOW}>>> [3/8] Docker...${NC}"
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

# 4. Данные
echo -e "${YELLOW}>>> [4/8] Конфигурация${NC}"
read -p "📝 ДОМЕН: " DOMAIN
[ -z "$DOMAIN" ] && exit 1

echo -e "${BLUE}--- Данные админа ---${NC}"
read -p "👤 Логин: " NEW_USERNAME
NEW_USERNAME=${NEW_USERNAME:-admin}
read -p "🔑 Пароль: " NEW_PASSWORD
NEW_PASSWORD=${NEW_PASSWORD:-admin}

# 5. SSL
echo -e "${YELLOW}>>> [5/8] SSL...${NC}"
wait_for_apt
apt install certbot -y
systemctl stop nginx 2>/dev/null
certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email
CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
[ ! -f "$CERT_PATH" ] && echo -e "${RED}Ошибка SSL${NC}" && exit 1

# 6. Кол-во панелей
read -p "🔢 Сколько панелей (1-100): " PANEL_COUNT
BASE_DIR="/root/3x-ui-farm"
mkdir -p $BASE_DIR
cd $BASE_DIR

# 7. Конфиг
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

# 8. Интерактив
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}   🛠 РУЧНАЯ НАСТРОЙКА ($PANEL_COUNT шт.)         ${NC}"
echo -e "${CYAN}================================================${NC}"

$DOCKER_CMD down &>/dev/null

for (( i=1; i<=PANEL_COUNT; i++ )); do
    # Генерация значений
    TP=$((5000 + i))   # Панели начинаются с 5001
    TSP=$((4000 + i))  # Подписки начинаются с 4001
    API=$((60000 + i))
    MET=$((10000 + i))
    
    # Генерация случайного пути (например /panel_a1b2/)
    RAND_SUFFIX=$(head /dev/urandom | tr -dc a-z0-9 | head -c 4)
    ROOT_PATH="/panel_${i}_${RAND_SUFFIX}/"

    echo -e "${YELLOW}>>> Запуск панели № $i...${NC}"
    mkdir -p xui$i
    $DOCKER_CMD up -d xui$i &>/dev/null
    sleep 3

    echo -e ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║             НАСТРОЙКА ПАНЕЛИ № $i (ИЗ $PANEL_COUNT)                      ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo -e " 1. Открой: ${MAGENTA}http://$SERVER_IP:2053${NC}"
    echo -e "    Логин: admin / Пароль: admin"
    echo -e ""
    echo -e "${BOLD} 2. 'Panel Settings' (Настройки панели):${NC}"
    echo -e "    📝 ВПИШИ ЭТИ ДАННЫЕ:"
    echo -e "    ┌──────────────────────────────────────────────────────────┐"
    echo -e "    │ Порт панели:      2053 ---> ${RED}$TP${NC}                         │"
    echo -e "    │ Порт подписки:    пусто ---> ${RED}$TSP${NC}                         │"
    echo -e "    │ URL root path:    /    ---> ${RED}$ROOT_PATH${NC}            │"
    echo -e "    │                                                          │"
    echo -e "    │ Логин:            ---> ${GREEN}$NEW_USERNAME${NC}                     │"
    echo -e "    │ Пароль:           ---> ${GREEN}$NEW_PASSWORD${NC}                     │"
    echo -e "    │                                                          │"
    echo -e "    │ Путь Cert:        ${YELLOW}$CERT_PATH${NC} │"
    echo -e "    │ Путь Key:         ${YELLOW}$KEY_PATH${NC}  │"
    echo -e "    └──────────────────────────────────────────────────────────┘"
    echo -e "    💾 Жми 'Save', но ${RED}НЕ ПЕРЕЗАГРУЖАЙ${NC}!"
    echo -e ""
    echo -e "${BOLD} 3. 'Xray Configuration' (Настройки Xray):${NC}"
    echo -e "    📝 Замени цифры в JSON:"
    echo -e "    [A] Блок ${BLUE}\"inbounds\"${NC} -> ${BLUE}\"tag\": \"api\"${NC}:"
    echo -e "        \"port\": ...  --->  ${RED}$API${NC}"
    echo -e ""
    echo -e "    [B] Блок ${BLUE}\"metrics\"${NC} (внизу):"
    echo -e "        \"listen\": ...  --->  \"listen\": \"127.0.0.1:${RED}$MET${NC}\""
    echo -e ""
    echo -e "    💾 Жми 'Save'."
    echo -e ""
    echo -e "${BOLD} 4. Финал:${NC}"
    echo -e "    🔥 Жми ${RED}Restart Panel${NC}."
    echo -e ""
    
    while true; do
        read -p "✅ Сделал? (y/n): " yn
        case $yn in [Yy]*) break;; *) echo "Жми y";; esac
    done

    # Сохраняем путь во временный файл для отчета, т.к. переменная в цикле
    echo "$ROOT_PATH" > "xui$i/root_path.txt"

    echo -e "${YELLOW}>>> Стоп панель $i...${NC}"
    $DOCKER_CMD stop xui$i &>/dev/null
done

# 9. Отчет
echo -e "${YELLOW}>>> [8/8] Финальный запуск...${NC}"
$DOCKER_CMD up -d &>/dev/null

REPORT_FILE="/root/panels_info.txt"
echo "=== ОТЧЕТ 3X-UI ===" > $REPORT_FILE
echo "Домен: $DOMAIN" >> $REPORT_FILE
echo "Логин/Пароль: $NEW_USERNAME / $NEW_PASSWORD" >> $REPORT_FILE
echo "--------------------------------------------------------" >> $REPORT_FILE

echo -e ""
echo -e "${GREEN}🎉 УСТАНОВКА ЗАВЕРШЕНА!${NC}"
echo -e "📄 Файл отчета: ${BOLD}/root/panels_info.txt${NC}"
echo -e ""
echo -e "${CYAN}📊 ТВОИ ПАНЕЛИ:${NC}"
printf "%-5s | %-45s | %-10s\n" "#" "URL (HTTPS)" "Sub Port"
echo "-------------------------------------------------------------------------"
for (( i=1; i<=PANEL_COUNT; i++ )); do
    TP=$((5000 + i))
    TSP=$((4000 + i))
    # Читаем сохраненный путь
    RP=$(cat xui$i/root_path.txt 2>/dev/null)
    [ -z "$RP" ] && RP="/"
    
    FULL_URL="https://$DOMAIN:$TP${RP}"
    
    printf "%-5s | %-45s | %-10s\n" "$i" "$FULL_URL" "$TSP"
    echo "Панель #$i | URL: $FULL_URL | Sub: $TSP" >> $REPORT_FILE
done
echo -e ""
