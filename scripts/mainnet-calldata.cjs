// Minimal strict ABI reader for the exact two supported PositionManager plans.
const {keccak_256} = require('js-sha3');
const word = n => BigInt(n).toString(16).padStart(64,'0');
const wallet='0xfe6fac6620c89f7dda96d1b3c34300c75abbe6b8';
const weth='0x0bd7d308f8e1639fab988df18a8011f41eacad73', usdg='0x5fc5360d0400a0fd4f2af552add042d716f1d168';
function at(hex,offset) {
  if(!Number.isSafeInteger(offset)||offset<0||offset*2+64>hex.length) throw Error('Invalid ABI offset');
  return hex.slice(offset*2,offset*2+64);
}
const numberAt=(hex,offset)=>Number(BigInt('0x'+at(hex,offset)));
function bytesAt(hex,offset) {
  const length=numberAt(hex,offset);
  if(!Number.isSafeInteger(length)||length<0||(offset+32+length)*2>hex.length) throw Error('Invalid ABI bytes');
  return hex.slice((offset+32)*2,(offset+32+length)*2);
}
function arrayAt(hex,offset) {
  const count=numberAt(hex,offset); if(count!==2) throw Error('Expected exactly two actions/calls');
  return [0,1].map(i=>bytesAt(hex,offset+32+numberAt(hex,offset+32+i*32)));
}
function callData(data,signature) {
  const hex=data.replace(/^0x/,'').toLowerCase();
  if(!/^[0-9a-f]+$/.test(hex)||hex.length%2 || !hex.startsWith(keccak_256(signature).slice(0,8))) throw Error('Wrong method');
  return hex.slice(8);
}
function validatePositionCall(stage,data,hook) {
  const key=[weth,usdg,0x800000,60,hook].map(word).join('');
  let modify;
  if(stage==='fund') {
    const calls=callData(data,'multicall(bytes[])');
    const [init,mint]=arrayAt(calls,numberAt(calls,0));
    const initial=callData(init,'initializePool((address,address,uint24,int24,address),uint160)');
    if(initial.length!==384||initial.slice(0,320)!==key || BigInt('0x'+at(initial,160))===0n) throw Error('Wrong initialization key/price');
    modify=callData(mint,'modifyLiquidities(bytes,uint256)');
  } else if(stage==='exit') modify=callData(data,'modifyLiquidities(bytes,uint256)');
  else throw Error('Unsupported stage');
  const deadline=numberAt(modify,32);
  const unlock=bytesAt(modify,numberAt(modify,0));
  const actions=bytesAt(unlock,numberAt(unlock,0));
  const args=arrayAt(unlock,numberAt(unlock,32));
  if(stage==='fund') {
    if(actions!=='020d'||args[1]!==word(weth)+word(usdg)) throw Error('Unexpected mint actions');
    if(args[0].slice(0,320)!==key || at(args[0],256)!==word(19000000000000000n) || at(args[0],288)!==word(50000000) || at(args[0],320)!==word(wallet)) throw Error('Wrong mint key, caps or recipient');
    const lower=BigInt.asIntN(24,BigInt('0x'+at(args[0],160))), upper=BigInt.asIntN(24,BigInt('0x'+at(args[0],192)));
    if(upper-lower!==1200n||lower%60n||upper%60n||lower < -887272n||upper>887272n||BigInt('0x'+at(args[0],224))===0n) throw Error('Unexpected range or zero liquidity');
    if(bytesAt(args[0],numberAt(args[0],352))!=='') throw Error('Unexpected hook data');
  } else {
    if(actions!=='0311'||args[1]!==word(weth)+word(usdg)+word(wallet)) throw Error('Unexpected exit actions/recipient');
    if(BigInt('0x'+at(args[0],32))===0n && BigInt('0x'+at(args[0],64))===0n) throw Error('Unbounded exit');
    if(bytesAt(args[0],numberAt(args[0],96))!=='') throw Error('Unexpected hook data');
  }
  return deadline;
}
module.exports={validatePositionCall};
