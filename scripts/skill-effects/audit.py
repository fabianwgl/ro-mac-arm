#!/usr/bin/env python3
"""Audit which active skills of the enabled 1st and 2nd jobs the client draws, and write docs/port/skill-effects.md.

usage: audit.py --repo <repo-root> --ref <ref.json> --rathena <rathena-root> --baseline-rev <git-rev> [--out <file>]

  ref.json       output of extract-reference.js (roBrowser reference tables, used only to count what is portable)
  --baseline-rev the commit before the skill effect work; its SkillEffectTable.swift and EffectTable.swift give
                 the "before" columns

Everything is derived from data: rAthena `db/re/skill_tree.yml`, `skill_db.yml`, `status.yml`, and the Swift
tables in `Packages/RagnarokEffects`. Nothing is guessed. Re-run it after changing those tables.
"""
import argparse, collections, json, re, subprocess, sys
import yaml

ap = argparse.ArgumentParser()
ap.add_argument('--repo', required=True)
ap.add_argument('--ref', required=True)
ap.add_argument('--rathena', required=True)
ap.add_argument('--baseline-rev', required=True)
ap.add_argument('--out')
args = ap.parse_args()
repo, rathena = args.repo, args.rathena
Loader = getattr(yaml, 'CSafeLoader', yaml.SafeLoader)

JOBS = ['Novice', 'Swordman', 'Mage', 'Archer', 'Acolyte', 'Merchant', 'Thief',
        'Knight', 'Crusader', 'Wizard', 'Sage', 'Hunter', 'Bard', 'Dancer',
        'Priest', 'Monk', 'Blacksmith', 'Alchemist', 'Assassin', 'Rogue']
FX = 'Packages/RagnarokEffects/Sources/RagnarokEffects/'

# ---------- rAthena data ----------
skill_db = yaml.load(open(f'{rathena}/db/re/skill_db.yml'), Loader=Loader)['Body']
skills = {s['Name']: s for s in skill_db}
tree = yaml.load(open(f'{rathena}/db/re/skill_tree.yml'), Loader=Loader)['Body']
tree_by_job = {t['Job']: t for t in tree}
status_db = yaml.load(open(f'{rathena}/db/re/status.yml'), Loader=Loader)['Body']
sc_by_skill = collections.defaultdict(list)
for s in status_db:
    if s.get('DurationLookup'):
        sc_by_skill[s['DurationLookup']].append(s)


def has_cast(s):
    ct = s.get('CastTime')
    if isinstance(ct, list):
        return any(int(e.get('Time', 0)) > 0 for e in ct)
    return bool(ct) and int(ct) > 0


# ---------- Swift tables ----------
def git_show(rev, path):
    return subprocess.run(['git', '-C', repo, 'show', f'{rev}:{path}'], capture_output=True, text=True, check=True).stdout


def parse_effect_tables(texts):
    defs = {}
    cur = None
    for text in texts:
        for line in text.split('\n'):
            m = re.match(r'^        (?:\.(ef_\w+)|"(\w+)"): \[', line)
            if m:
                cur = m.group(1) or m.group(2)
                defs[cur] = []
                continue
            m = re.match(r'^            \.(?:`(2D|3D)`|(cylinder|spr|str|wav))\(', line)
            if cur and m:
                defs[cur].append(m.group(1) or m.group(2))
    return defs


def parse_skill_table(text):
    out = {}
    cur = None
    for line in text.split('\n'):
        m = re.match(r'^        \.(\w+): \.init\(', line)
        if m:
            cur = m.group(1)
            out[cur] = {}
            continue
        if cur:
            m = re.match(r'^            (\w+): \[(.*)\]', line)
            if m:
                refs = re.findall(r'\.id\(\.(\w+)\)|\.name\("(\w+)"\)', m.group(2))
                out[cur][m.group(1)] = [a or b for a, b in refs]
    return out


SLOT = {'beginCastEffects': 'B', 'effects': 'E', 'beforeHitEffects': 'P', 'hitEffects': 'H',
        'successEffects': 'S', 'groundEffects': 'G'}


def read(path):
    return open(f'{repo}/{path}').read()


after = dict(
    effects=parse_effect_tables([read(FX + 'EffectTable.swift'), read(FX + 'EffectTable+Reference.swift')]),
    skills=parse_skill_table(read(FX + 'SkillEffectTable.swift')),
)
before = dict(
    effects=parse_effect_tables([git_show(args.baseline_rev, FX + 'EffectTable.swift')]),
    skills=parse_skill_table(git_show(args.baseline_rev, FX + 'SkillEffectTable.swift')),
)
unit_skills = set(re.findall(r'^        \.\w+: \.(\w+),', read(FX + 'SkillUnitTable.swift'), re.M))


