#!/bin/bash
# =========================================================================
#  UniFi Vsratiy PBR-VPN-PROXYFI — NOTIFICATION AGENT
# =========================================================================
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

MODULE_DIR="/data/unifi-custom-modules/vsratiy-pbr-proxyfi"
CONFIG="$MODULE_DIR/config.conf"
[ -f "$CONFIG" ] && source "$CONFIG"

MESSAGE="$1"
if [ -z "$MESSAGE" ]; then echo "Использование: $0 'текст ошибки'"; exit 1; fi

# 1. Локальный syslog (База)
logger -t vsratiy-pbr "[🔔 ALERT] $MESSAGE"

# 2. Интеграция в системный лог UniFi OS (для нативного пуша)
if [ -f "/var/log/messages" ]; then
    echo "$(date '+%b %d %H:%M:%S') $(hostname) user.err vsratiy-pbr: $MESSAGE" >> /var/log/messages
fi

# 3. Асинхронный выстрел в Telegram
if [ -n "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
    local_hostname=$(hostname)
    payload="<b>🚨 [${local_hostname}] PROXYFI ALERT</b>\n\n<code>${MESSAGE}</code>"
    curl -s -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TG_CHAT_ID}" \
        -d "text=${payload}" \
        -d "parse_mode=HTML" \
        --max-time 10 >/dev/null 2>&1 &
fi

# 4. Асинхронный выстрел на Email через встроенный Python
if [ "$EMAIL_ENABLED" = "yes" ]; then
    local_hostname=$(hostname)
    subject="[⚠️ PROXYFI ALERT] on $local_hostname"
    
    python3 - <<EOF >/dev/null 2>&1 &
import smtplib
from email.mime.text import MIMEText

msg = MIMEText("""$MESSAGE""")
msg['Subject'] = "$subject"
msg['From'] = "$SMTP_USER"
msg['To'] = "$EMAIL_TO"

try:
    if "$SMTP_PORT" == "465":
        server = smtplib.SMTP_SSL("$SMTP_SERVER", 465, timeout=10)
    else:
        server = smtplib.SMTP("$SMTP_SERVER", int("$SMTP_PORT"), timeout=10)
        server.starttls()
    if "$SMTP_USER" and "$SMTP_PASS":
        server.login("$SMTP_USER", "$SMTP_PASS")
    server.sendmail("$SMTP_USER", ["$EMAIL_TO"], msg.as_string())
    server.quit()
except Exception:
    pass
EOF
fi
