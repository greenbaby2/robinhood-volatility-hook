// Export a fresh, already-simulated funding or exit stage. Never broadcasts.
const fs = require('node:fs');
const crypto = require('node:crypto');
const {keccak_256} = require('js-sha3');
const {validatePositionCall} = require('./mainnet-calldata.cjs');
const stage = process.argv[2];
if(!['fund','exit'].includes(stage)) throw Error('Specify fund or exit');
const source='broadcast/MainnetPilot.s.sol/4663/dry-run/run-latest.json';
if(Date.now()-fs.statSync(source).mtimeMs>300000) throw Error('Rerun the exact stage simulation first');
const run=JSON.parse(fs.readFileSync(source));
const readback=JSON.parse(fs.readFileSync('reports/mainnet-hook-readback.json'));
if(!readback.runtimeAndImmutableChecksPassed || readback.chainId!==4663 || Date.now()-Date.parse(readback.checkedAt)>3600000) throw Error('Refresh hook verification');
const wallet='0xfe6fac6620c89f7dda96d1b3c34300c75abbe6b8';
const weth='0x0bd7d308f8e1639fab988df18a8011f41eacad73', usdg='0x5fc5360d0400a0fd4f2af552add042d716f1d168';
const permit='0x000000000022d473030f116ddee9f6b43ac78ba3', pm='0x58daec3116aae6d93017baaea7749052e8a04fa7';
const labels=stage==='fund'?['Approve capped WETH to Permit2','Approve capped WETH to PositionManager','Approve capped USDG to Permit2','Approve capped USDG to PositionManager','Initialize and mint pilot LP','Revoke WETH PositionManager allowance','Revoke WETH Permit2 allowance','Revoke USDG PositionManager allowance','Revoke USDG Permit2 allowance']:
  ['Burn LP and withdraw tokens','Revoke WETH PositionManager allowance','Revoke WETH Permit2 allowance','Revoke USDG PositionManager allowance','Revoke USDG Permit2 allowance'];
if(run.transactions.length!==labels.length) throw Error('Wrong stage transaction count');
const targets=stage==='fund'?[weth,permit,usdg,permit,pm,permit,weth,permit,usdg]:[pm,permit,weth,permit,usdg];
const selector=s=>'0x'+keccak_256(s).slice(0,8);
const signatures=stage==='fund'?['approve(address,uint256)','approve(address,address,uint160,uint48)','approve(address,uint256)','approve(address,address,uint160,uint48)','multicall(bytes[])']:
  ['modifyLiquidities(bytes,uint256)'];
signatures.push('approve(address,address,uint160,uint48)','approve(address,uint256)','approve(address,address,uint160,uint48)','approve(address,uint256)');
let deadline;
const txs=run.transactions.map((item,i)=>{
  const tx=item.transaction;
  if(BigInt(tx.chainId)!==4663n || tx.from.toLowerCase()!==wallet || BigInt(tx.value||0)!==0n || tx.to?.toLowerCase()!==targets[i]) throw Error('Unexpected sender, chain, target, or value');
  if(!tx.input.startsWith(selector(signatures[i]))) throw Error('Unexpected action');
  if(i && BigInt(tx.nonce)!==BigInt(run.transactions[i-1].transaction.nonce)+1n) throw Error('Nonce gap');
  const words=tx.input.slice(10).match(/.{64}/g)||[];
  const asAddress=w=>'0x'+w.slice(-40).toLowerCase();
  const revocation=i>=(stage==='fund'?5:1);
  if(signatures[i]==='approve(address,uint256)') {
    const cap=revocation?0n:targets[i]===weth?4000000000000000n:12000000n;
    if(words.length!==2 || asAddress(words[0])!==permit || BigInt('0x'+words[1])!==cap) throw Error('ERC20 approval exceeds policy');
  } else if(signatures[i]==='approve(address,address,uint160,uint48)') {
    const token=asAddress(words[0]);
    const cap=revocation?0n:token===weth?4000000000000000n:12000000n;
    if(words.length!==4 || ![weth,usdg].includes(token) || asAddress(words[1])!==pm || BigInt('0x'+words[2])!==cap) throw Error('Permit2 approval exceeds policy');
    if(!revocation) deadline=Number(BigInt('0x'+words[3]));
  } else {
    const positionDeadline=validatePositionCall(stage,tx.input,readback.hook);
    if(deadline && deadline!==positionDeadline) throw Error('Inconsistent stage deadline');
    deadline=positionDeadline;
  }
  return {label:labels[i],from:wallet,to:tx.to,data:tx.input,value:'0x0',nonce:tx.nonce,chainId:'0x1237',simulatedGas:tx.gas};
});
if(!deadline || deadline<Date.now()/1000+300 || deadline>Date.now()/1000+1500) throw Error('Invalid or stale deadline');
const manifest={schema:1,stage,chainId:4663,wallet,createdAt:new Date().toISOString(),expiresAt:deadline,
  transactionHash:crypto.createHash('sha256').update(JSON.stringify(txs)).digest('hex'),transactions:txs,
  note:'Unsigned mainnet stage from local reviewed script. Review the nested PositionManager calldata before wallet signing.'};
fs.mkdirSync('signer-state',{recursive:true});fs.writeFileSync('signer-state/mainnet-manifest.json',JSON.stringify(manifest,null,2));
console.log(`Prepared ${txs.length} unsigned ${stage} transactions; none sent.`);
