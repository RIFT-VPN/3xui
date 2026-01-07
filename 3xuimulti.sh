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
        echo -ne "${RED}⏳ Ждем apt...${NC}\r"
        sleep 2
    done
}

clear
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}   🚀 3X-UI MULTI-INSTALLER (v10.0 SCALING)    ${NC}"
echo -e "${CYAN}   + Auto-Scale + SSL Check + Full Config       ${NC}"
echo -e "${CYAN}================================================${NC}"

# 0. IP
SERVER_IP=$(curl -s -4 ifconfig.me)
if [ -z "$SERVER_IP" ]; then SERVER_IP=$(hostname -I | awk '{print $1}'); fi
echo -e "${MAGENTA}>>> IP: $SERVER_IP ${NC}"

# 1. Оптимизация (Пропускаем, если уже настроено)
if ! grep -q "net.ipv4.tcp_congestion_control = bbr" /etc/sysctl.conf; then
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
else
    echo -e "${GREEN}>>> [1/8] Система уже оптимизирована.${NC}"
fi

# 2. Обновление
echo -e "${YELLOW}>>> [2/8] Проверка обновлений...${NC}"
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

# 5. SSL (Smart Check)
echo -e "${YELLOW}>>> [5/8] Проверка SSL...${NC}"
CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

if [ -f "$CERT_PATH" ] && [ -f "$KEY_PATH" ]; then
    echo -e "${GREEN}✅ Сертификаты уже существуют. Пропускаем генерацию.${NC}"
else
    echo -e "${YELLOW}>>> Сертификатов нет, запускаем Certbot...${NC}"
    wait_for_apt
    apt install certbot -y
    systemctl stop nginx 2>/dev/null
    certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email
    [ ! -f "$CERT_PATH" ] && echo -e "${RED}Ошибка SSL${NC}" && exit 1
fi

# 6. Подсчет панелей (Logic for Scaling)
BASE_DIR="/root/3x-ui-farm"
mkdir -p $BASE_DIR
cd $BASE_DIR

EXISTING_COUNT=0
if [ -f "docker-compose.yml" ]; then
    EXISTING_COUNT=$(grep -c "container_name: xui" docker-compose.yml)
fi

echo -e "${MAGENTA}-------------------------------------------${NC}"
if [ "$EXISTING_COUNT" -gt 0 ]; then
    echo -e "Найдено установленных панелей: ${BOLD}$EXISTING_COUNT${NC}"
    read -p "🔢 Сколько панелей ДОБАВИТЬ? (0 - просто пересоздать конфиг): " ADD_COUNT
else
    echo -e "Панелей не найдено."
    read -p "🔢 Сколько панелей УСТАНОВИТЬ? (1-100): " ADD_COUNT
fi

if ! [[ "$ADD_COUNT" =~ ^[0-9]+$ ]]; then ADD_COUNT=0; fi
TOTAL_COUNT=$((EXISTING_COUNT + ADD_COUNT))

if [ "$TOTAL_COUNT" -eq 0 ]; then
    echo "Нечего делать."
    exit 0
fi

# 7. Генерация конфига (Пересоздаем полный файл)
echo -e "${YELLOW}>>> [6/8] Обновление конфигурации ($TOTAL_COUNT шт.)...${NC}"
cat > docker-compose.yml <<EOF
version: '3'
services:
EOF

for (( i=1; i<=TOTAL_COUNT; i++ )); do
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

# 8. Интерактив (Только для НОВЫХ)
START_INDEX=$((EXISTING_COUNT + 1))

