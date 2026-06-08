#!/bin/bash
# =========================================================================
#  UniFi Vsratiy PBR-VPN-PROXYFI — MASTER INSTALLER
# =========================================================================

# =========================================================================
#  Project: UniFi Vsratiy PBR-VPN-PROXYFI
#  File:    install.sh
#  Desc:    Module Installer
#  Author:  Rew-weR
#  Date:    2026-06-08
# =========================================================================

# Установка режима безопасного выполнения (остановка при ошибке)
set -e

if [ "$EUID" -ne 0 ]; then echo "Ошибка: Нужен root."; exit 1; fi
if [ ! -d "src" ]; then
    echo "[🚨] Ошибка: Не найдена папка src/. Запустите инсталлер из корня репозитория!"
    exit 1
fi

echo "=========================================================="
echo "   Добро пожаловать в UniFi Vsratiy PBR-VPN-PROXYFI!   "
echo "=========================================================="

# 1. Накат пакетов
echo "[*] Обновление списков пакетов и установка сисадминского пака..."
apt-get update -y
ADMIN_PACK="mc curl nano wget redsocks htop tcpdump dnsutils net-tools"
DEBIAN_FRONTEND=noninteractive apt-get install -y $ADMIN_PACK
echo "[+] Джентльменский набор успешно установлен!"
echo "--------------------------------------------------"

# 2. Метки безопасности
echo "[*] Сканирование системы на предмет занятых firewall-меток..."
USED_MARKS=$( { iptables-save; ip6tables-save; ip rule show; } 2>/dev/null | grep -oE '0x[0-9a-fA-F]+' | tr '[:upper:]' '[:lower:]' | sort -u )

find_free_fwmark() {
    local candidate_dec=$1
    while true; do
        local candidate_hex=$(printf "0x%x" $candidate_dec)
        if ! echo "$USED_MARKS" | grep -q "^${candidate_hex}$"; then
            echo "$candidate_hex"; return 0
        fi
        candidate_dec=$((candidate_dec + 1))
    done
}
AUTO_MARK_WARP=$(find_free_fwmark 100)
AUTO_MARK_PROXY=$(find_free_fwmark $(( $(printf "%d" $AUTO_MARK_WARP) + 1 )) )

# 3. Сеть
AVAILABLE_TUNNELS=($(ip -br link show | grep -E '^(wg|tun|vti)' | awk '{print $1}'))
if [ ${#AVAILABLE_TUNNELS[@]} -eq 0 ]; then
    read -p "Введите имя интерфейса вручную (например, wgclt4): " SELECTED_IFACE
else
    echo "Найдены активные туннели:"
    for i in "${!AVAILABLE_TUNNELS[@]}"; do echo "  [$i] ${AVAILABLE_TUNNELS[$i]}"; done
    while true; do
        read -p "Выберите номер туннеля для основного канала (0-$(( ${#AVAILABLE_TUNNELS[@]} - 1 ))): " CHOICE
        if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -lt "${#AVAILABLE_TUNNELS[@]}" ]; then
            SELECTED_IFACE="${AVAILABLE_TUNNELS[$CHOICE]}"; break
        else echo "[!] Ошибка ввода. Повторите."; fi
    done
fi

# 4. Прокси
read -p "Включить резервный прокси-сервер? (yes/no): " ANSWER_PROXY
if [ "$ANSWER_PROXY" = "yes" ]; then
    USE_PROXY="yes"
    echo "  [1] socks5 | [2] socks4 | [3] http"
    while true; do
        read -p "Тип прокси (1-3): " P_TYPE_CHOICE
        case $P_TYPE_CHOICE in
            1) PROXY_TYPE="socks5"; break ;;
            2) PROXY_TYPE="socks4"; break ;;
            3) PROXY_TYPE="http"; break ;;
            *) echo "[!] Выберите от 1 до 3." ;;
        esac
    done
    read -p "Введите IP адрес прокси: " PROXY_IP
    read -p "Введите порт прокси: " PROXY_PORT
    read -p "Требуется авторизация? (yes/no): " REQ_AUTH
    if [ "$REQ_AUTH" = "yes" ]; then
        read -p "Логин: " PROXY_USER; read -p "Пароль: " PROXY_PASS
    else
        PROXY_USER=""; PROXY_PASS=""
    fi
else
    USE_PROXY="no"; PROXY_TYPE="socks5"; PROXY_IP="1.2.3.4"; PROXY_PORT="1080"; PROXY_USER=""; PROXY_PASS=""
fi

# 4.2 Оповещения Telegram
echo "--------------------------------------------------"
read -p "Включить алерты в Telegram? (yes/no): " ANSWER_TG
if [ "$ANSWER_TG" = "yes" ]; then
    read -p "Введите токен бота (TG_BOT_TOKEN): " TG_BOT_TOKEN
    read -p "Введите ваш Chat ID (TG_CHAT_ID): " TG_CHAT_ID
else
    TG_BOT_TOKEN=""; TG_CHAT_ID=""
fi

# 4.3 Оповещения Email
read -p "Включить алерты на Email? (yes/no): " ANSWER_EMAIL
if [ "$ANSWER_EMAIL" = "yes" ]; then
    EMAIL_ENABLED="yes"
    read -p "SMTP сервер (например, smtp.yandex.ru): " SMTP_SERVER
    read -p "SMTP порт (465 или 587): " SMTP_PORT
    read -p "SMTP Почта-логин: " SMTP_USER
    read -p "SMTP Пароль приложения: " SMTP_PASS
    read -p "Email получателя алертов: " EMAIL_TO
