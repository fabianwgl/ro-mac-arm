// Evaluate the roBrowser AMD modules with stubs and dump plain data as JSON.
const fs = require('fs');
const ref = '/Users/fwgl/dev/ro-ios/reference/roBrowser/src/DB/';
const outDir = process.argv[2];

function run(path, depsFn) {
  const src = fs.readFileSync(ref + path, 'utf8');
  let r;
  const define = (a, b) => { r = (typeof a === 'function' ? a : b)(depsFn); };
  new Function('define', src)(define);
  return r;
}
const SK = run('Skills/SkillConst.js');
const skillEffect = run('Skills/SkillEffect.js', SK);
const skillUnit = run('Skills/SkillUnit.js', SK);
const et = run('Effects/EffectTable.js', () => ({}));

const invSK = {};
for (const k in SK) invSK[SK[k]] = k;
const out = { skillEffect: {}, skillUnit: {}, effectTable: {} };
for (const id in skillEffect) out.skillEffect[invSK[id] || id] = skillEffect[id];
for (const id in skillUnit) out.skillUnit[id] = invSK[skillUnit[id]];
for (const id in et) {
  out.effectTable[id] = et[id].map(e => {
    const o = {};
    for (const k in e) o[k] = typeof e[k] === 'function' ? '<fn>' : e[k];
    return o;
  });
}
fs.writeFileSync(outDir + '/ref.json', JSON.stringify(out, null, 1));
console.log(Object.keys(out.skillEffect).length, Object.keys(out.skillUnit).length, Object.keys(out.effectTable).length);
