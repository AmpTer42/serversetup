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

# ------------------------------------------------------------------
# Проверка: есть ли NVIDIA GPU в системе и видит ли его ОС (драйвер)
# ------------------------------------------------------------------
check_nvidia_gpu() {
    # 1. Железо на PCI-шине (vendor id 10de = NVIDIA)
    if ! lspci -nn 2>/dev/null | grep -qiE '\[10de:'; then
        echo "[check] NVIDIA GPU не найден на PCI-шине" >&2
        return 1
    fi

    # 2. Драйвер установлен?
    if ! command -v nvidia-smi >/dev/null 2>&1; then
        echo "[check] nvidia-smi не найден — драйвер не установлен" >&2
        return 1
    fi

    # 3. Драйвер может общаться с картой?
    if ! nvidia-smi -L >/dev/null 2>&1; then
        echo "[check] nvidia-smi не может связаться с драйвером" >&2
        return 1
    fi

    # 4. Созданы device-узлы
    if ! compgen -G '/dev/nvidia[0-9]*' >/dev/null; then
        echo "[check] Нет устройств /dev/nvidia*" >&2
        return 1
    fi

    echo "[check] NVIDIA GPU обнаружен и доступен:"
    nvidia-smi -L | sed 's/^/    /'
    return 0
}

# ------------------------------------------------------------------
# Установка NVIDIA Container Toolkit
# ------------------------------------------------------------------
install_nvidia_container_toolkit() {

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
}

if check_nvidia_gpu; then
    install_nvidia_container_toolkit
else
    echo "NVIDIA: драйвер или видеокарта не обнаружены"
fi

# -------------------- 5. Запуск Docker ----------------------
echo ">>> Docker: запуск сервиса..."
sudo systemctl enable --now docker

# -------------------- 6. Python ------------------------------
echo ">>> Установка Python..."
sudo apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    python3-setuptools \
    python3-wheel \
    build-essential \
    libssl-dev \
    libffi-dev \
    libsqlite3-dev \
    libreadline-dev \
    zlib1g-dev

# -------------------- Итог --------------------
echo
echo "============================================================"
echo " Готово!"
echo " Tailscale : $(command -v tailscale || echo 'не найден')"
echo " Nushell   : $(command -v nu        || echo 'не найден')"
echo " Docker    : $(docker --version    2>/dev/null || echo 'не найден')"
echo " NVIDIA CT : $(command -v nvidia-ctk || echo 'не найден')"
echo " Python    : $(python3 --version 2>/dev/null || echo 'не найден')"
echo
echo " ВАЖНО: чтобы использовать docker без sudo, выйдите из"
echo " сессии и зайдите заново (или выполните: newgrp docker)."
echo "============================================================"