def effect_state(tables, name):
    """Return (state, slots) for the effects a skill plays when it is used or hits.
    Ground effects are not counted: they belong to the ground unit column."""
    slots = tables['skills'].get(name.lower())
    if not slots:
        return 'missing', ''
    states, letters = [], ''
    for slot, refs in slots.items():
        if slot == 'groundEffects' or not refs:
            continue
        letters += SLOT[slot]
        for r in refs:
            d = tables['effects'].get(r)
            if d is None or not d:
                states.append('none')
            elif set(d) - {'wav'}:
                states.append('visual')
            else:
                states.append('sound')
    if 'visual' in states:
        return 'visual', letters
    if 'sound' in states:
        return 'sound', letters
    if states:
        return 'no definition', letters
    return 'missing', ''


def ground_state(tables, name, s):
    """None when the skill leaves no unit with a picture; else shown / missing."""
    unit = s.get('Unit')
    visible_unit = bool(unit) and str(unit.get('Id')).lower() != 'dummyskill'
    if not visible_unit and name.lower() not in unit_skills:
        return None
    slots = tables['skills'].get(name.lower(), {})
    return 'shown' if slots.get('groundEffects') and name.lower() in unit_skills else 'missing'


def status_state(name):
    scs = sc_by_skill.get(name, [])
    if not scs:
        return None, ''
    opts = collections.defaultdict(set)
    for sc in scs:
        for k in ('Opt1', 'Opt2', 'Opt3', 'Options'):
            v = sc.get(k)
            if isinstance(v, dict):
                opts[k].update(v)
            elif v:
                opts[k].add(v)
    hide = bool(opts['Options'] & {'Cloak', 'Hide', 'Invisible'})
    bits = [k for k in ('Opt1', 'Opt2', 'Opt3', 'Options') if opts[k] and not (k == 'Options' and hide and opts[k] <= {'Cloak', 'Hide', 'Invisible'})]
    if hide:
        return 'shown', 'hides the sprite'
    if bits:
        return 'missing', 'option bits ' + '/'.join(sorted(b for b in bits)) + ' (' + ', '.join(sorted(x for b in bits for x in opts[b])) + ')'
    return 'icon', 'icon only'


# ---------- rows ----------
rows = {}
seen = set()
for job in JOBS:
    out = []
    for e in tree_by_job[job].get('Tree', []):
        n = e['Name']
        if e.get('MaxLevel', 1) <= 0 or n in seen:
            continue
        s = skills.get(n)
        if not s or s.get('TargetType', 'Passive') == 'Passive':
            continue
        seen.add(n)
        st_b, sl_b = effect_state(before, n)
        st_a, sl_a = effect_state(after, n)
        sc_state, sc_note = status_state(n)
        out.append(dict(
            name=n, id=s['Id'], desc=s.get('Description', n), target=s.get('TargetType'),
            cast=has_cast(s), eff_before=st_b, eff_after=st_a, slots=sl_a,
            gu_before=ground_state(before, n, s), gu_after=ground_state(after, n, s),
            sc=sc_state, sc_note=sc_note,
        ))
    rows[job] = out

# ---------- totals ----------
def count(rs, pred):
    return sum(1 for r in rs if pred(r))


def totals(rs):
    return dict(
        active=len(rs),
        cast=count(rs, lambda r: r['cast']),
        vb=count(rs, lambda r: r['eff_before'] == 'visual'),
        va=count(rs, lambda r: r['eff_after'] == 'visual'),
        sound=count(rs, lambda r: r['eff_after'] == 'sound'),
        miss=count(rs, lambda r: r['eff_after'] in ('missing', 'no definition')),
        gu=count(rs, lambda r: r['gu_after'] is not None),
        gub=count(rs, lambda r: r['gu_before'] == 'shown'),
        gua=count(rs, lambda r: r['gu_after'] == 'shown'),
        sc=count(rs, lambda r: r['sc'] is not None),
        scv=count(rs, lambda r: r['sc'] == 'shown'),
        sci=count(rs, lambda r: r['sc'] == 'icon'),
        scm=count(rs, lambda r: r['sc'] == 'missing'),
    )


