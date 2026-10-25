#!/usr/bin/env bash
# install-nushell.sh — установка Nushell на различных дистрибутивах Linux
# и добавление пути к nu в /etc/shells
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Запустите скрипт от root или через sudo" >&2
    exit 1
fi

if [[ ! -f /etc/os-release ]]; then
    echo "Не удалось определить дистрибутив (/etc/os-release отсутствует)" >&2
    exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release
DISTRO_ID="${ID:-unknown}"

echo "==> Дистрибутив: ${PRETTY_NAME:-$DISTRO_ID}"

NU_BIN=""

install_ubuntu() {
    if ! command -v snap >/dev/null 2>&1; then
        echo "==> Установка snapd..."
        apt-get update
        apt-get install -y snapd
    fi
    # Ждём инициализации snapd на свежих системах
    snap wait system seed.loaded 2>/dev/null || true
    echo "==> Установка nushell через snap..."
    snap install nushell --classic
    NU_BIN="/snap/bin/nu"
}

install_debian() {
    echo "==> Пробуем установить nushell через apt..."
    apt-get update
    if apt-get install -y nushell; then
        NU_BIN="/usr/bin/nu"
        return
    fi
    echo "==> В репозитории нет nushell, скачиваем .deb с GitHub Releases..."
    local arch deb_arch url tmp
    arch=$(dpkg --print-architecture)
    case "$arch" in
        amd64) deb_arch="amd64" ;;
        arm64) deb_arch="arm64" ;;
        *) echo "Неподдерживаемая архитектура: $arch" >&2; exit 1 ;;
    esac

    url=$(curl -fsSL https://api.github.com/repos/nushell/nushell/releases/latest \
          | grep -oE "https://[^\"]*_${deb_arch}\.deb" | head -n1 || true)
    if [[ -z "$url" ]]; then
        echo "Не удалось найти .deb в последнем релизе" >&2
        exit 1
    fi

    tmp=$(mktemp --suffix=.deb)
    curl -fL -o "$tmp" "$url"
    dpkg -i "$tmp" || apt-get install -y -f
    rm -f "$tmp"
    NU_BIN="/usr/bin/nu"
}

install_arch() {
    echo "==> Установка nushell через pacman..."
    pacman -Sy --noconfirm nushell
    NU_BIN="/usr/bin/nu"
}

install_opensuse() {
    echo "==> Установка nushell через zypper..."
    zypper --non-interactive install nushell
    NU_BIN="/usr/bin/nu"
}

install_fedora() {
    echo "==> Установка nushell через dnf..."
    if ! dnf install -y nushell; then
        echo "==> Пробуем через EPEL..."
        dnf install -y epel-release || true
        dnf install -y nushell
    fi
    NU_BIN="/usr/bin/nu"
}

case "$DISTRO_ID" in
    ubuntu)                     install_ubuntu ;;
    debian)                     install_debian ;;
    arch|manjaro|endeavouros)   install_arch ;;
    opensuse*|suse|sles|sle-micro) install_opensuse ;;
    fedora|rhel|centos|rocky|almalinux) install_fedora ;;
    *)
        echo "Дистрибутив '$DISTRO_ID' не поддерживается этим скриптом" >&2
        exit 1
        ;;
esac

# Проверяем, что бинарник на месте
if [[ ! -x "${NU_BIN:-}" ]]; then
    NU_BIN="$(command -v nu || true)"
fi
if [[ -z "$NU_BIN" || ! -x "$NU_BIN" ]]; then
    echo "Не удалось найти исполняемый файл nu" >&2
    exit 1
fi

echo "==> Nushell установлен: $NU_BIN"

# Добавляем в /etc/shells
touch /etc/shells
if grep -Fxq "$NU_BIN" /etc/shells; then
    echo "==> $NU_BIN уже есть в /etc/shells"
else
    echo "$NU_BIN" >> /etc/shells
    echo "==> Добавлено в /etc/shells: $NU_BIN"
fi

echo "==> Готово!"
echo "Сменить оболочку можно так: chsh -s $NU_BIN"
