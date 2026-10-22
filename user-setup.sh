#!/usr/bin/sh
# usage: ./add-sudo-user.sh <username> [--nopasswd]
set -eu

USER_NAME="${1:?usage: $0 <username> [--nopasswd]}"
NOPASSWD="${2:-}"
[ "$(id -u)" -eq 0 ] || {
	echo "run as root" >&2
	exit 1
}
id "$USER_NAME" >/dev/null 2>&1 || {
	echo "user $USER_NAME does not exist" >&2
	exit 1
}

# Определяем группу sudo по дистрибутиву
if [ -f /etc/debian_version ]; then
	SUDO_GROUP="sudo"
elif [ -f /etc/redhat-release ] || [ -f /etc/fedora-release ]; then
	SUDO_GROUP="wheel"
elif [ "$(uname -s)" = "FreeBSD" ]; then
	SUDO_GROUP="wheel"
else
	# fallback: ищем группу, которой уже разрешён sudo
	SUDO_GROUP=$(awk '/^%[a-zA-Z0-9_-]+[[:space:]]+ALL=/{sub("^%","",$1); print $1; exit}' /etc/sudoers 2>/dev/null || true)
fi
[ -n "${SUDO_GROUP:-}" ] || {
	echo "cannot detect sudo group" >&2
	exit 1
}

# Гарантируем, что группа существует и правило в sudoers есть
getent group "$SUDO_GROUP" >/dev/null 2>&1 || groupadd "$SUDO_GROUP"

if [ "$SUDO_GROUP" = "sudo" ] || [ "$SUDO_GROUP" = "wheel" ]; then
	RULE="%${SUDO_GROUP} ALL=(ALL:ALL) ALL"
	grep -Eq "^%${SUDO_GROUP}[[:space:]]+ALL=" /etc/sudoers /etc/sudoers.d/* 2>/dev/null ||
		echo "$RULE" >"/etc/sudoers.d/10-${SUDO_GROUP}"
	chmod 0440 "/etc/sudoers.d/10-${SUDO_GROUP}" 2>/dev/null || true
	chown root:root "/etc/sudoers.d/10-${SUDO_GROUP}" 2>/dev/null || true
	visudo -cf "/etc/sudoers.d/10-${SUDO_GROUP}" >/dev/null
fi

# Добавляем пользователя в группу
usermod -aG "$SUDO_GROUP" "$USER_NAME"

# Опционально: NOPASSWD через отдельный файл
if [ "$NOPASSWD" = "--nopasswd" ]; then
	F="/etc/sudoers.d/90-${USER_NAME}-nopasswd"
	echo "${USER_NAME} ALL=(ALL:ALL) NOPASSWD: ALL" >"$F"
	chmod 0440 "$F"
	chown root:root "$F"
	visudo -cf "$F" >/dev/null
fi

echo "OK: $USER_NAME -> group $SUDO_GROUP"
sudo -l -U "$USER_NAME"

