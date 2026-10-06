// Verify deployed pilot bytecode and immutable values before funding. Read-only.
const fs = require('node:fs');
const {keccak_256: hash} = require('js-sha3');
const hook = (process.argv[2] || '').toLowerCase();
const manager='0x8366a39cc670b4001a1121b8f6a443a643e40951';
const wallet='0xfe6fac6620c89f7dda96d1b3c34300c75abbe6b8';
const rpcURL=process.env.ROBINHOOD_RPC || 'https://rpc.mainnet.chain.robinhood.com';
async function rpc(method,params=[]) {
  const response=await fetch(rpcURL,{method:'POST',headers:{'content-type':'application/json'},
    body:JSON.stringify({jsonrpc:'2.0',id:1,method,params}),signal:AbortSignal.timeout(20000)});
  if(!response.ok) throw Error(`RPC HTTP ${response.status}`);
  const data=await response.json(); if(data.error) throw Error(JSON.stringify(data.error)); return data.result;
}
(async()=>{
  if(!/^0x[0-9a-f]{40}$/.test(hook) || (BigInt(hook)&0x3fffn)!==0x10c4n) throw Error('Provide the deployed pilot hook address');
  if(BigInt(await rpc('eth_chainId'))!==4663n) throw Error('Wrong chain');
  const block='0x'+(BigInt(await rpc('eth_blockNumber'))-256n).toString(16);
  const code=await rpc('eth_getCode',[hook,block]); if(code==='0x') throw Error('No deployed code yet');
  const artifact=JSON.parse(fs.readFileSync('artifacts/CumulativeVolatilityHook.sol/CumulativeVolatilityHook.json'));
  const actual=Buffer.from(code.slice(2),'hex');
  const expected=Buffer.from(artifact.deployedBytecode.object.replace(/^0x/,''),'hex');
  if(actual.length!==expected.length) throw Error('Runtime length differs');
  const allowed=new Set([BigInt(manager).toString(),BigInt(wallet).toString(),'10']);
  const seen=new Set();
  for(const entries of Object.values(artifact.deployedBytecode.immutableReferences)) {
    let first;
    for(const {start,length} of entries) {
      const value=BigInt('0x'+actual.subarray(start,start+length).toString('hex')).toString();
      if(!allowed.has(value) || (first && value!==first)) throw Error('Inconsistent immutable configuration');
      first=value; seen.add(value); actual.fill(0,start,start+length); expected.fill(0,start,start+length);
    }
  }
  if(seen.size!==3 || !actual.equals(expected)) throw Error('Runtime does not match local build');
  const checks={'author()':BigInt(wallet),'poolManager()':BigInt(manager),'royaltyBps()':10n,
    'MAX_SIGNAL()':455n,'DECAY_TICKS_PER_SECOND()':8n,'BASE_FEE()':1500n,'MAX_FEE()':10000n};
  for(const [signature,value] of Object.entries(checks)) {
    const result=await rpc('eth_call',[{to:hook,data:'0x'+hash(signature).slice(0,8)},block]);
    if(BigInt(result)!==value) throw Error(`Configuration mismatch: ${signature}`);
  }
  const report={chainId:4663,block:Number(BigInt(block)),checkedAt:new Date().toISOString(),hook,
    codeHash:'0x'+hash(Buffer.from(code.slice(2),'hex')),runtimeAndImmutableChecksPassed:true,
    note:'Source/runtime identity verification only; no independent security audit or profit forecast.'};
  fs.writeFileSync('reports/mainnet-hook-readback.json',JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report,null,2));
})().catch(e=>{console.error(e.message);process.exitCode=1;});
