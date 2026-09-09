# Proxmox: remove "No valid subscription" nag

Скрипт remove_nag.sh патчит фронтенд Proxmox и убирает окно
"No valid subscription" (Subscription Nag) из веб‑интерфейса.

Патчатся оба файла:
- /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
- /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.min.js


## Логика работы

1. В каждом целевом файле ищется строка:
   No valid subscription

   Если строка не найдена — считается, что патч уже применён
   (или версия файла изменилась), изменений не выполняется.

2. Если строка найдена — вычисляется SHA256 исходного файла
   (до внесения изменений).

3. Создаётся бэкап рядом с оригиналом:
   <имя_файла>.<sha12>.bak

   где sha12 — первые 12 символов SHA256.

   Если такой бэкап уже существует (т.е. данный оригинал
   уже сохранялся ранее), новый бэкап не создаётся.

4. Скрипт находит вызов Ext.Msg.show(...), который содержит
   строку "No valid subscription", и полностью удаляет этот
   вызов, заменяя его на прямой вызов команды:

   orig_cmd();

   В минифицированной версии используется фактическое имя
   параметра функции (например t();), которое определяется
   автоматически.

5. Если хотя бы один файл был изменён, выполняется:
   systemctl restart pveproxy

   Если изменений не было — перезапуск не выполняется.


## Идемпотентность

- Повторный запуск безопасен.
- Повторные бэкапы одного и того же исходника не создаются.
- После обновления пакета proxmox-widget-toolkit патч
  автоматически применится снова (если настроен apt hook).


## Установка

Рекомендуемое размещение:

    /usr/local/sbin/remove_nag.sh

Установка:

    install -m 0755 remove_nag.sh /usr/local/sbin/remove_nag.sh


## Автозапуск после обновлений (APT hook)

Создать файл для apt:

    install -m 0644 /dev/stdin /etc/apt/apt.conf.d/99-remove-nag <<'EOF'
    DPkg::Post-Invoke { "/usr/local/sbin/remove_nag.sh >/dev/null 2>&1 || true"; };
    EOF

После этого скрипт будет автоматически запускаться
после каждого apt upgrade / full-upgrade.


## Откат

Для восстановления используйте соответствующий .bak файл:

    cp -a proxmoxlib.js.<sha12>.bak proxmoxlib.js
    cp -a proxmoxlib.min.js.<sha12>.bak proxmoxlib.min.js

После восстановления:

    systemctl restart pveproxy
