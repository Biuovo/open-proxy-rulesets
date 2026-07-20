#!/usr/bin/env bash
set -euo pipefail

curl -fL --retry 5 --retry-delay 5 \
  -o cn-domain.srs \
  https://github.com/SagerNet/sing-geosite/releases/latest/download/geosite-cn.db

curl -fL --retry 5 --retry-delay 5 \
  -o cn-ip.srs \
  https://github.com/SagerNet/sing-geoip/releases/latest/download/geoip-cn.db

sha256sum cn-domain.srs cn-ip.srs > SHA256SUMS
