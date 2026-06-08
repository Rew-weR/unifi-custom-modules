#!/bin/bash
# =========================================================================
#  UniFi Vsratiy PBR-VPN-PROXYFI — CORE ENGINE (Immortal Edition)
# =========================================================================
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

MODULE_DIR="/data/unifi-custom-modules/vsratiy-pbr-proxyfi"
CONFIG="$MODULE_DIR/config.conf"
ALERT_AGENT="$MODULE_DIR/alert-agent.sh"

if [ ! -f "$CONFIG" ]; then
    logger -t vsratiy-pbr "[⚠️] Критическая ошибка: Конфиг PROXYFI не найден!"
    exit 0
fi
source $CONFIG

# Роскомпозор, я вашу маму в кино водил.

verify_environment_safety() {
    for cmd in ip iptables ipset ss logger ping; do
        if ! command -v $cmd >/dev/null 2>&1; then
            [ -x "$ALERT_AGENT" ] && $ALERT_AGENT "SAFE-MODE АКТИВИРОВАН: Утилита $cmd отсутствует!"
            exit 0
        fi
    done
    ipset list >/dev/null 2>&1 || exit 0
}

find_free_prio() {
    local start_prio=$1
    while ip rule show | grep -q "^${start_prio}:"; do start_prio=$((start_prio + 1)); done
    echo "$start_prio"
}