per_job = {j: totals(rows[j]) for j in JOBS}
all_rows = [r for j in JOBS for r in rows[j]]
grand = totals(all_rows)

# Reference coverage, for the "what is portable" statement.
ref = json.load(open(args.ref))
ref_funcs = sum(1 for v in ref['effectTable'].values() if any(e.get('type') == 'FUNC' for e in v))
ref_ids = len(ref['effectTable'])
ref_skills = len(ref['skillEffect'])
tables_after = after['effects']
visible_ids_before = sum(1 for d in before['effects'].values() if set(d) - {'wav'})
visible_ids_after = sum(1 for d in after['effects'].values() if set(d) - {'wav'})
skills_mapped_before = len(before['skills'])
skills_mapped_after = len(after['skills'])


# ---------- markdown ----------
def cell_effect(r):
    st = r['eff_after']
    if st == 'visual':
        return f'yes ({r["slots"]})'
    if st == 'sound':
        return f'sound only ({r["slots"]})'
    if st == 'no definition':
        return f'mapped, no picture ({r["slots"]})'
    return 'missing'


def cell_ground(r):
    if r['gu_after'] is None:
        return '-'
    return 'yes' if r['gu_after'] == 'shown' else 'missing'


def cell_status(r):
    if r['sc'] is None:
        return '-'
    return {'shown': 'yes (' + r['sc_note'] + ')', 'icon': 'icon only', 'missing': 'missing: ' + r['sc_note']}[r['sc']]


L = []
w = L.append
w('# Skill and effect audit (P4-02)')
w('')
w('Generated by `scripts/skill-effects/audit.py` from the rAthena data in `db/re/` and the Swift tables in')
w('`Packages/RagnarokEffects`. Re-run it after changing those tables. "Before" is the tree at `' + args.baseline_rev + '`.')
w('')
w('Scope: the 1st and 2nd jobs `' + '`, `'.join(JOBS) + '`.')
w('`docs/port/server-content.md` lists every job (transcendent, 3rd, expanded) as enabled but nothing says')
w('which are played, so those are not audited. A skill shared by several jobs (`AL_HEAL`, `BD_*`) is counted')
w('once, under the first job above that has it. Passive skills are left out: ' + str(grand['active']) + ' active skills.')
w('')
w('Regenerate (paths are examples; the reference is `roBrowser` in `/Users/fwgl/dev/ro-ios/reference`):')
w('')
w('```sh')
w('node scripts/skill-effects/extract-reference.js <dir>            # writes <dir>/ref.json')
w('python3 scripts/skill-effects/grf-names.py data.grf <dir>/grf.txt <dir>/grf.tsv')
w('python3 scripts/skill-effects/gen-effect-table.py <dir>/ref.json <dir>/grf.tsv data.grf . > Packages/RagnarokEffects/Sources/RagnarokEffects/EffectTable+Reference.swift')
w('python3 scripts/skill-effects/gen-skill-unit-table.py <dir>/ref.json . > Packages/RagnarokEffects/Sources/RagnarokEffects/SkillUnitTable.swift')
w('python3 scripts/skill-effects/audit.py --repo . --ref <dir>/ref.json --rathena ~/dev/rathena --baseline-rev ' + args.baseline_rev + ' --out docs/port/skill-effects.md')
w('```')
w('')
w('## How the client shows a skill today')
w('')
w('Everything below is in `Packages/RagnarokGame/Sources/RagnarokGame/Engine/` (`PlaySession.swift`,')
w('`Scene/MapScene+EventHandler.swift`, `Scene/MapScene+SkillUnit.swift`).')
w('')
w('| Server packet | Handler | What is drawn |')
w('|---|---|---|')
w('| `ZC_USESKILL_ACK` (0x13e, cast start, also for ground skills) | `PlaySession.swift:371` -> `onMapObjectSkillCast` | Cast bar and the cast circle (`ef_beginspell*`, `ef_darkcasting` by element) when the cast time is above zero; then `SkillEffectTable.beginCastEffects`. Works for every skill. The target cell of a ground cast is ignored: the circle is at the caster. |')
w('| `ZC_NOTIFY_SKILL`, `ZC_USE_SKILL` (damage, heals, buffs) | `PlaySession.swift:390,393` -> `onMapObjectSkillPerformed` | Caster action, damage numbers, heal number and sound, then the skill table: before-hit and hit effects only when damage is above zero, `effects` unless the hit is a splash, `successEffects` when the skill succeeded. |')
w('| `ZC_NOTIFY_GROUNDSKILL` (ground skill used) | `PlaySession.swift:396` -> `onGroundSkillCast` | `SkillEffectTable.effects` on the target cell. |')
w('| `ZC_SKILL_ENTRY5` (0x9ca, one per ground unit cell) and `ZC_SKILL_DISAPPEAR` | `PlaySession.swift:401,404` -> `onSkillUnitSpawned` / `onSkillUnitVanished` | Looping `groundEffects` of the unit\'s skill on its cell until the server removes the unit. Added by this change; before it the packets were decoded and dropped. |')
w('| `ZC_NOTIFY_EFFECT`, `ZC_NOTIFY_EFFECT2` (script `specialeffect`) | `PlaySession.swift:597,601` | Level-up effects and any `EffectTable` id. |')
w('| `ZC_MSG_STATE_CHANGE`, `ZC_MSG_STATE_CHANGE3` (buff on or off) | `PlaySession.swift:572,581` | Status icon and timer for the player only (`packet.AID == account.accountID`). No picture, and other players\' buffs are ignored. `ZC_EFST_SET_ENTER` is not handled. |')
w('| `ZC_STATE_CHANGE` (option bits: stone, poison, quicken, cloak) | `PlaySession.swift:561` -> `onMapObjectStateChanged` | Stored on the object. Only `cloak` and `invisible` are used (the sprite is hidden); stone, freeze, stun, poison, curse, the Opt3 auras and the rest are not drawn. |')
w('')
w('Skill id to effect: `SkillEffectTable` (skill -> `beginCast`, `effects`, `beforeHit`, `hit`, `success`, `ground` lists of')
w('effect references), effect id to pictures: `EffectTable` (hand written, 2D / 3D / cylinder / SPR / STR / WAV) and')
w('`EffectTable+Reference` (generated, STR / SPR / WAV), unit id to skill: `SkillUnitTable`. The renderer')
w('handles all six definition kinds, so no effect type is skipped by the engine; what is missing is data.')
w('')
w('## Result per job')
w('')
w('Columns: active skills; skills with a cast time (cast bar and circle shown, all of them); skills with a skill specific')
w('effect picture before and after this change; still missing; ground unit skills (a unit with a picture)')
w('and how many are drawn before and after; skills that start a status, and how many show more than an icon.')
w('')
w('| Job | Active | Cast time | Effect before | Effect after | Missing | Ground unit skills | Drawn before | Drawn after | Status skills | Status drawn |')
w('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|')
for j in JOBS:
    t = per_job[j]
    w(f'| {j} | {t["active"]} | {t["cast"]} | {t["vb"]} | {t["va"]} | {t["miss"]} | {t["gu"]} | {t["gub"]} | {t["gua"]} | {t["sc"]} | {t["scv"]} |')
