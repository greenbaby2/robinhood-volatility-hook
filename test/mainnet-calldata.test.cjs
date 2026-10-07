const {test}=require('node:test');
const assert=require('node:assert/strict');
const {keccak_256}=require('js-sha3');
const {validatePositionCall}=require('../scripts/mainnet-calldata.cjs');
const word=n=>BigInt.asUintN(256,BigInt(n)).toString(16).padStart(64,'0');
const bytes=hex=>word(hex.length/2)+hex.padEnd(Math.ceil(hex.length/64)*64,'0');
const array=items=>word(items.length)+items.map((_,i)=>word(items.length*32+items.slice(0,i).reduce((n,x)=>n+bytes(x).length/2,0))).join('')+items.map(bytes).join('');
const call=(sig,args)=>keccak_256(sig).slice(0,8)+args;
const wallet='0xfe6fac6620c89f7dda96d1b3c34300c75abbe6b8';
const weth='0x0bd7d308f8e1639fab988df18a8011f41eacad73',usdg='0x5fc5360d0400a0fd4f2af552add042d716f1d168';
const hook='0x00000000000000000000000000000000000010c4';
function fixture({cap=19000000000000000n,recipient=wallet,otherHook=hook,actions='020d',stage='fund'}={}) {
  const key=[weth,usdg,0x800000,60,otherHook].map(word).join('');
  const params=stage==='fund'?[key+[-197940,-196740,123,cap,50000000,recipient,384,0].map(word).join(''),word(weth)+word(usdg)]:
    [[100,1,1,128,0].map(word).join(''),[weth,usdg,recipient].map(word).join('')];
  const actionsEncoded=bytes(stage==='fund'?actions:'0311');
  const unlock=word(64)+word(64+actionsEncoded.length/2)+actionsEncoded+array(params);
  const modify=call('modifyLiquidities(bytes,uint256)',word(64)+word(2000000000)+bytes(unlock));
  if(stage==='exit') return '0x'+modify;
  const init=call('initializePool((address,address,uint24,int24,address),uint160)',key+word(12345));
  return '0x'+call('multicall(bytes[])',word(32)+array([init,modify]));
}
test('accepts bounded pilot mint encoding',()=>assert.equal(validatePositionCall('fund',fixture(),hook),2000000000));
test('accepts quoted exit encoding',()=>assert.equal(validatePositionCall('exit',fixture({stage:'exit'}),hook),2000000000));
test('rejects excessive mint approval cap',()=>assert.throws(()=>validatePositionCall('fund',fixture({cap:19000000000000001n}),hook),/caps/));
test('rejects another recipient',()=>assert.throws(()=>validatePositionCall('fund',fixture({recipient:'0x1234'}),hook),/recipient/));
test('rejects a different hook',()=>assert.throws(()=>validatePositionCall('fund',fixture({otherHook:'0x1234'}),hook),/key/));
test('rejects substituted actions',()=>assert.throws(()=>validatePositionCall('fund',fixture({actions:'050d'}),hook),/actions/));
test('rejects malformed ABI offsets',()=>assert.throws(()=>validatePositionCall('fund','0x'+call('multicall(bytes[])',word(999999)),hook),/offset/));