start_engine() {
    verify_environment_safety
    ensure_cron_exists

    PRIO_WARP=$(find_free_prio 12000)
    PRIO_PROXY=$(find_free_prio $((PRIO_WARP + 1)))
    echo "RUNTIME_PRIO_WARP=$PRIO_WARP" > "$MODULE_DIR/.runtime_prio"
    echo "RUNTIME_PRIO_PROXY=$PRIO_PROXY" >> "$MODULE_DIR/.runtime_prio"

    TABLE_WARP_ID=111
    while ip route show table $TABLE_WARP_ID 2>/dev/null | grep -q "default"; do TABLE_WARP_ID=$((TABLE_WARP_ID + 1)); done
    TABLE_PROXY_ID=112
    while ip route show table $TABLE_PROXY_ID 2>/dev/null | grep -q "default"; do TABLE_PROXY_ID=$((TABLE_PROXY_ID + 1)); done
    LOCAL_REDSOCKS_PORT=15555
    while ss -tlnp | grep -q ":$LOCAL_REDSOCKS_PORT "; do LOCAL_REDSOCKS_PORT=$((LOCAL_REDSOCKS_PORT + 1)); done

    ipset create unifi_pbr_set hash:ip comment 2>/dev/null
    ipset create unifi_pbr_set6 hash:ip family inet6 comment 2>/dev/null

    DNSMASQ_CONF="/etc/dnsmasq.d/unifi-pbr.conf"
    echo -n "" > $DNSMASQ_CONF
    for domain in $DOMAINS; do echo "ipset=/$domain/unifi_pbr_set,unifi_pbr_set6" >> $DNSMASQ_CONF; done

    TUNNEL_ALIVE=0
    if ip link show dev "$TARGET_INTERFACE" >/dev/null 2>&1; then
        ip route add default dev $TARGET_INTERFACE table $TABLE_WARP_ID 2>/dev/null
        if ping -c 2 -W 3 -I "$TARGET_INTERFACE" 1.1.1.1 >/dev/null 2>&1; then
            TUNNEL_ALIVE=1
        else
            logger -t vsratiy-pbr "[⚠️] Пинг через $TARGET_INTERFACE упал. Блокировка протокола?"
            ip route flush table $TABLE_WARP_ID 2>/dev/null
        fi
    else
        [ -x "$ALERT_AGENT" ] && $ALERT_AGENT "Интерфейс $TARGET_INTERFACE не найден в системе после обновления UniFi!"
    fi

    if [ "$TUNNEL_ALIVE" -eq 1 ]; then
        ip rule add fwmark $FWMARK_WARP table $TABLE_WARP_ID priority $PRIO_WARP 2>/dev/null
        iptables -t mangle -A OUTPUT -m set --match-set unifi_pbr_set daddr -j MARK --set-mark $FWMARK_WARP
        ip6tables -t mangle -A OUTPUT -m set --match-set unifi_pbr_set6 daddr -j MARK --set-mark $FWMARK_WARP
    else
        logger -t vsratiy-pbr "[🔄 Failover] Трафик перенаправлен на резервный канал."
    fi

    if [ "$USE_PROXY" = "yes" ]; then
        if [ -x "$(command -v redsocks)" ]; then
            cat << EOF > "$MODULE_DIR/redsocks.conf"
base { log_debug = off; log_info = off; log = "syslog:local7"; daemon = on; redirector = iptables; }
redsocks { local_ip = 127.0.0.1; local_port = $LOCAL_REDSOCKS_PORT; ip = $PROXY_IP; port = $PROXY_PORT; type = $PROXY_TYPE;
EOF
            [ -n "$PROXY_USER" ] && [ -n "$PROXY_PASS" ] && echo "    login = \"$PROXY_USER\"; password = \"$PROXY_PASS\";" >> "$MODULE_DIR/redsocks.conf"
            echo "}" >> "$MODULE_DIR/redsocks.conf"
            redsocks -c "$MODULE_DIR/redsocks.conf" 2>/dev/null
            
            ip route add default dev lo table $TABLE_PROXY_ID 2>/dev/null
            ip rule add fwmark $FWMARK_PROXY table $TABLE_PROXY_ID priority $PRIO_PROXY 2>/dev/null
            
            if [ "$TUNNEL_ALIVE" -eq 1 ]; then
                iptables -t nat -A OUTPUT -m set --match-set unifi_pbr_set daddr -p tcp -m multiport --dports 80,443 -m mark --mark $FWMARK_PROXY -j REDIRECT --to-ports $LOCAL_REDSOCKS_PORT
            else
                iptables -t nat -A OUTPUT -m set --match-set unifi_pbr_set daddr -p tcp -m multiport --dports 80,443 -j REDIRECT --to-ports $LOCAL_REDSOCKS_PORT
            fi
        fi
    fi
    killall -HUP dnsmasq
}

stop_engine() {
    if [ -f "$MODULE_DIR/.runtime_prio" ]; then source "$MODULE_DIR/.runtime_prio"; fi
    killall redsocks 2>/dev/null
    [ -n "$RUNTIME_PRIO_WARP" ] && ip rule del priority $RUNTIME_PRIO_WARP 2>/dev/null
    [ -n "$RUNTIME_PRIO_PROXY" ] && ip rule del priority $RUNTIME_PRIO_PROXY 2>/dev/null
    for table_id in $(seq 111 125); do ip route flush table $table_id 2>/dev/null; done
    iptables -t mangle -D OUTPUT -m set --match-set unifi_pbr_set daddr -j MARK --set-mark $FWMARK_WARP 2>/dev/null
    ip6tables -t mangle -D OUTPUT -m set --match-set unifi_pbr_set6 daddr -j MARK --set-mark $FWMARK_WARP 2>/dev/null
    iptables -t nat -D OUTPUT -m set --match-set unifi_pbr_set daddr -p tcp -m multiport --dports 80,443 -j REDIRECT 2>/dev/null
    ipset flush unifi_pbr_set 2>/dev/null
    ipset flush unifi_pbr_set6 2>/dev/null
    rm -f /etc/dnsmasq.d/unifi-pbr.conf
    rm -f "$MODULE_DIR/.runtime_prio"
}

ensure_cron_exists() {
    if [ ! -f "/etc/cron.d/vsratiy-pbr-watchdog" ]; then
        echo "* * * * * root $MODULE_DIR/unifi-pbr-core.sh cron-check >/dev/null 2>&1" > /etc/cron.d/vsratiy-pbr-watchdog
        /etc/init.d/cron restart 2>/dev/null || systemctl restart cron 2>/dev/null
    fi
}

cron_check_logic() {
    local service_file="/etc/systemd/system/vsratiy-pbr-proxyfi.service"
    local need_reload=0

    if [ ! -f "$service_file" ]; then
        [ -x "$ALERT_AGENT" ] && $ALERT_AGENT "Обновление UniFi OS затерло сервис! Восстановление..."
        cp "$MODULE_DIR/vsratiy-pbr-proxyfi.service" "$service_file"
        need_reload=1
    fi

    ensure_cron_exists

    if [ "$need_reload" -eq 1 ]; then
        systemctl daemon-reload
        systemctl enable vsratiy-pbr-proxyfi.service
    fi

    if systemctl is-active --quiet vsratiy-pbr-proxyfi.service; then
        if [ $(( $(date +%M) % 5 )) -eq 0 ]; then
            if ip link show dev "$TARGET_INTERFACE" >/dev/null 2>&1; then
                if ! ping -c 2 -W 3 -I "$TARGET_INTERFACE" 1.1.1.1 >/dev/null 2>&1; then
                    systemctl restart vsratiy-pbr-proxyfi.service
                fi
            fi
        fi
    else
        systemctl restart vsratiy-pbr-proxyfi.service
    fi
}

case "$1" in
    start) stop_engine; start_engine ;;
    stop) stop_engine; killall -HUP dnsmasq ;;
    cron-check) cron_check_logic ;;
    *) echo "Использование: $0 {start|stop|cron-check}"; exit 1 ;;
esac
