const fs = require('node:fs');
const path = require('node:path');
const solc = require('solc');
const sources = {};
for (const dir of ['src', 'test', 'script']) {
  if (fs.existsSync(dir)) for (const f of fs.readdirSync(dir, {recursive:true})) {
    const name = `${dir}/${f}`.replaceAll('\\', '/');
    if (f.endsWith('.sol')) sources[name] = {content: fs.readFileSync(name, 'utf8')};
  }
}
const input = {language:'Solidity', sources, settings:{optimizer:{enabled:true,runs:200},
  evmVersion:'cancun', outputSelection:{'*':{'*':['abi','evm.bytecode.object']}}}};
const output = JSON.parse(solc.compile(JSON.stringify(input), {import: p => {
  const mapped = p.replace('@uniswap/v4-core/', 'lib/v4-core/')
    .replace('@openzeppelin/uniswap-hooks/', 'lib/uniswap-hooks/')
    .replace(/^forge-std\//, 'lib/v4-core/lib/forge-std/src/')
    .replace(/^solmate\//, 'lib/v4-core/lib/solmate/');
  try {return {contents:fs.readFileSync(path.resolve(mapped),'utf8')}}
  catch {return {error:`Missing dependency: ${p}`}}
}}));
for (const e of output.errors || []) console.error(e.formattedMessage);
if ((output.errors || []).some(e => e.severity === 'error')) process.exit(1);
fs.mkdirSync('artifacts', {recursive:true});
fs.writeFileSync('artifacts/compiled.json', JSON.stringify(output.contracts, null, 2));
console.log('Compiled successfully with', solc.version());
