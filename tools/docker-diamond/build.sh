#!/bin/bash
# Headless Diamond build, runs inside the container.
# Mount points (see run-synth.sh):
#   /work/project  - exp2.ldf + .vhd + .lpf
#   /work/out      - receives .jed/.bit + synthesis/implementation reports
#   /work/license  - license.dat (LM_LICENSE_FILE points here)
set -o pipefail

OUT=/work/out
mkdir -p "$OUT"

echo "== container MAC (must match license HOSTID) =="
cat /sys/class/net/eth0/address 2>/dev/null || true

cd /work/project

echo "== run diamondc (Synthesis/Map/PAR/Bitgen) =="
timeout 3000 diamondc /opt/build.tcl
RC=$?

echo "== generate JEDEC from PAR output =="
export bindir=/opt/lscc/diamond/3.14/bin/lin64
export BALI_USE_FOUNDRY_OUTSIDE=
source "$bindir/diamond_env"
export LD_LIBRARY_PATH=/opt/lscc/diamond/3.14/ispfpga/bin/lin64:$LD_LIBRARY_PATH
cd /work/project/impl1
NCD=$(ls *.ncd 2>/dev/null | head -1)
if [ -n "$NCD" ]; then
  /opt/lscc/diamond/3.14/ispfpga/bin/lin64/bitgen -J w "$NCD" 2>&1 | tail -5
else
  echo "NO NCD FOUND - PAR output missing"
fi

echo "== collect artifacts =="
for f in *.jed *.bit *.ncd *.mrp *.tw1 *.log synthesis.log; do
  [ -f "$f" ] && cp -v "$f" "$OUT/" 2>/dev/null
done

echo "== done (rc=$RC); jed files =="
ls -la "$OUT"/*.jed 2>/dev/null || echo "NO JED PRODUCED - inspect /work/out logs"
exit $RC
