const fs = require('node:fs');
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const root=path.resolve(__dirname,'..');
const pins=JSON.parse(fs.readFileSync(path.join(root,'dependencies.lock.json')));
const git=args=>execFileSync('git',args,{cwd:root,stdio:'inherit'});
for(const [relative,pin] of Object.entries(pins)) {
  const dest=path.resolve(root,relative);
  if(!dest.startsWith(root+path.sep)||!relative.startsWith('lib/')||!/^[0-9a-f]{40}$/.test(pin.commit)||
    !/^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+(?:\.git)?$/.test(pin.repository)) throw Error('Invalid dependency pin');
  if(!fs.existsSync(path.join(dest,'.git'))) {
    fs.mkdirSync(dest,{recursive:true});git(['init',dest]);
    git(['-C',dest,'remote','add','origin',pin.repository]);
    git(['-C',dest,'fetch','--depth','1','origin',pin.commit]);
    git(['-C',dest,'checkout','--detach',pin.commit]);
  }
  const actual=execFileSync('git',['-C',dest,'rev-parse','HEAD'],{encoding:'utf8'}).trim();
  if(actual!==pin.commit) throw Error(`Dependency revision mismatch: ${relative}`);
  console.log(`${relative}: ${actual}`);
}
