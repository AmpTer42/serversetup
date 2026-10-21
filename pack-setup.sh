#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  Установка Tailscale, Nushell и Docker на Ubuntu
#  Запуск: bash install.sh
# ============================================================

CURRENT_USER="${SUDO_USER:-${USER:-$(id -un)}}"

# -------------------- 1. Tailscale (через apt) --------------
echo ">>> Установка Tailscale..."
if command -v tailscale >/dev/null 2>&1; then
    echo "Tailscale уже установлен, пропускаем."
else
    curl -fsSL https://tailscale.com/install.sh | sh
fi

# -------------------- 2. Nushell (через Snap) ---------------
echo ">>> Установка Nushell (snap)..."
if command -v nu >/dev/null 2>&1; then
    echo "Nushell уже установлен, пропускаем."
else
    sudo snap install nushell --classic
fi

# -------------------- 3. Docker (через apt) -----------------
echo ">>> Docker: удаление старых версий..."
OLD_PKGS=$(dpkg --get-selections \
    docker.io docker-compose docker-compose-v2 docker-doc \
    docker-buildx podman-docker containerd runc 2>/dev/null \
    | awk '{print $1}' || true)

if [ -n "${OLD_PKGS}" ]; then
    sudo apt remove -y ${OLD_PKGS}
else
    echo "Старых пакетов Docker не найдено."
fi

echo ">>> Docker: добавление официального GPG-ключа..."
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo ">>> Docker: добавление репозитория..."
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update

echo ">>> Docker: установка пакетов..."
sudo apt install -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

echo ">>> Docker: создание группы и добавление пользователя ${CURRENT_USER}..."
sudo groupadd -f docker
sudo usermod -aG docker "${CURRENT_USER}"

# --- ВАЖНО: сервис Docker НЕ запускаем до настройки NVIDIA ---

# -------------------- 4. NVIDIA Container Toolkit ------------
echo ">>> NVIDIA: установка зависимостей..."
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg2

echo ">>> NVIDIA: добавление репозитория..."
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
    && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null

echo ">>> NVIDIA: обновление индекса пакетов..."
sudo apt-get update

echo ">>> NVIDIA: установка пакетов..."
sudo apt-get install -y \
    nvidia-container-toolkit \
    nvidia-container-toolkit-base \
    libnvidia-container-tools \
    libnvidia-container1

echo ">>> NVIDIA: настройка Docker runtime..."
sudo nvidia-ctk runtime configure --runtime=docker

# -------------------- 5. Запуск Docker ----------------------
echo ">>> Docker: запуск сервиса..."
sudo systemctl enable --now docker

# -------------------- Итог --------------------
echo
echo "============================================================"
echo " Готово!"
echo " Tailscale : $(command -v tailscale || echo 'не найден')"
echo " Nushell   : $(command -v nu        || echo 'не найден')"
echo " Docker    : $(docker --version    2>/dev/null || echo 'не найден')"
ehco " NVIDIA CT : $(command -v nvidia-ctk || echo 'не найден')"
echo
echo " ВАЖНО: чтобы использовать docker без sudo, выйдите из"
echo " сессии и зайдите заново (или выполните: newgrp docker)."
echo "============================================================"