t = grand
w(f'| **Total** | **{t["active"]}** | **{t["cast"]}** | **{t["vb"]}** | **{t["va"]}** | **{t["miss"]}** | **{t["gu"]}** | **{t["gub"]}** | **{t["gua"]}** | **{t["sc"]}** | **{t["scv"]}** |')
w('')
w(f'Tables: skills mapped {skills_mapped_before} -> {skills_mapped_after}, effect ids with a picture {visible_ids_before} -> {visible_ids_after}.')
w(f'The reference (`roBrowser` `EffectTable.js`) has {ref_ids} effect ids, {ref_funcs} of them written as code (`FUNC`) and')
w(f'not portable as data, and {ref_skills} skill mappings.')
w('')
w('## Gaps, biggest first')
w('')
nomap = grand['miss']
missing_by_job = {j: [r['name'] for r in rows[j] if r['eff_after'] in ('missing', 'no definition')] for j in JOBS}
gu_missing = [r['name'] for r in all_rows if r['gu_after'] == 'missing']
status_bits = [r['name'] for r in all_rows if r['sc'] == 'missing']
w(f'1. **No skill specific effect: {nomap} of {grand["active"]} active skills** (was {grand["active"] - grand["vb"]}).')
w('   Every skill still gets a cast bar, damage numbers and the caster animation; only the picture on the target is')
w("   missing. All of the reference's skill mappings and all of its STR / SPR effects are in now, so the rest needs")
w('   effect ids and assets from outside the reference: `EffectID.swift` has 1127 ids and only ' + str(visible_ids_after) + ' have a picture,')
w('   and `FUNC` effects (below) have to be written by hand. Biggest jobs: ' + ', '.join(f'{j} {len(v)}' for j, v in sorted(missing_by_job.items(), key=lambda kv: -len(kv[1]))[:6]) + '.')
w(f'2. **Status pictures: {grand["sc"]} skills start a status, {grand["scv"]} are drawn** (the Cloak and Hide ones, by hiding the sprite).')
w("   Other players' buffs are not drawn at all: `ZC_MSG_STATE_CHANGE*` is only read for the player (icon and timer), and")
w('   `ZC_EFST_SET_ENTER` (buffs already running when a player comes into view) is not handled. The option bits (stone,')
w('   freeze, stun, poison, curse, Quicken, Overthrust, Energy Coat, Steel Body) arrive in `ZC_STATE_CHANGE` and are stored')
w('   but never rendered. Skills that set option bits: ' + ', '.join(status_bits) + '.')
w(f'3. **Ground units: {len(gu_missing)} of {grand["gu"]} skills still draw nothing.** Fire Wall, Pneuma and Quagmire are drawn now,')
w('   because the reference has a per cell ground picture for exactly those. The other units have an id in `SkillUnitTable`')
w('   and no `groundEffects`, so they stay invisible: ' + ', '.join(gu_missing) + '.')
w('   Warp Portal and Safety Wall are the ones players notice. Sanctuary, Magnus, Safety Wall and Fire Pillar have an STR')
w('   that the reference plays once at the cast; whether it fits one cell was not checked, so it was not used per cell.')
w('4. **Ground cast circle:** `ZC_USESKILL_ACK` carries the target cell of a ground skill; the cast circle is drawn at the')
w('   caster instead of the cell.')
w('5. **Effects written as code in the reference (`FUNC`):** ' + str(ref_funcs) + ' ids are not in the generated table. Hand written')
w('   2D / 3D / cylinder definitions in `EffectTable.swift` cover some (Fire Ball, Fire Bolt, Cold Bolt); the rest need new ones.')
w('')
w('Still missing a skill specific effect, by job:')
w('')
for j in JOBS:
    if missing_by_job[j]:
        w(f'- {j}: ' + ', '.join(missing_by_job[j]))
