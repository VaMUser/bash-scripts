# README: dev_station_prepare.sh

## 📌 Назначение

Скрипт `dev_station_prepare.sh` подготавливает Debian-сервер для работы через:

- VS Code Remote SSH
- Ansible + ansible-lint
- нестабильное соединение (tmux)

---

# 🚀 0. Как использовать

Запускать **от root** на чистой Debian:

```bash
bash dev_station_prepare.sh
```

Или со своим никнеймом

```bash
USERNAME=dev bash dev_station_prepare.sh
```

После выполнения:

```bash
ssh user@<host>
```

---

# ⚙️ 1. Что делает скрипт (по шагам)

## 🔹 [1] Установка базовых пакетов

```bash
apt update
apt install -y sudo python3 python3-pip pipx git tmux mc nano
```

---

## 🔹 [2] Создание пользователя

```bash
USERNAME="user"
```

- создаётся пользователь `user`
- добавляется в группу `sudo`

---

## 🔹 [3] Настройка SSH

```bash
cp /root/.ssh/authorized_keys "$USER_HOME/.ssh/"
```

- копируются ключи root → user
- права:
  - `700 ~/.ssh`
  - `600 authorized_keys`

---

## 🔹 [4] Настройка pipx

```bash
pipx ensurepath
```

Добавляет `~/.local/bin` в PATH

---

## 🔹 [5] Установка Ansible

```bash
pipx install ansible-lint
pipx install ansible-core
pipx inject ansible-lint ansible
```

---

## 🔹 [6] Завершение

```bash
echo "[6] Done. Reconnect as user"
```

---

# 💻 2. Первичная настройка на сервере

## Git (ОБЯЗАТЕЛЬНО)

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
git config --global core.editor "nano"
```

Проверка:

```bash
git config --list
```

---

# 💻 3. Настройка VS Code

## Расширения

- Remote - SSH
- Ansible (Red Hat)
- YAML (Red Hat)
- Python (опционально)

---

## YAML + Ansible Vault (ВАЖНО)

Чтобы VS Code не ругался на vault-поля (`!vault`), добавить в настройки:

```json
{
  "yaml.customTags": [
    "!vault scalar"
  ]
}
```

---

## SSH config (локальная машина)

Файл: `~/.ssh/config`

```ssh
Host my-vm
    HostName <IP>
    User user
    IdentityFile ~/.ssh/id_rsa
    ServerAliveInterval 30
    ServerAliveCountMax 3
    ForwardAgent yes
```

---

## 🔑 Проброс SSH-агента (Windows)

### Вариант 1: Windows OpenSSH (рекомендуется)

1. Включить службу:
```powershell
Get-Service ssh-agent | Set-Service -StartupType Automatic
Start-Service ssh-agent
```

2. Добавить ключ:
```powershell
ssh-add $env:USERPROFILE\.ssh\id_rsa
```

3. Проверить:
```powershell
ssh-add -l
```

---

### Вариант 2: Git Bash

```bash
eval $(ssh-agent)
ssh-add ~/.ssh/id_rsa
```

---

### Проверка на сервере

После подключения:

```bash
ssh-add -l
```

Если ключи видны — всё работает.

---

## Подключение

```
Ctrl+Shift+P → Remote-SSH: Connect to Host
```

---

# 🧩 4. Настройки VS Code

## tmux как терминал

```json
{
  "terminal.integrated.profiles.linux": {
    "tmux work": {
      "path": "/bin/bash",
      "args": ["-lc", "tmux attach -t work || tmux new -s work"]
    }
  },
  "terminal.integrated.defaultProfile.linux": "tmux work"
}
```

---

## ansible-lint

```json
{
  "ansible.validation.lint.path": "~/.local/bin/ansible-lint",
  "ansible.validation.lint.enabled": true
}
```

---

# 🔄 5. Workflow

1. Подключился через VS Code  
2. Открыл проект  
3. Открыл терминал  
4. Работаешь внутри tmux  

---

# 🌐 6. Нестабильный SSH

Используется:

- tmux
- SSH keepalive

---

# ⚠️ 7. Проблемы

## ansible-lint не найден

```bash
echo $PATH
```

Должен содержать `~/.local/bin`

---

## Permission denied

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

---

# 🧾 Итог

Готовая среда для:

- удалённой разработки
- ansible
- нестабильных соединений
