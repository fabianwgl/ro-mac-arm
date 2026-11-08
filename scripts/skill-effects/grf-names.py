"""Dump the file names of a GRF 0x200 archive, one per line (Windows separators, CP949 decoded).

usage: grf-names.py <data.grf> <out.txt> [<out.tsv>]
The optional tsv gets name, flags, compressed size, aligned size, size, offset, which gen-effect-table.py
uses to read the STR files and check their textures. Only GRF 0x200 archives with zlib entries are supported.
"""
import struct, sys, zlib

path = sys.argv[1]
out = sys.argv[2]
with open(path, 'rb') as f:
    head = f.read(46)
    assert head[:15] == b'Master of Magic', head[:15]
    table_off, seed, count, version = struct.unpack('<IIII', head[30:46])
    if version != 0x200:
        raise SystemExit('unsupported GRF version %x' % version)
    f.seek(46 + table_off)
    comp, uncomp = struct.unpack('<II', f.read(8))
    data = zlib.decompress(f.read(comp))

pos = 0
rows = []
for _ in range(count - seed - 7):
    end = data.index(b'\0', pos)
    name = data[pos:end].decode('cp949', errors='replace')
    pos = end + 1
    csize, asize, size, flags, offset = struct.unpack('<IIIBI', data[pos:pos + 17])
    pos += 17
    rows.append((name, flags, csize, asize, size, offset))

with open(out, 'w') as o:
    for r in rows:
        o.write(r[0] + '\n')
if len(sys.argv) > 3:
    with open(sys.argv[3], 'w') as o:
        for r in rows:
            o.write('\t'.join(str(x) for x in r) + '\n')
print(len(rows), 'entries')
