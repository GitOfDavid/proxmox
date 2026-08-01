#!/bin/bash
set -euo pipefail

# Configuración
HOSTNAME=$(hostname)
REMOTE_HOST="backupsync@172.16.100.14"
REMOTE_DIR="/mnt/proxmox-node-backups/${HOSTNAME}"
SSH_KEY="/root/.ssh/id_ed25519_backupsync"
LOG="/var/log/backup-host.log"

echo "[$(date '+%F %T')] Iniciando backup del sistema Proxmox..." >> "$LOG"

# Crear directorio remoto
ssh -i "$SSH_KEY" "$REMOTE_HOST" "mkdir -p ${REMOTE_DIR}"

# Sincronizar SOLO el sistema operativo
rsync -aAXH --numeric-ids --delete \
  --exclude={/proc,/sys,/dev,/run,/tmp,/mnt,/media,/lost+found} \
  --exclude=/swapfile \
  --exclude=/var/{tmp,cache,run,log,backups} \
  --exclude=/var/lib/{vz,lxc,pve-cluster} \
  --exclude=/etc/pve/priv \
  --exclude=/root/.cache \  -e "ssh -i ${SSH_KEY}" \
  / \
  "${REMOTE_HOST}:${REMOTE_DIR}" >> "$LOG" 2>&1

# Guardar información crítica para recuperación
{
  echo "=== SISTEMA ==="
  echo "Hostname: $(hostname)"
  echo "Fecha backup: $(date)"
  echo "Kernel: $(uname -a)"
  echo ""
  echo "=== DISCOS ==="
  lsblk -f
  echo ""
  echo "=== PROXMOX ==="
  pveversion -v
  echo ""
  echo "=== REPOSITORIOS ==="
  cat /etc/apt/sources.list
  echo ""
  echo "=== RED ==="
  ip addr show
  echo ""
  echo "=== PARTICIONES ==="
  fdisk -l 2>/dev/null | grep -E "^/dev/"
} | ssh -i "$SSH_KEY" "$REMOTE_HOST" "cat > ${REMOTE_DIR}/system-info.txt"

# Guardar paquetes instalados
dpkg -l | ssh -i "$SSH_KEY" "$REMOTE_HOST" "cat > ${REMOTE_DIR}/packages.txt"
apt-mark showmanual | ssh -i "$SSH_KEY" "$REMOTE_HOST" "cat > ${REMOTE_DIR}/manual-packages.txt"

# Guardar configuración de red
cp /etc/network/interfaces /tmp/interfaces.backup
ssh -i "$SSH_KEY" "$REMOTE_HOST" "cat > ${REMOTE_DIR}/interfaces" < /tmp/interfaces.backup
rm /tmp/interfaces.backup

echo "[$(date '+%F %T')] Backup del sistema completado." >> "$LOG"
