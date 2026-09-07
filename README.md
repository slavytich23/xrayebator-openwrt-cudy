# Xrayebator OpenWrt/Cudy companion

Независимый набор для запуска Xray-клиента на OpenWrt-роутере с безопасным
включением, автоматическим откатом, fail-closed маршрутизацией, контролем
здоровья и резервным интернетом на Windows.

Проверено в двух реальных схемах. Исходный односетевой режим остаётся
совместимым, а для одного основного Cudy теперь есть изолированный режим
Direct/VPN:

```text
интернет/PPPoE → Cudy WR3000H 1.0
                 ├─ br-lan: LAN2–LAN4 + Direct Wi-Fi 2,4/5 ГГц → напрямую
                 └─ br-vpn: LAN1 + VPN Wi-Fi 2,4/5 ГГц → Xray TUN → интернет
```

Проект дополняет [Xrayebator](https://github.com/howdeploy/Xrayebator), который
настраивает VPS и выдаёт клиентские профили. Этот репозиторий отвечает только
за клиентскую сторону OpenWrt и необязательный резервный маршрут Windows. Это
не официальный компонент Xrayebator.

## Что здесь есть

- OpenWrt `procd`-сервис с обязательной проверкой `xray run -test`;
- staged activation: 30–600 секунд на проверку, иначе автоматический откат;
- отдельный network namespace для проверки DNS и HTTPS именно через туннель;
- различение поломки туннеля и обрыва домашнего WAN;
- ограничение частоты перезапусков и журнал причин;
- контроль RSS/доступной памяти для маломощных роутеров;
- fail-closed policy: LAN не уходит напрямую в WAN, если TUN исчез;
- выбор конкретной OpenWrt-сети для Xray через постоянную UCI-конфигурацию;
- инструменты для двух мостов, одного SSID на оба диапазона и обратимого
  переноса одного LAN-порта в VPN-сеть;
- необязательный Windows-монитор: Ethernet через Cudy основной, Wi-Fi другого
  роутера — резерв;
- пример XHTTP/XMUX `maxConnections: 1`, который уменьшил расход памяти в
  проверенной конфигурации.

## Проверенная граница

Полевая проверка выполнялась на Cudy WR3000H 1.0 с OpenWrt 25.12.x и
Xray-core. После ограничения XHTTP XMUX наблюдавшийся RSS снизился примерно со
105–107 МБ до 53–58 МБ. Контрольный прогон длился 1 805 секунд: 59 проверок,
0 ошибок проб, PID не изменился; затем прошли 5 из 5 загрузок общим объёмом
47 002 980 байт.

Это результат одного стенда, а не гарантия для любого провайдера, прошивки или
транспорта. Порог памяти и сетевые адреса сделаны настраиваемыми.

## Требования

- поддерживаемый OpenWrt для точной ревизии роутера;
- рабочий Xray-core и уже подготовленный приватный клиентский конфиг;
- `curl`, `ip-full` с network namespaces/veth, `nftables`, `jsonfilter`;
- BusyBox `setsid` для действительно отделённого таймера автоотката;
- TUN-интерфейс, по умолчанию `xrayebator0`;
- независимый путь восстановления до первой активации.

Этот репозиторий не содержит прошивок. Для Cudy обязательно сверяйте точную
аппаратную ревизию с официальной таблицей OpenWrt. Не прошивайте образ от
другой модели или ревизии.

## Установка на OpenWrt

1. Скопируйте дерево `openwrt/files/` поверх корня роутера, сохранив пути.
2. Сделайте исполняемыми файлы в `/etc/init.d`, `/usr/bin` и
   `/usr/libexec/xrayebator-safe`.
3. Создайте каталог и локально положите приватный конфиг:

   ```sh
   mkdir -p /etc/xrayebator-safe
   chmod 700 /etc/xrayebator-safe
   chmod 600 /etc/xrayebator-safe/client.json
   ```

4. Проверьте `/etc/config/xrayebator_safe`. По умолчанию сохранён совместимый
   односетевой режим `lan`/`br-lan`/`192.168.10.0/24`. Для другой сети измените
   UCI-параметры `client_*` и `health_*`; переменные окружения с теми же
   именами остаются временным override.
5. Проверьте конфиг, не включая маршрутизацию:

   ```sh
   /etc/init.d/xrayebator-safe check
   ```

6. Запустите пробную активацию на 90 секунд:

   ```sh
   xrayebator-safe-activate 90
   ```

7. Проверьте доступ к роутеру, DNS, HTTPS и внешний IP. Если всё исправно:

   ```sh
   xrayebator-safe-commit
   ```

Если подтверждение не выполнено, сервис сам остановится и отключится. Ручной
откат: `xrayebator-safe-rollback`.

## Две сети на одном Cudy

[docs/dual-network.md](docs/dual-network.md) описывает проверенную схему, где:

- один LAN-порт и один двухдиапазонный SSID относятся к `br-vpn`;
- остальные LAN-порты и второй двухдиапазонный SSID остаются в `br-lan`;
- одинаковое имя на 2,4 и 5 ГГц позволяет клиенту самому выбирать диапазон;
- ошибка записи, reload или проверки автоматически восстанавливает backup;
- старые SSID отключаются только отдельной финальной командой после проверок;
- полный откат восстанавливает сохранённые UCI-файлы.

Инструменты находятся в `openwrt/tools/`. Настройщик сначала работает как
read-only preflight и меняет конфигурацию только с `APPLY_CHANGES=1`. Ключи
Wi-Fi вводятся скрыто либо читаются из локальных файлов с режимом `0600`; они
не передаются аргументами командной строки.

## DNS в условиях фильтрации

Открытый DNS или отдельное прямое подключение к публичному DoH может
перехватываться либо блокироваться. Устойчивый целевой режим — full TUN:
приложения, системный DNS и подключение к DoH идут внутри одного рабочего
туннеля. Напрямую разрешаются только локальные и служебные сети.

`route-guard` перенаправляет DNS только выбранной клиентской сети на
настраиваемый адрес захвата и запрещает этой сети выходить напрямую через WAN.
Глобальной блокировки DNS самого роутера больше нет: она затрагивала независимую
Direct-сеть. Сам адрес захвата не является защитой — DNS VPN-клиентов обязан
быть обработан Xray внутри TUN. Актуальный управляемый профиль HAPP лучше
получать из свежей версии Xrayebator, а не копировать чужой JSON.

## XHTTP/XMUX и память

Фрагмент [examples/xhttp-xmux-fragment.json](examples/xhttp-xmux-fragment.json)
показывает единственную проверенную настройку. Её нужно добавить в
`streamSettings.xhttpSettings` соответствующего клиентского outbound, сохранив
остальные параметры профиля. Перед включением всегда выполняйте
`xray run -test` и храните локальный откат.

## Резервный интернет Windows

[windows/cudy-primary-failover-monitor.ps1](windows/cudy-primary-failover-monitor.ps1)
проверяет HTTPS отдельно с адреса Cudy Ethernet и резервного Wi-Fi. После
нескольких последовательных ошибок он повышает метрику Ethernet только если
резерв действительно работает; после восстановления возвращает Cudy основным.

Сначала запустите монитор диагностически:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\cudy-primary-failover-monitor.ps1 `
  -PrimaryInterfaceAlias 'Ethernet' `
  -BackupInterfaceAlias 'Wi-Fi' `
  -BackupWifiProfile 'YOUR_WIFI_PROFILE' `
  -PrimaryGateway '192.168.20.1' `
  -BackupGateway '192.168.10.1' `
  -NoChange -MaxCycles 4
```

Только после проверки параметров можно убрать `-NoChange` или установить
задачу через `windows/install-cudy-failover-monitor.ps1` из повышенной
PowerShell.

## Тесты

Из PowerShell в корне репозитория:

```powershell
.\tests\test-openwrt-scripts.ps1
.\tests\test-windows-failover-monitor.ps1
.\tests\test-secret-hygiene.ps1
```

Тест OpenWrt выполняет `sh -n` через WSL, если WSL доступен. Полный тест
network namespace требует Linux root и намеренно не запускается автоматически:

```powershell
.\tests\run-all.ps1 -Integration
```

## Что намеренно не публикуется

- готовая прошивка;
- рабочий `client.json`;
- подписки, UUID, ключи, адреса VPS;
- сырые логи, MAC/IP домашней сети и packet capture;
- нестабильные списки адресов отдельных игр.

English summary: community-tested OpenWrt client hardening for Xrayebator/Xray,
including staged rollback, fail-closed routing, WAN-aware health supervision,
memory-pressure control, dual Direct/VPN bridges, and optional Windows
dual-uplink failover.

## Лицензия

MIT. См. [LICENSE](LICENSE) и [NOTICE.md](NOTICE.md).
