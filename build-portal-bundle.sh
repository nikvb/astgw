#!/bin/bash
###############################################################################
# Build the AstGW portal deploy bundle for install-standalone.sh (Phase 9).
#
# Run this on a machine with a modern Node (20.19+/22 — Vite 7 needs it).
# Produces ./portal-bundle.tar.gz containing: build/ + package.json + prod
# node_modules. install-standalone.sh ships that to the first server, where the
# unofficial glibc-217 Node 20 runtime serves it (works on EL7's old glibc).
#
#   bash build-portal-bundle.sh
###############################################################################
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
OUT="$SRC/portal-bundle.tar.gz"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

command -v node >/dev/null || { echo "FATAL: node not found (need 20.19+/22)"; exit 1; }
echo ">> Node $(node -v)"

cd "$SRC"
echo ">> npm install + build (adapter-node)"
npm install --no-audit --no-fund
npm run build                                   # -> build/

echo ">> staging prod deps (no optional/native, so it's portable to the target)"
cp -r build "$STAGE/build"
cp package.json "$STAGE/"
[ -f package-lock.json ] && cp package-lock.json "$STAGE/"
( cd "$STAGE" && npm ci --omit=dev --omit=optional --no-audit --no-fund )

echo ">> packing $OUT"
tar czf "$OUT" -C "$STAGE" build package.json node_modules
ls -lh "$OUT"
echo ">> done. Place portal-bundle.tar.gz next to install-standalone.sh on the first server."
