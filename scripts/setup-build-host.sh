#!/usr/bin/env bash
# =============================================================================
# Secure Linux Platform - build host setup for the Ubuntu VirtualBox VM
#   VM: 4 vCPU, ~9 GB RAM, 180 GB data disk (/dev/sdb), no KVM
#
# What it does (idempotent, safe to re-run):
#   1. Formats + mounts the data disk at /srv/yocto   (only with --format-disk)
#   2. Adds 8 GB swap on the data disk
#   3. Kernel/user limits bitbake needs (inotify, swappiness, open files)
#   4. Host packages, Docker group, kas + kas-container (pipx)
#   5. Directory layout for work tree, caches and cache services
#   6. Writes kas/features/local-vm.yml (4-core / low-RAM build profile)
#   7. Installs GitLab Runner and, if RUNNER_TOKEN is set, registers it
#
# Usage:
#   sudo ./setup-build-host.sh --format-disk /dev/sdb      # first run only
#   sudo ./setup-build-host.sh                             # later runs
#   sudo RUNNER_TOKEN=glrt-xxxx GITLAB_URL=https://gitlab.com ./setup-build-host.sh
# =============================================================================
set -euo pipefail

DATA_MNT=/srv/yocto
SWAP_FILE="${DATA_MNT}/swapfile"
SWAP_SIZE=8G
TARGET_USER="${SUDO_USER:-$USER}"
GITLAB_URL="${GITLAB_URL:-https://gitlab.com}"
RUNNER_TOKEN="${RUNNER_TOKEN:-}"
FORMAT_DISK=""

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARN: %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --format-disk) FORMAT_DISK="${2:?device required, e.g. /dev/sdb}"; shift 2 ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

[[ $EUID -eq 0 ]] || die "run with sudo"
[[ "$TARGET_USER" != "root" ]] || die "run via sudo from your normal user, not as root"

# --- 1. Data disk -------------------------------------------------------------
log "Data disk"
if [[ -n "$FORMAT_DISK" ]]; then
    [[ -b "$FORMAT_DISK" ]] || die "$FORMAT_DISK is not a block device"
    if lsblk -no MOUNTPOINTS "$FORMAT_DISK" | grep -q '/'; then
        die "$FORMAT_DISK is mounted - refusing to format"
    fi
    if blkid "$FORMAT_DISK" >/dev/null 2>&1; then
        warn "$FORMAT_DISK already has a filesystem: $(blkid -o value -s TYPE "$FORMAT_DISK") - not formatting"
    else
        size=$(lsblk -dnbo SIZE "$FORMAT_DISK")
        (( size > 100*1024*1024*1024 )) || die "$FORMAT_DISK is smaller than 100 GB - wrong disk?"
        echo "About to FORMAT $FORMAT_DISK ($(lsblk -dno SIZE "$FORMAT_DISK")). Type YES to continue:"
        read -r answer; [[ "$answer" == "YES" ]] || die "aborted"
        mkfs.ext4 -L yocto -m 1 "$FORMAT_DISK"
    fi
fi
mkdir -p "$DATA_MNT"
if ! grep -q "LABEL=yocto" /etc/fstab; then
    echo "LABEL=yocto ${DATA_MNT} ext4 defaults,noatime 0 2" >> /etc/fstab
fi
mountpoint -q "$DATA_MNT" || mount "$DATA_MNT" || die "could not mount ${DATA_MNT} - run once with --format-disk /dev/sdb"
chown "$TARGET_USER:$TARGET_USER" "$DATA_MNT"
df -h "$DATA_MNT"

# --- 2. Swap --------------------------------------------------------------------
log "Swap (${SWAP_SIZE} on data disk)"
if [[ ! -f "$SWAP_FILE" ]]; then
    fallocate -l "$SWAP_SIZE" "$SWAP_FILE"
    chmod 600 "$SWAP_FILE"
    mkswap "$SWAP_FILE"
fi
swapon --show=NAME | grep -q "$SWAP_FILE" || swapon "$SWAP_FILE"
grep -q "$SWAP_FILE" /etc/fstab || echo "${SWAP_FILE} none swap sw 0 0" >> /etc/fstab
free -h

# --- 3. Kernel and user limits ---------------------------------------------------
log "Kernel limits for bitbake"
cat > /etc/sysctl.d/90-yocto-build.conf <<'EOF'
# bitbake watches many files; default inotify limits are too low
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 1024
# keep build processes in RAM as long as possible
vm.swappiness = 10
EOF
sysctl --system >/dev/null
cat > /etc/security/limits.d/90-yocto-build.conf <<EOF
${TARGET_USER} soft nofile 65536
${TARGET_USER} hard nofile 65536
EOF

# --- 4. Packages, Docker, kas ----------------------------------------------------
log "Host packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq git curl ca-certificates pipx python3-yaml jq zstd \
    shellcheck yamllint qemu-system-x86 >/dev/null

if ! command -v docker >/dev/null; then
    apt-get install -y -qq docker.io docker-compose-v2 >/dev/null
fi
systemctl enable --now docker >/dev/null
if ! id -nG "$TARGET_USER" | grep -qw docker; then
    usermod -aG docker "$TARGET_USER"
    RELOGIN=1