if [ "$ADD_COUNT" -gt 0 ]; then
    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}   🛠 НАСТРОЙКА НОВЫХ ПАНЕЛЕЙ ($ADD_COUNT шт.)    ${NC}"
    echo -e "${CYAN}================================================${NC}"

    # Сначала гасим только новые, если они вдруг есть, но лучше просто убедиться что порты свободны
    # $DOCKER_CMD down &>/dev/null # НЕЛЬЗЯ делать down, это убьет старые панели
    
    for (( i=START_INDEX; i<=TOTAL_COUNT; i++ )); do
        TP=$((5000 + i))
        TSP=$((4000 + i))
        API=$((60000 + i))
        MET=$((10000 + i))
        
        RAND_SUFFIX=$(head /dev/urandom | tr -dc a-z0-9 | head -c 4)
        ROOT_PATH="/panel_${i}_${RAND_SUFFIX}/"

        echo -e "${YELLOW}>>> Запуск НОВОЙ панели № $i...${NC}"
        mkdir -p xui$i
        
        # Запускаем конкретный контейнер
        $DOCKER_CMD up -d xui$i &>/dev/null
        sleep 3

        echo -e ""
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║             НАСТРОЙКА ПАНЕЛИ № $i (ИЗ $TOTAL_COUNT)                      ║${NC}"
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
        echo -e "    Выдели ВЕСЬ старый код (Ctrl+A), удали его и вставь ЭТОТ:"
        echo -e "${GREEN}⬇️⬇️⬇️ СКОПИРУЙ ОТСЮДА ⬇️⬇️⬇️${NC}"
        echo -e "${GREEN}"
        cat <<EOF
{
  "log": {
    "access": "none",
    "dnsLog": false,
    "error": "",
    "loglevel": "warning",
    "maskAddress": ""
  },
  "api": {
    "tag": "api",
    "services": [
      "HandlerService",
      "LoggerService",
      "StatsService"
    ]
  },
  "inbounds": [
    {
      "tag": "api",
      "listen": "127.0.0.1",
      "port": $API,
      "protocol": "tunnel",
      "settings": {
        "address": "127.0.0.1"
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "AsIs",
        "redirect": "",
        "noises": []
      }
    },
    {
      "tag": "blocked",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "policy": {
    "levels": {
      "0": {
        "statsUserDownlink": true,
        "statsUserUplink": true
      }
    },
    "system": {
      "statsInboundDownlink": true,
      "statsInboundUplink": true,
      "statsOutboundDownlink": false,
      "statsOutboundUplink": false
    }
  },
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "inboundTag": [
          "api"
        ],
        "outboundTag": "api"
      },
      {
        "type": "field",
        "outboundTag": "blocked",
        "ip": [
          "geoip:private"
        ]
      },
      {
        "type": "field",
        "outboundTag": "blocked",
        "protocol": [
          "bittorrent"
        ]
      }
    ]
  },
  "stats": {},
  "metrics": {
    "tag": "metrics_out",
    "listen": "127.0.0.1:$MET"
  }
}
EOF
        echo -e "${NC}${GREEN}⬆️⬆️⬆️ ДО СЮДА ⬆️⬆️⬆️${NC}"
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

        echo "$ROOT_PATH" > "xui$i/root_path.txt"
        echo -e "${YELLOW}>>> Стоп панель $i...${NC}"
        $DOCKER_CMD stop xui$i &>/dev/null
    done
else
    echo -e "${GREEN}>>> Новых панелей нет, пропускаем ручную настройку.${NC}"
fi

# 9. Отчет
echo -e "${YELLOW}>>> [8/8] Финальный запуск всей фермы...${NC}"
$DOCKER_CMD up -d &>/dev/null

REPORT_FILE="/root/panels_info.txt"
echo "=== ОТЧЕТ 3X-UI ===" > $REPORT_FILE
echo "Домен: $DOMAIN" >> $REPORT_FILE
echo "Логин/Пароль: $NEW_USERNAME / $NEW_PASSWORD" >> $REPORT_FILE
echo "--------------------------------------------------------" >> $REPORT_FILE

echo -e ""
echo -e "${GREEN}🎉 ВСЕ ГОТОВО!${NC}"
echo -e "📄 Файл: ${BOLD}/root/panels_info.txt${NC}"
echo -e ""
echo -e "${CYAN}📊 ПОЛНЫЙ СПИСОК:${NC}"
printf "%-5s | %-45s | %-10s\n" "#" "URL (HTTPS)" "Sub Port"
echo "-------------------------------------------------------------------------"
for (( i=1; i<=TOTAL_COUNT; i++ )); do
    TP=$((5000 + i))
    TSP=$((4000 + i))
    # Читаем сохраненный путь (даже для старых панелей)
    RP=$(cat xui$i/root_path.txt 2>/dev/null)
    [ -z "$RP" ] && RP="/"
    
    FULL_URL="https://$DOMAIN:$TP${RP}"
    
    printf "%-5s | %-45s | %-10s\n" "$i" "$FULL_URL" "$TSP"
    echo "Панель #$i | URL: $FULL_URL | Sub: $TSP" >> $REPORT_FILE
done
echo -e ""
