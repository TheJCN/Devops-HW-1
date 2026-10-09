#!/usr/bin/env bash
set -euo pipefail

APP_NAME="homework-app"
APP_USER="homework"
APP_GROUP="homework"
APP_DIR="/opt/linux-devops-homework"
DATA_DIR="/var/lib/linux-devops-homework"
CONFIG_DIR="/etc/linux-devops-homework"
SERVICE_FILE="/etc/systemd/system/${APP_NAME}.service"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

info() { echo; echo "==> $*"; }
error() { echo; echo "[ОШИБКА] $*" >&2; exit 1; }

if [[ "${EUID}" -ne 0 ]]; then
    error "Скрипт необходимо запускать с правами root:
  sudo ./scripts/setup.sh"
fi

if ! command -v apt-get >/dev/null 2>&1; then
    error "Не найден apt-get.

Эта домашняя работа рассчитана на Debian, Ubuntu
или другую систему с пакетным менеджером APT."
fi

if [[ ! -r /etc/os-release ]]; then
    error "Не удалось определить Linux-дистрибутив (/etc/os-release отсутствует)."
fi
# shellcheck disable=SC1091
source /etc/os-release
info "Обнаружена система: ${PRETTY_NAME:-unknown}"

if [[ "$(ps -p 1 -o comm= | tr -d ' ')" != "systemd" ]]; then
    error "systemd не является PID 1.

Для выполнения задания требуется система, загруженная с systemd.
Если используется WSL2, убедитесь, что systemd включён."
fi

info "Проверяю необходимые пакеты..."
REQUIRED_PACKAGES=(python3 curl iproute2 procps)
PACKAGES_TO_INSTALL=()
for package in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg-query -W -f='${Status}' "${package}" 2>/dev/null | grep -q "ok installed"; then
        PACKAGES_TO_INSTALL+=("${package}")
    fi
done

if (( ${#PACKAGES_TO_INSTALL[@]} > 0 )); then
    info "Устанавливаю необходимые пакеты: ${PACKAGES_TO_INSTALL[*]}"
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${PACKAGES_TO_INSTALL[@]}"
else
    info "Все необходимые пакеты уже установлены."
fi

REQUIRED_COMMANDS=(python3 curl ip ss ps stat systemctl journalctl)
for command_name in "${REQUIRED_COMMANDS[@]}"; do
    command -v "${command_name}" >/dev/null 2>&1 || error "После установки зависимостей команда '${command_name}' недоступна."
done

info "Удаляю предыдущую версию стенда, если она существует..."
systemctl stop "${APP_NAME}.service" 2>/dev/null || true
systemctl disable "${APP_NAME}.service" 2>/dev/null || true
rm -f "${SERVICE_FILE}"
rm -rf "${APP_DIR}" "${CONFIG_DIR}" "${DATA_DIR}"
systemctl daemon-reload
systemctl reset-failed "${APP_NAME}.service" 2>/dev/null || true

info "Подготавливаю системного пользователя ${APP_USER}..."
getent group "${APP_GROUP}" >/dev/null || groupadd --system "${APP_GROUP}"
if ! id "${APP_USER}" >/dev/null 2>&1; then
    useradd --system --gid "${APP_GROUP}" --home-dir "${DATA_DIR}" --no-create-home --shell /usr/sbin/nologin "${APP_USER}"
fi

info "Устанавливаю файлы приложения..."
install -d -m 0755 "${APP_DIR}" "${CONFIG_DIR}"
install -m 0755 "${REPO_DIR}/app/server.py" "${APP_DIR}/server.py"
install -m 0644 "${REPO_DIR}/config/app.conf" "${CONFIG_DIR}/app.conf"

info "Подготавливаю каталог данных..."
install -d -o root -g root -m 0700 "${DATA_DIR}"

info "Устанавливаю systemd unit..."
install -m 0644 "${REPO_DIR}/systemd/${APP_NAME}.service" "${SERVICE_FILE}"
systemctl daemon-reload
systemctl enable "${APP_NAME}.service" >/dev/null 2>&1 || true
# Первая попытка запуска намеренно может завершиться ошибкой.
systemctl start "${APP_NAME}.service" 2>/dev/null || true

cat <<EOF2

============================================================
 Стенд для домашней работы подготовлен
============================================================

Приложение:    ${APP_DIR}
Конфигурация:  ${CONFIG_DIR}/app.conf
Данные:        ${DATA_DIR}
systemd unit:  ${SERVICE_FILE}

Стенд намеренно находится в неисправном состоянии.
Ваша задача — привести его к состоянию, описанному в README.md.
Начните диагностику с состояния сервиса.
EOF2
