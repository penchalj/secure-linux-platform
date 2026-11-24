# syntax=docker/dockerfile:1.7
# =============================================================================
# Secure Linux build container: kas + Yocto host deps + CI tooling.
# Built in CI with BuildKit registry cache (--cache-to/--cache-from), scanned
# with Trivy, signed with cosign, referenced by digest in .gitlab-ci.yml.
# =============================================================================
# renovate: datasource=docker depName=ghcr.io/siemens/kas/kas
ARG KAS_VERSION=5.0
FROM ghcr.io/siemens/kas/kas:${KAS_VERSION}

ARG COSIGN_VERSION=2.4.1
ARG ORAS_VERSION=1.2.0

USER root
# Fail RUN pipelines on the first failing command (hadolint DL4006)
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Cache apt between builds (BuildKit cache mount, not baked into the layer)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        awscli gnupg rsync jq zstd python3-yaml python3-jsonschema \
        qemu-system-x86 qemu-system-arm iproute2 \
    && rm -rf /var/lib/apt/lists/*

# Pinned CLI tools with checksum verification
COPY docker/checksums.txt /tmp/checksums.txt
WORKDIR /tmp
RUN set -eux; \
    curl -fsSLO "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-amd64"; \
    curl -fsSLO "https://github.com/oras-project/oras/releases/download/v${ORAS_VERSION}/oras_${ORAS_VERSION}_linux_amd64.tar.gz"; \
    grep -E "cosign-linux-amd64|oras_${ORAS_VERSION}" checksums.txt | sha256sum -c -; \
    install -m 0755 cosign-linux-amd64 /usr/local/bin/cosign; \
    tar -xzf "oras_${ORAS_VERSION}_linux_amd64.tar.gz" -C /usr/local/bin oras; \
    rm -f /tmp/*.tar.gz /tmp/cosign-linux-amd64

COPY ci/scripts/ /opt/secure-linux/ci/
RUN chmod 0755 /opt/secure-linux/ci/*.sh

WORKDIR /builder
USER builder
LABEL org.opencontainers.image.title="secure-linux-yocto-builder" \
      org.opencontainers.image.source="${CI_PROJECT_URL}" \
      org.opencontainers.image.licenses="MIT"
