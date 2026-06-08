# UniFi Vsratiy PBR-VPN-PROXYFI

Модульное решение для продвинутой маршрутизации (PBR) на устройствах UniFi (UDM/UDM Pro/SE), позволяющее гибко перенаправлять трафик через VPN-туннели или прокси-серверы.



## 🚀 Возможности
- **Модульность:** Изолированная логика каждого компонента.
- **Smart PBR:** Гибкое управление потоками через `ipset` и `iptables`.
- **Failover:** Автоматическое переключение на прокси при недоступности VPN.
- **Мониторинг:** Встроенный агент уведомлений (Telegram/Email).
- **Watchdog:** Автоматическое восстановление сервиса после обновлений UniFi OS.

## 📦 Структура
.
├── install.sh                # Мастер-инсталлер
├── uninstall.sh              # Полная очистка
└── src/
├── config.conf           # Шаблон конфигурации
├── unifi-pbr-core.sh     # Ядро логики (PBR)
├── alert-agent.sh        # Агент алертов
└── vsratiy-pbr-proxyfi.service # systemd unit

## 🛠️ Установка
Можно лапками скачать и положить в нужную директорию вида "unifi-custom-modules/vsratiy-pbr-proxyfi" чтобы не парится потом.
# Клонирование
git clone [https://github.com/Rew-weR/unifi-custom-modules.git](https://github.com/Rew-weR/unifi-custom-modules.git)
cd unifi-custom-modules/vsratiy-pbr-proxyfi

# Права
chmod +x install.sh uninstall.sh src/*.sh

# Запуск
./install.sh

При установке скрипт установщик по спрашивает вас обо всяком, отвечайте честно ) иначе можно случайно сломать что то наверное.

Естественно все предложенные скрипты и модули вы используеете на свой страх и риск, У меня вроде бы все работает.

Резервные копии наше ВСЕ берегити их и храните в нескольких местах.
