#!/usr/bin/env bash
# Generate DEVELOPMENT signing material (RAUC CA + signing cert, sstate GPG key).
# Output goes to ./keys/ which is git-ignored. Production keys live in an HSM /
# GitLab protected File variables and are never generated with this script.
set -euo pipefail
out="${1:-keys}"
mkdir -p "$out"; chmod 700 "$out"

openssl req -x509 -newkey rsa:4096 -nodes -days 3650 \
    -keyout "$out/rauc-ca.key.pem" -out "$out/rauc-ca.cert.pem" \
    -subj "/O=Secure Linux Platform Dev/CN=Secure Linux Dev RAUC CA"
openssl req -newkey rsa:4096 -nodes \
    -keyout "$out/rauc-dev.key.pem" -out "$out/rauc-dev.csr.pem" \
    -subj "/O=Secure Linux Platform Dev/CN=Secure Linux Dev RAUC Signing"
openssl x509 -req -days 730 -in "$out/rauc-dev.csr.pem" \
    -CA "$out/rauc-ca.cert.pem" -CAkey "$out/rauc-ca.key.pem" -CAcreateserial \
    -out "$out/rauc-dev.cert.pem"

gpg --batch --passphrase '' --quick-gen-key "Secure Linux Dev sstate <sstate@example.invalid>" ed25519 sign 1y
gpg --armor --export "sstate@example.invalid" > "$out/sstate-dev.pub.asc"
echo "Dev keys written to $out/ (DO NOT use for production)"
