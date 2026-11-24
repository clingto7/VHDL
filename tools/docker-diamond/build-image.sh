#!/bin/zsh
# Build the Diamond docker image. Needs the Linux rpm dropped into rpm/.
set -uo pipefail
cd "$(dirname "$0")"

if ! ls rpm/*.rpm >/dev/null 2>&1; then
  cat >&2 <<'EOF'
No rpm found in rpm/.
1. Create/sign in to a Lattice account
2. Download "Diamond 3.14 64-bit for Linux"
   https://www.latticesemi.com/en/Products/DesignSoftwareAndIP/FPGAandLDS/LatticeDiamond
3. Drop the file into tools/docker-diamond/rpm/ (keep the original name)
EOF
  exit 1
fi

docker build --platform linux/amd64 -t diamond-mxo2 . && \
  echo "== image ready; next: put license/license.dat, then ./run-synth.sh =="
