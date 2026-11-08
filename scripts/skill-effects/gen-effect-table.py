#!/usr/bin/env python3
"""Generate Packages/RagnarokEffects/Sources/RagnarokEffects/EffectTable+Reference.swift.

Takes the effect ids and asset names of the roBrowser reference EffectTable.js (as dumped by
extract-reference.js), keeps the STR, SPR and sound-only entries whose assets exist in the
client's data.grf, and skips ids that the hand written EffectTable.swift already defines.
FUNC entries need code and are skipped (they are listed on stderr).

usage: gen-effect-table.py <ref.json> <grf.tsv> <data.grf> <repo-root> > EffectTable+Reference.swift
  ref.json   output of extract-reference.js
  grf.tsv    output of grf-names.py (third argument)
  data.grf   the client archive, used to check that the textures of every STR file exist
"""
import json, re, struct, sys, zlib

ref_path, tsv_path, grf_path, repo = sys.argv[1:5]
ref = json.load(open(ref_path))['effectTable']

# ---- GRF index -------------------------------------------------------------------------------
entries = {}
for line in open(tsv_path):
    name, flags, csize, asize, size, offset = line.rstrip('\n').split('\t')
    entries[name.lower().replace('/', '\\')] = (int(csize), int(offset))
grf = open(grf_path, 'rb')


def exists(path):
    return path.lower() in entries


def read(path):
    csize, offset = entries[path.lower()]
    grf.seek(46 + offset)
    return zlib.decompress(grf.read(csize))


def str_textures(data):
    assert data[:4] == b'STRM', data[:4]
    layers = struct.unpack('<I', data[16:20])[0]
    pos = 36
    names = []
    for _ in range(layers):
        count = struct.unpack('<I', data[pos:pos + 4])[0]
        pos += 4
        for _ in range(count):
            raw = data[pos:pos + 128]
            names.append(raw.split(b'\0')[0].decode('cp949', errors='replace'))
            pos += 128
        anim = struct.unpack('<I', data[pos:pos + 4])[0]
        pos += 4 + anim * 124
    return names


# ---- names -----------------------------------------------------------------------------------
ids = {}
for line in open(f'{repo}/Packages/RagnarokConstants/Sources/RagnarokConstants/Generated/EffectID.swift'):
    m = re.match(r'\s+case (ef_\w+) = (\d+)', line)
    if m:
        ids[int(m.group(2))] = m.group(1)
hand = set(re.findall(r'^        \.(ef_\w+): \[',
                      open(f'{repo}/Packages/RagnarokEffects/Sources/RagnarokEffects/EffectTable.swift').read(), re.M))


def korean(s):
    # the reference file is UTF-8 holding CP949 bytes read as Latin-1
    try:
        return s.encode('latin-1').decode('cp949')
    except (UnicodeEncodeError, UnicodeDecodeError):
        return s


def swift_string(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def swift_file(s):
    return f'K2L({swift_string(s)})' if any(ord(c) > 127 for c in s) else swift_string(s)


def expand(name, rand):
    if '%d' not in name:
        return [name]
    lo, hi = rand if rand else (1, 1)
    return [name.replace('%d', str(i)) for i in range(lo, hi + 1)]


def sound(e):
    w = e.get('wav')
    if not w:
        return None, []
    path = w.replace('/', '\\') + '.wav'
    files = ['data\\wav\\' + p for p in expand(path, e.get('rand'))]
    return path, files


out = []
skipped = []
warnings = []
for key in sorted(ref, key=int):
    n = int(key)
    name = ids.get(n)
    if name is None or name in hand:
        continue
    defs = []
    for e in ref[key]:
        t = e.get('type', 'wav')
        attached = 'true' if e.get('attachedEntity') else 'false'
        snd, snd_files = sound(e)
        missing_sound = any(not exists(f) for f in snd_files)
        rand = e.get('rand')
        rand_s = f'{rand[0]}...{rand[1]}' if rand else None
        if t == 'FUNC':
            skipped.append((n, name, 'FUNC'))
            continue
        if t == 'STR':
            fname = korean(e['file'])
            if fname.startswith('effect/'):
                fname = fname[len('effect/'):]
            files = expand(fname + '.str', rand)
            full = ['data\\texture\\effect\\' + f.replace('/', '\\') for f in files]
            if not all(exists(f) for f in full):
                skipped.append((n, name, 'STR missing: ' + fname))
                continue
            non_ascii = False
            for f in full:
                for tex in str_textures(read(f)):
                    if not exists('data\\texture\\effect\\' + tex):
                        warnings.append(f'{name}: {f} texture {tex!r} not in GRF')
                    if not tex.isascii():
                        non_ascii = True
            if non_ascii:
                # The STR parser in RagnarokFileFormats rejects non-ASCII texture names.
                skipped.append((n, name, 'STR texture name is not ASCII: ' + fname))
                continue
            args = [f'fileName: {swift_file(fname + ".str")}']
            if snd and not missing_sound:
                args.append(f'soundName: {swift_string(snd)}')
            if rand_s:
                args.append(f'randomNumberRange: {rand_s}')
            args.append(f'attachedToTarget: {attached}')
            defs.append('.str(' + ', '.join(args) + ')')
        elif t == 'SPR':
            fname = korean(e['file'])
            base = 'data\\sprite\\이팩트\\' + fname
            if not (exists(base + '.spr') and exists(base + '.act')):
                skipped.append((n, name, 'SPR missing: ' + fname))
                continue
            args = [f'fileName: {swift_file(fname)}']
            if snd and not missing_sound:
                args.append(f'soundName: {swift_string(snd)}')
            if e.get('repeat'):
                args.append('repeats: true')
            if e.get('stopAtEnd'):
                args.append('stopsAtEnd: true')
            args.append(f'attachedToTarget: {attached}')
            if e.get('head'):
                args.append('rendersAtHead: true')
            if e.get('direction'):
                args.append('inheritsDirection: true')
            defs.append('.spr(' + ', '.join(args) + ')')
        else:  # sound only
            if not snd:
                continue
            if missing_sound:
                skipped.append((n, name, 'WAV missing: ' + snd))
                continue
            args = [f'soundName: {swift_string(snd)}']
            if rand_s:
                args.append(f'randomNumberRange: {rand_s}')
            defs.append('.wav(' + ', '.join(args) + ')')
    if defs:
        out.append((n, name, defs))

print('''//
//  EffectTable+Reference.swift
//  RagnarokEffects
//
//  Generated by scripts/skill-effects/gen-effect-table.py. Do not edit by hand.
//

import RagnarokConstants
import RagnarokCore

// Effects the hand written `EffectTable` does not define. Ids and asset names follow the
// roBrowser reference EffectTable.js, filtered to STR, SPR and sound-only entries whose
// assets exist in the kRO client data. `EffectTable.definitions(for:)` looks here after
// its own table, so a hand written entry always wins.
extension EffectTable {
    // Entries are sorted in ascending order by `EffectID.rawValue`.
    static let referenceTable: [EffectID : [EffectDefinition]] = [''')
for n, name, defs in out:
    print(f'        .{name}: [')
    for d in defs:
        print(f'            {d},')
    print('        ],')
print('    ]\n}')

sys.stderr.write(f'{len(out)} effect ids written, {len(skipped)} skipped, {len(warnings)} texture warnings\n')
for s in skipped:
    sys.stderr.write('skipped %d %s: %s\n' % s)
for w in warnings:
    sys.stderr.write('warning: ' + w + '\n')
