#!/bin/bash
# =========================================================================
#  UniFi Vsratiy PBR-VPN-PROXYFI — UNINSTALLER
# =========================================================================
MODULE_DIR="/data/unifi-custom-modules/vsratiy-pbr-proxyfi"

if [ "$EUID" -ne 0 ]; then echo "Ошибка: Нужен root."; exit 1; fi

echo "[*] Останавливаю службу..."
systemctl stop vsratiy-pbr-proxyfi.service 2>/dev/null
systemctl disable vsratiy-pbr-proxyfi.service 2>/dev/null

echo "[*] Удаляю системные линки..."
rm -f /data/on-boot.d/99-vsratiy-pbr-proxyfi.sh
rm -f /etc/systemd/system/vsratiy-pbr-proxyfi.service
rm -f /etc/cron.d/vsratiy-pbr-watchdog

echo "[*] Удаляю модуль и очищаю сеть..."
if [ -f "$MODULE_DIR/unifi-pbr-core.sh" ]; then
    "$MODULE_DIR/unifi-pbr-core.sh" stop
fi
rm -rf "$MODULE_DIR"
ipset destroy unifi_pbr_set 2>/dev/null
ipset destroy unifi_pbr_set6 2>/dev/null

systemctl daemon-reload
/etc/init.d/cron restart 2>/dev/null || systemctl restart cron 2>/dev/null
killall -HUP dnsmasq

echo "[🎉] Готово. Всратость полностью удалена."
