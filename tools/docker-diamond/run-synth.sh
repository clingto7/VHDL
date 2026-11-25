#!/bin/zsh
# Host-side wrapper: run one headless Diamond synthesis of exp2 in Docker.
# Prereqs (see README.md):
#   - image built:    ./build-image.sh        (needs rpm/ first)
#   - license file:   license/license.dat     (node-locked to container MAC)
# Output: out/ next to this script, contains .jed + reports.
set -uo pipefail
cd "$(dirname "$0")"

MAC=00:0c:29:d5:14:8e
IMG=diamond-mxo2

if ! docker image inspect "$IMG" >/dev/null 2>&1; then
  echo "image $IMG missing - run ./build-image.sh first" >&2
  exit 1
fi

mkdir -p out license
if [ ! -f license/license.dat ]; then
  echo "WARNING: license/license.dat missing - build will fail at synthesis" >&2
fi

REPO=$(cd "$(dirname "$0")/../.." && pwd)

docker run --rm --platform linux/amd64 \
  --mac-address="$MAC" \
  -v "$(pwd)/exp2.ldf":/work/project/exp2.ldf:ro \
  -v "$(pwd)/Strategy1.sty":/work/project/Strategy1.sty:ro \
  -v "$REPO/code/exp2_pwm_breathing_led/src":/work/project/src:ro \
  -v "$REPO/code/exp2_pwm_breathing_led/constraints":/work/project/constraints:ro \
  -v "$(pwd)/license":/work/license:ro \
  -v "$(pwd)/out":/work/out \
  "$IMG" /opt/build.sh

echo "== artifacts =="
ls -la out/ 2>/dev/null
