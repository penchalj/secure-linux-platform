#!/usr/bin/env bash
# =============================================================================
# Bring up the shared Yocto cache services and provision Garage (idempotent).
#
#   * renders garage.toml with fresh secrets (first run only)
#   * starts garage, hashserv, prserv on docker network "yocto-cache"
#   * single-node layout, buckets "sstate" + "downloads" (website = read-only)
#   * least-privilege key "ci-publisher" (read+write on both buckets),
#     credentials written to $SLP_SERVICES_DIR/garage/ci-publisher.env (0600)
#   * smoke test from a container on the same network
#
# Usage:  infra/cache/bootstrap-cache.sh            (as your normal user)
# =============================================================================
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
export SLP_SERVICES_DIR="${SLP_SERVICES_DIR:-/srv/yocto/services}"
export SLP_BITBAKE_DIR="${SLP_BITBAKE_DIR:-/srv/yocto/cache/ci/work/bitbake}"
SLP_UID="$(id -u)"; SLP_GID="$(id -g)"
export SLP_UID SLP_GID
GARAGE_CAPACITY="${GARAGE_CAPACITY:-100G}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || die "run as your normal user (not sudo): the services must not run as root"
[[ -x "$SLP_BITBAKE_DIR/bin/bitbake-hashserv" ]] \
  || die "bitbake not found at $SLP_BITBAKE_DIR (run one CI build first, or set SLP_BITBAKE_DIR)"

log "Directories under $SLP_SERVICES_DIR"
mkdir -p "$SLP_SERVICES_DIR"/{garage/meta,garage/data,hashserv,prserv}
chmod 700 "$SLP_SERVICES_DIR/garage"

conf="$SLP_SERVICES_DIR/garage/garage.toml"
if [[ ! -f "$conf" ]]; then
  log "Rendering garage.toml with fresh secrets"
  sed -e "s/__RPC_SECRET__/$(openssl rand -hex 32)/" \
      -e "s/__ADMIN_TOKEN__/$(openssl rand -base64 32 | tr -d '/+=')/" \
      -e "s/__METRICS_TOKEN__/$(openssl rand -base64 32 | tr -d '/+=')/" \
      "$here/garage.toml.template" > "$conf"
  chmod 600 "$conf"
fi

# hashserv access control (v0.3 step 3c): anonymous clients may only READ
# hash equivalences; reporting needs a user with @report (CI on protected main).
# Admin credentials live only here (0600), never in the repo or on a command line.
hsenv="$SLP_SERVICES_DIR/hashserv/hashserv.env"
if [[ ! -f "$hsenv" ]]; then
  log "Creating hashserv.env (anonymous @read, admin user)"
  ( umask 077
    printf '%s\n' "HASHSERVER_ANON_PERMS=@read" \
                   "HASHSERVER_ADMIN_USER=slp-admin" \
                   "HASHSERVER_ADMIN_PASSWORD=$(openssl rand -hex 32)" > "$hsenv" )
fi

log "Starting services"
docker compose -f "$here/docker-compose.yml" up -d
garage() { docker compose -f "$here/docker-compose.yml" exec -T garage /garage "$@"; }

log "Waiting for Garage"
for _ in $(seq 1 30); do garage status >/dev/null 2>&1 && break; sleep 2; done
garage status >/dev/null 2>&1 || die "Garage did not come up: docker compose -f $here/docker-compose.yml logs garage"

log "Cluster layout (single node, $GARAGE_CAPACITY)"
if garage status | grep -q "NO ROLE ASSIGNED"; then
  node_id="$(garage node id -q | cut -d@ -f1)"
  garage layout assign -z dc1 -c "$GARAGE_CAPACITY" "$node_id"
  garage layout apply --version 1
else
  echo "layout already applied"
fi

log "Buckets (website access = anonymous READ-ONLY HTTP on :3902)"
for b in sstate downloads; do
  garage bucket info "$b" >/dev/null 2>&1 || garage bucket create "$b"
  garage bucket website --allow "$b"
done

log "Least-privilege key: ci-publisher"
envf="$SLP_SERVICES_DIR/garage/ci-publisher.env"
if [[ ! -f "$envf" ]]; then
  out="$(garage key create ci-publisher)"
  key_id="$(awk -F': *' '/Key ID/{print $2; exit}' <<<"$out")"
  secret="$(awk -F': *' '/Secret key/{print $2; exit}' <<<"$out")"
  [[ -n "$key_id" && -n "$secret" ]] || { echo "$out"; die "could not parse key output (format changed?)"; }
  umask 077
  printf 'AWS_ACCESS_KEY_ID=%s\nAWS_SECRET_ACCESS_KEY=%s\nAWS_DEFAULT_REGION=garage\nS3_ENDPOINT=http://garage:3900\n' \
    "$key_id" "$secret" > "$envf"
fi
for b in sstate downloads; do
  garage bucket allow --read --write "$b" --key ci-publisher
done

log "Smoke test from a container on network yocto-cache"
docker run --rm --network yocto-cache curlimages/curl:latest -s -o /dev/null \
  -w "garage web (sstate): HTTP %{http_code}\n" http://sstate.web.garage:3902/ || true
docker run --rm --network yocto-cache --entrypoint /bin/sh \
  -v "$SLP_BITBAKE_DIR:/opt/bitbake:ro" ghcr.io/siemens/kas/kas:5.5 -c \
  '/opt/bitbake/bin/bitbake-hashclient --address hashserv:8686 stats && echo "hashserv: OK"' || true
docker run --rm --network yocto-cache busybox nc -z -w 3 prserv 8585 \
  && echo "prserv: port 8585 open" || echo "prserv: NOT reachable"

log "Done"
docker compose -f "$here/docker-compose.yml" ps
cat <<INFO

  S3 write endpoint (CI publish only) : http://garage:3900  (credentials: $envf)
  Read-only sstate mirror             : http://sstate.web.garage:3902
  Read-only download mirror           : http://downloads.web.garage:3902
  Hash equivalence                    : hashserv:8686
  PR server                           : prserv:8585
  Docker network                      : yocto-cache
INFO