w('')
w('## What this change fixed')
w('')
w('- `EffectTable+Reference.swift` (generated by `scripts/skill-effects/gen-effect-table.py`): the reference\'s STR, SPR')
w('  and sound-only effects that the hand written table lacked. Each asset was checked in the kRO `data.grf` (STR file,')
w('  every texture it names, SPR and ACT, WAV) and then loaded through the app\'s own `EffectAssetLoader`: all load.')
w('  Skipped: the `FUNC` ids, `ef_item316` (file missing from the client) and `ef_ado_str` (the STR parser rejects its')
w('  non-ASCII texture name).')
w('- `SkillEffectTable`: ' + str(skills_mapped_after - skills_mapped_before) + ' more skills (the reference\'s `SkillEffect.js` plus name-matched Slow Poison, Repair Weapon,')
w('  Envenom, Spell Breaker, Dispell, Magic Rod, the four endow skills, Chain Combo) and a `groundEffects` slot.')
w('- Ground units: `SkillUnitTable` (102 unit ids, each checked against rAthena\'s `e_skill_unit_id` and `skill_db.yml`),')
w('  the two packet cases in `PlaySession` and `MapScene+SkillUnit.swift`.')
w('- Tests (`swift test --package-path Packages/RagnarokEffects`): every skill effect reference resolves to a')
w('  definition, no id is in both tables, well formed file names, the unit table.')
w('')
w('## Per job tables')
w('')
w('Effect letters: B begin cast, E on use or ground cast, P before hit, H hit, S success. "Cast" is `bar` when the skill has a')
w('cast time. Ground unit: `-` when the skill leaves none (or an invisible `Dummyskill` unit).')
w('')
for j in JOBS:
    t = per_job[j]
    w(f'### {j} ({t["active"]} active)')
    w('')
    w('| Skill | Id | Target | Cast | Effect | Ground unit | Status |')
    w('|---|---:|---|---|---|---|---|')
    for r in rows[j]:
        w(f'| {r["name"]} | {r["id"]} | {r["target"]} | {"bar" if r["cast"] else "instant"} | {cell_effect(r)} | {cell_ground(r)} | {cell_status(r)} |')
    w('')

text = '\n'.join(L)
if args.out:
    open(args.out, 'w').write(text)
else:
    print(text)
print(json.dumps(dict(grand=grand, per_job=per_job)), file=sys.stderr)