else
    EMAIL_ENABLED="no"; SMTP_SERVER=""; SMTP_PORT="465"; SMTP_USER=""; SMTP_PASS=""; EMAIL_TO=""
fi

# 5. Сборка и Деплой модулей
MODULE_DIR="/data/unifi-custom-modules/vsratiy-pbr-proxyfi"
mkdir -p "$MODULE_DIR"
mkdir -p /data/on-boot.d

if [ ! -f "$MODULE_DIR/config.conf" ]; then
    cp src/config.conf ./config.conf.tmp
    sed -i "s#TEMPLATE_IFACE#$SELECTED_IFACE#g" ./config.conf.tmp
    sed -i "s#TEMPLATE_FWMARK_WARP#$AUTO_MARK_WARP#g" ./config.conf.tmp
    sed -i "s#TEMPLATE_FWMARK_PROXY#$AUTO_MARK_PROXY#g" ./config.conf.tmp
    sed -i "s#TEMPLATE_USE_PROXY#$USE_PROXY#g" ./config.conf.tmp
    sed -i "s#TEMPLATE_PROXY_TYPE#$PROXY_TYPE#g" ./config.conf.tmp
    sed -i "s#TEMPLATE_PROXY_IP#$PROXY_IP#g" ./config.conf.tmp
    sed -i "s#TEMPLATE_PROXY_PORT#$PROXY_PORT#g" ./config.conf.tmp
    sed -i "s#TEMPLATE_PROXY_USER#$PROXY_USER#g" ./config.conf.tmp
    sed -i "s#TEMPLATE_PROXY_PASS#$PROXY_PASS#g" ./config.conf.tmp
    sed -i "s#TEMPLATE_TG_BOT_TOKEN#$TG_BOT_TOKEN#g" ./config.conf.tmp
    sed -i "s#TEMPLATE_TG_CHAT_ID#$TG_CHAT_ID#g" ./config.conf.tmp
    sed -i "s#TEMPLATE_EMAIL_ENABLED#$EMAIL_ENABLED#g" ./config.conf.tmp
    sed -i "s#TEMPLATE_SMTP_SERVER#$SMTP_SERVER#g" ./config.conf.tmp
    sed -i "s#TEMPLATE_SMTP_PORT#$SMTP_PORT#g" ./config.conf.tmp
    sed -i "s#TEMPLATE_SMTP_USER#$SMTP_USER#g" ./config.conf.tmp
    sed -i "s#TEMPLATE_SMTP_PASS#$SMTP_PASS#g" ./config.conf.tmp
    sed -i "s#TEMPLATE_EMAIL_TO#$EMAIL_TO#g" ./config.conf.tmp
    mv ./config.conf.tmp "$MODULE_DIR/config.conf"
fi

cp src/unifi-pbr-core.sh "$MODULE_DIR/unifi-pbr-core.sh" && chmod +x "$MODULE_DIR/unifi-pbr-core.sh"
cp src/alert-agent.sh "$MODULE_DIR/alert-agent.sh" && chmod +x "$MODULE_DIR/alert-agent.sh"
cp src/uninstall.sh "$MODULE_DIR/uninstall.sh" && chmod +x "$MODULE_DIR/uninstall.sh"
cp src/vsratiy-pbr-proxyfi.service "$MODULE_DIR/vsratiy-pbr-proxyfi.service"
cp src/vsratiy-pbr-proxyfi.service /etc/systemd/system/vsratiy-pbr-proxyfi.service

# 6. Крон и Автозагрузка
echo "* * * * * root $MODULE_DIR/unifi-pbr-core.sh cron-check >/dev/null 2>&1" > /etc/cron.d/vsratiy-pbr-watchdog
/etc/init.d/cron restart 2>/dev/null || systemctl restart cron 2>/dev/null

cat << 'EOF' > /data/on-boot.d/99-vsratiy-pbr-proxyfi.sh
#!/bin/sh
PERSISTENT_DIR="/data/unifi-custom-modules/vsratiy-pbr-proxyfi"
if [ -f "$PERSISTENT_DIR/vsratiy-pbr-proxyfi.service" ]; then
    cp "$PERSISTENT_DIR/vsratiy-pbr-proxyfi.service" /etc/systemd/system/vsratiy-pbr-proxyfi.service
    echo "* * * * * root $PERSISTENT_DIR/unifi-pbr-core.sh cron-check >/dev/null 2>&1" > /etc/cron.d/vsratiy-pbr-watchdog
    systemctl daemon-reload
    systemctl enable vsratiy-pbr-proxyfi.service
    systemctl start vsratiy-pbr-proxyfi.service
    /etc/init.d/cron restart 2>/dev/null || systemctl restart cron 2>/dev/null
fi
EOF
chmod +x /data/on-boot.d/99-vsratiy-pbr-proxyfi.sh

systemctl daemon-reload
systemctl enable vsratiy-pbr-proxyfi.service
systemctl start vsratiy-pbr-proxyfi.service

echo "--------------------------------------------------"
echo "[🎉] Модульная Жирная Тварь запущена и готова к деплою на GitHub!"
