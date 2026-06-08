# UniFi Vsratiy PBR-VPN-PROXYFI

Модульное решение для продвинутой маршрутизации (PBR) на устройствах UniFi (UDM/UDM Pro/SE), позволяющее гибко перенаправлять трафик через VPN-туннели или прокси-серверы.

## 🚀 Возможности
- **Модульная архитектура:** Разделение логики маршрутизации, конфигурации и алертов.
- **Smart PBR:** Автоматическое определение доменов для обхода ограничений через `ipset`.
- **Failover-ready:** Автоматический переключатель на резервный прокси-канал при падении основного туннеля.
- **Система уведомлений:** Интегрированный агент для отправки оповещений в Telegram и на Email.
- **Watchdog:** Автоматический контроль состояния службы через `systemd` и `cron`.

## 📦 Структура
```text
.
├── install.sh                # Мастер-инсталлер
├── uninstall.sh              # Полная очистка системы
└── src/
    ├── config.conf           # Шаблон конфигурации
    ├── unifi-pbr-core.sh     # Ядро маршрутизации
    ├── alert-agent.sh        # Агент уведомлений
    └── vsratiy-pbr-proxyfi.service # systemd-юнит

    ⚙️ Установка
Клонируйте репозиторий:

Bash
git clone [https://github.com/ВАШ_НИК/vsratiy-pbr-proxyfi.git](https://github.com/ВАШ_НИК/vsratiy-pbr-proxyfi.git)
cd vsratiy-pbr-proxyfi
Сделайте скрипты исполняемыми:

Bash
chmod +x install.sh uninstall.sh src/*.sh
Запустите инсталлер:

Bash
sudo ./install.sh
⚠️ Безопасность
Все секретные данные (токены ботов, пароли SMTP) хранятся локально в config.conf
