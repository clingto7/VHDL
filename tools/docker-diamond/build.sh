#!/bin/bash
# Headless Diamond build, runs inside the container.
# Mount points (see run-synth.sh):
#   /work/project  - exp2.ldf + .vhd + .lpf
#   /work/out      - receives .jed + synthesis/implementation reports
#   /work/license  - license.dat (LM_LICENSE_FILE points here)
set -uo pipefail

OUT=/work/out
mkdir -p "$OUT"

echo "== container MAC (register node-locked license against this) =="
ip link show eth0 | grep -o -E "link/ether [0-9a-f:]{17}"

echo "== diamond install =="
DIA_DIR=$(ls -d /opt/lscc/diamond/*/ | head -1)
echo "DIAMOND_DIR=$DIA_DIR"
ls "$DIA_DIR/bin/lin64/" | grep -E "diamondc|pnmain|synpute|ecd" | head

cd /work/project

# Preferred: diamondc console (headless Tcl). Fallback: GUI binary under Xvfb.
if command -v diamondc >/dev/null 2>&1; then
  echo "== run via diamondc =="
  diamondc /opt/build.tcl
else
  echo "== diamondc not found, falling back to diamond -t under Xvfb =="
  xvfb-run -a "$DIA_DIR/bin/lin64/diamond" -t /opt/build.tcl
fi
RC=$?

echo "== collect artifacts =="
# JED and reports live under impl1/ (impl directory named in exp2.ldf)
for f in impl1/*.jed impl1/*.mrp impl1/*.tw1 impl1/*.log impl1/synthesis.log; do
  [ -f "$f" ] && cp -v "$f" "$OUT/"
done

echo "== done (rc=$RC); jed files =="
ls -la "$OUT"/*.jed 2>/dev/null || echo "NO JED PRODUCED - inspect /work/out logs"
exit $RC