fi

log "kas (pipx, for user ${TARGET_USER})"
sudo -u "$TARGET_USER" -H pipx install --force kas >/dev/null
sudo -u "$TARGET_USER" -H pipx ensurepath >/dev/null
sudo -u "$TARGET_USER" -H bash -lc 'kas --version'

# --- 5. Directory layout -----------------------------------------------------------
log "Directory layout under ${DATA_MNT}"
install -d -o "$TARGET_USER" -g "$TARGET_USER" \
    "${DATA_MNT}/work" \
    "${DATA_MNT}/cache/downloads" \
    "${DATA_MNT}/cache/sstate-cache" \
    "${DATA_MNT}/cache/cve-db" \
    "${DATA_MNT}/services/minio" \
    "${DATA_MNT}/services/hashserv" \
    "${DATA_MNT}/services/prserv"
install -d -o 999 -g 999 "${DATA_MNT}/runner-builds"

# --- 6. Build profile for this VM ---------------------------------------------------
log "kas build profile for 4 vCPU / 9 GB RAM"
cat > "${DATA_MNT}/local-vm.yml" <<'EOF'
# Build profile for the VirtualBox build host (4 vCPU, ~9 GB RAM, no KVM).
# Copy to <repo>/kas/features/local-vm.yml and append to the kas command line.
header:
  version: 18

local_conf_header:
  05-local-vm: |
    # 4 parallel bitbake tasks, 3 compile jobs each: fits ~9 GB RAM + swap
    BB_NUMBER_THREADS = "4"
    PARALLEL_MAKE = "-j 3"
    # DL_DIR / SSTATE_DIR come from the host environment: kas-container
    # mounts them into the container (see "export" lines in the summary)
    # No /dev/kvm in this VM: QEMU falls back to TCG (slower, still correct)
    QEMU_USE_KVM = ""
EOF
chown "$TARGET_USER:$TARGET_USER" "${DATA_MNT}/local-vm.yml"

# --- 7. GitLab Runner ------------------------------------------------------------------
log "GitLab Runner"
if ! command -v gitlab-runner >/dev/null; then
    curl -fsSL -o /usr/local/bin/gitlab-runner \
        "https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64"
    chmod 0755 /usr/local/bin/gitlab-runner
    id gitlab-runner >/dev/null 2>&1 || useradd --comment 'GitLab Runner' --create-home gitlab-runner --shell /bin/bash
    usermod -aG docker gitlab-runner
    gitlab-runner install --user=gitlab-runner --working-directory=/home/gitlab-runner
    gitlab-runner start
fi
gitlab-runner --version | head -1

if [[ -n "$RUNNER_TOKEN" ]]; then
    if grep -q "name = \"vm-yocto-builder\"" /etc/gitlab-runner/config.toml 2>/dev/null; then
        warn "runner vm-yocto-builder already registered - skipping"
    else
        gitlab-runner register --non-interactive \
            --url "$GITLAB_URL" \
            --token "$RUNNER_TOKEN" \
            --name "vm-yocto-builder" \
            --executor docker \
            --docker-image "ghcr.io/siemens/kas/kas:5.0" \
            --docker-volumes "${DATA_MNT}/cache:/cache/yocto:rw" \
            --docker-shm-size 2147483648 \
            --builds-dir "/builds" \
            --docker-volumes "${DATA_MNT}/runner-builds:/builds:rw"
        # One Yocto job at a time on this VM
        sed -i 's/^concurrent = .*/concurrent = 1/' /etc/gitlab-runner/config.toml
        gitlab-runner restart
        log "Runner registered. Tags are set on the runner in GitLab (use: yocto)."
    fi
else
    warn "RUNNER_TOKEN not set - runner installed but not registered (see summary)"
fi

# --- Summary ------------------------------------------------------------------------------
log "Done"
cat <<EOF

  Data disk     : $(df -h "$DATA_MNT" | awk 'NR==2{print $4" free of "$2}') at ${DATA_MNT}
  Memory + swap : $(free -h | awk '/Mem:/{print $2}') RAM, $(free -h | awk '/Swap:/{print $2}') swap
  KVM           : $( [[ -e /dev/kvm ]] && echo available || echo "not available (TCG fallback)")
  Build profile : ${DATA_MNT}/local-vm.yml

Next steps
  1. $( [[ "${RELOGIN:-0}" == 1 ]] && echo "Log out and back in (docker group membership)." || echo "Docker group OK." )
  2. Put the repo on the big disk:
        cd ${DATA_MNT}/work && unzip ~/Downloads/secure-linux-platform.zip
        cp ${DATA_MNT}/local-vm.yml ${DATA_MNT}/work/<repo>/kas/features/
  3. First (cold) build - run overnight and note the time:
        export DL_DIR=${DATA_MNT}/cache/downloads SSTATE_DIR=${DATA_MNT}/cache/sstate-cache
        cd ${DATA_MNT}/work/<repo>
        time kas-container build kas/machines/qemux86-64.yml:kas/features/local-vm.yml
  4. Runner: GitLab project > Settings > CI/CD > Runners > New project runner,
     tags "yocto", then:
        sudo RUNNER_TOKEN=glrt-... ./setup-build-host.sh
EOF
