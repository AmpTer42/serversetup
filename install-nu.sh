#!/usr/bin/env bash
#
# install-nushell.sh — установка Nushell и добавление в /etc/shells
# Поддерживаемые дистрибутивы: Ubuntu (snapd), Debian (apt),
# Arch Linux (pacman), openSUSE (zypper), Fedora/RHEL (dnf).
#
set -euo pipefail

# Цветной вывод для наглядности
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Определение дистрибутива
# ---------------------------------------------------------------------------
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    DISTRO_ID="${ID,,}"        # приводим к нижнему регистру
    DISTRO_LIKE="${ID_LIKE:-}" # может быть пустым
else
    error "Не удалось определить дистрибутив: отсутствует /etc/os-release"
fi

info "Обнаружен дистрибутив: ${PRETTY_NAME:-$DISTRO_ID}"

# ---------------------------------------------------------------------------
# 2. Функции установки для каждого семейства
# ---------------------------------------------------------------------------

install_ubuntu_snap() {
    info "Установка Nushell через snapd (Ubuntu)…"
    if ! command -v snap &>/dev/null; then
        error "snapd не установлен. Установите snapd и повторите запуск."
    fi
    sudo snap install nushell --classic
}

install_debian_apt() {
    info "Установка Nushell через официальный apt-репозиторий (Debian)…"
    sudo apt-get update -qq
    sudo apt-get install -y -qq curl gnupg

    # Добавляем GPG-ключ и репозиторий Fury
    curl -fsSL https://apt.fury.io/nushell/gpg.key \
        | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/fury-nushell.gpg

    echo "deb https://apt.fury.io/nushell/ /" \
        | sudo tee /etc/apt/sources.list.d/fury.list >/dev/null

    sudo apt-get update -qq
    sudo apt-get install -y -qq nushell
}

install_arch_pacman() {
    info "Установка Nushell через pacman (Arch Linux)…"
    sudo pacman -Sy --noconfirm nushell
}

install_opensuse_zypper() {
    info "Установка Nushell через zypper (openSUSE)…"
    # Пакет nushell доступен в основных репозиториях openSUSE.
    sudo zypper --non-interactive install nushell
}

install_fedora_dnf() {
    info "Установка Nushell через dnf (Fedora/RHEL)…"

    # Добавляем репозиторий Fury для yum/dnf
    sudo tee /etc/yum.repos.d/fury-nushell.repo >/dev/null <<'EOF'
[fury-nushell]
name=Fury Nushell Repo
baseurl=https://yum.fury.io/nushell/
enabled=1
gpgcheck=1
gpgkey=https://yum.fury.io/nushell/gpg.key
EOF

    sudo dnf install -y nushell
}

# ---------------------------------------------------------------------------
# 3. Выбор и запуск установщика
# ---------------------------------------------------------------------------
case "$DISTRO_ID" in
    ubuntu)
        install_ubuntu_snap
        ;;
    debian)
        # В Debian snapd не всегда предустановлен, поэтому используем apt-репозиторий
        install_debian_apt
        ;;
    arch|manjaro|endeavouros)
        install_arch_pacman
        ;;
    opensuse*|suse|sles)
        install_opensuse_zypper
        ;;
    fedora|rhel|centos|rocky|almalinux)
        install_fedora_dnf
        ;;
    *)
        # На случай производных дистрибутивов (ID_LIKE)
        if [[ "$DISTRO_LIKE" == *"debian"* ]]; then
            install_debian_apt
        elif [[ "$DISTRO_LIKE" == *"arch"* ]]; then
            install_arch_pacman
        elif [[ "$DISTRO_LIKE" == *"suse"* ]]; then
            install_opensuse_zypper
        elif [[ "$DISTRO_LIKE" == *"fedora"* || "$DISTRO_LIKE" == *"rhel"* ]]; then
            install_fedora_dnf
        else
            error "Неподдерживаемый дистрибутив: $DISTRO_ID (ID_LIKE=$DISTRO_LIKE). Установите Nushell вручную."
        fi
        ;;
esac

# ---------------------------------------------------------------------------
# 4. Проверка, что nu установлен
# ---------------------------------------------------------------------------
if ! command -v nu &>/dev/null; then
    error "Исполняемый файл 'nu' не найден в PATH после установки. Проверьте установку вручную."
fi

NU_PATH="$(command -v nu)"
info "Nushell установлен: $NU_PATH"
nu --version

# ---------------------------------------------------------------------------
# 5. Добавление в /etc/shells (если ещё не добавлен)
# ---------------------------------------------------------------------------
SHELLS_FILE="/etc/shells"

if [[ ! -f "$SHELLS_FILE" ]]; then
    warn "$SHELLS_FILE не существует. Создаём пустой файл."
    sudo touch "$SHELLS_FILE"
fi

# Проверяем, есть ли уже точное совпадение строки
if grep -Fxq "$NU_PATH" "$SHELLS_FILE"; then
    info "$NU_PATH уже присутствует в $SHELLS_FILE — пропускаем."
else
    info "Добавляем $NU_PATH в $SHELLS_FILE…"
    echo "$NU_PATH" | sudo tee -a "$SHELLS_FILE" >/dev/null
    info "Готово. Теперь можно сменить оболочку командой: chsh -s $NU_PATH"
fi

info "Установка и настройка Nushell завершены успешно."
