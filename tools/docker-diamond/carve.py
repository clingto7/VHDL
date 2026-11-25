import os, sys
src = "/Users/m1zu/ws/VHDL/tools/docker-diamond/installer/3.14.0.75.2_Diamond_lin.run"
outdir = "/Users/m1zu/Documents/tmp/dia_carve"
os.makedirs(outdir, exist_ok=True)
f = open(src, "rb")
total = os.path.getsize(src)
print("total", total)
MAGIC = bytes([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])
hits = []
pos = 0; last = b""
while True:
    chunk = f.read(64 * 1024 * 1024)
    if not chunk: break
    buf = last + chunk
    i = buf.find(MAGIC)
    while i != -1:
        hits.append(pos - len(last) + i)
        i = buf.find(MAGIC, i + 1)
    pos += len(chunk); last = chunk[-16:]
print("hits", len(hits))
for n, h in enumerate(hits):
    end = hits[n+1] if n+1 < len(hits) else total
    f.seek(h)
    remaining = end - h
    outn = os.path.join(outdir, "seg%02d.7z" % n)
    with open(outn, "wb") as o:
        while remaining > 0:
            step = min(remaining, 64*1024*1024)
            o.write(f.read(step))
            remaining -= step
    print("wrote", outn, end - h)
f.close()
