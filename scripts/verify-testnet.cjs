// Read-only post-deployment checks for the supplied testnet rehearsal manifest.
const fs = require('node:fs');
const {keccak256} = require('js-sha3');
const manifest = JSON.parse(fs.readFileSync('signing/manifest.json'));
const rpcURL = 'https://rpc.testnet.chain.robinhood.com';
let block;
async function rpc(method, params=[]) {
  const r = await fetch(rpcURL, {method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({jsonrpc:'2.0',id:1,method,params}),signal:AbortSignal.timeout(20000)});
  if(!r.ok) throw Error(`${method}: HTTP ${r.status}`);
  const j = await r.json();if(j.error) throw Error(JSON.stringify(j.error));return j.result;
}
const word = x => BigInt(x).toString(16).padStart(64,'0');
const selector = signature => keccak256(signature).slice(0,8);
const call = (to, signature, words=[]) => rpc('eth_call',[{to,data:'0x'+selector(signature)+words.join('')},block]);
function normalizedCode(code,refs) {
  let hex=code.replace(/^0x/,'').toLowerCase();
  for(const entries of Object.values(refs||{})) for(const {start,length} of entries)
    hex=hex.slice(0,start*2)+'0'.repeat(length*2)+hex.slice((start+length)*2);
  return hex;
}
(async()=>{
  if(BigInt(await rpc('eth_chainId'))!==46630n) throw Error('Wrong chain');
  // Give rate-limited/load-balanced RPC backends time to agree on the block.
  block='0x'+(BigInt(await rpc('eth_blockNumber'))-128n).toString(16);
  const tx=manifest.transactions;
  const manager=tx[0].expectedContract, token=tx[1].expectedContract, router=tx[4].expectedContract;
  const hook=tx[11].to;
  const report={chainId:46630,block:Number(BigInt(block)),checkedAt:new Date().toISOString(),wallet:manifest.wallet,
    addresses:{manager,token,router,hook},checks:{}};
  for(const [name,address,artifactName] of [['hook',hook,'VolatilityRoyaltyHook'],['router',router,'RehearsalRouter']]) {
    const code=await rpc('eth_getCode',[address,block]);
    report.checks[name+'HasCode']=code!=='0x';
    if(code==='0x') throw Error(`${name} has no deployed code at ${address}`);
    const artifactPath=[`out/${artifactName}.sol/${artifactName}.json`,`artifacts/${artifactName}.sol/${artifactName}.json`].find(fs.existsSync);
    if(!artifactPath) throw Error('Build Foundry artifacts first.');
    const artifact=JSON.parse(fs.readFileSync(artifactPath));
    report.checks[name+'RuntimeMatches']=normalizedCode(code,artifact.deployedBytecode.immutableReferences)===
      normalizedCode(artifact.deployedBytecode.object,artifact.deployedBytecode.immutableReferences);
  }
  report.checks.authorMatches=BigInt(await call(hook,'author()'))===BigInt(manifest.wallet);
  report.checks.managerMatches=BigInt(await call(hook,'poolManager()'))===BigInt(manager);
  report.checks.routerOwnerMatches=BigInt(await call(router,'owner()'))===BigInt(manifest.wallet);
  report.checks.routerManagerMatches=BigInt(await call(router,'manager()'))===BigInt(manager);
  report.checks.royaltyTenBps=BigInt(await call(hook,'royaltyBps()'))===10n;
  report.checks.permissionBits=(BigInt(hook)&0x3fffn)===0x10c4n;
  report.nativeClaimWei=BigInt(await call(manager,'balanceOf(address,uint256)',[word(hook),word(0)])).toString();
  report.tokenClaimRaw=BigInt(await call(manager,'balanceOf(address,uint256)',[word(hook),word(token)])).toString();
  report.routerAllowance=BigInt(await call(token,'allowance(address,address)',[word(manifest.wallet),word(router)])).toString();
  const keyWords=[word(0),word(token),word(0x800000),word(60),word(hook)];
  report.poolId='0x'+keccak256(Buffer.from(keyWords.join(''),'hex'));
  const slot=BigInt('0x'+keccak256(Buffer.from(report.poolId.slice(2)+word(6),'hex')));
  report.poolLiquidity=(BigInt(await call(manager,'extsload(bytes32)',[word((slot+3n)%(1n<<256n))]))&((1n<<128n)-1n)).toString();
  report.checks.claimsCleared=report.nativeClaimWei==='0'&&report.tokenClaimRaw==='0';
  report.checks.approvalRevoked=report.routerAllowance==='0';
  report.checks.liquidityRemoved=report.poolLiquidity==='0';
  report.walletNonce=Number(BigInt(await rpc('eth_getTransactionCount',[manifest.wallet,block])));
  report.walletBalanceTestETH=Number(BigInt(await rpc('eth_getBalance',[manifest.wallet,block])))/1e18;
  report.allChecksPassed=Object.values(report.checks).every(Boolean);
  fs.mkdirSync('reports',{recursive:true});fs.writeFileSync('reports/testnet-readback.json',JSON.stringify(report,null,2));
  console.log(JSON.stringify(report,null,2));
  if(!report.allChecksPassed) process.exitCode=1;
})().catch(e=>{console.error(e.message);process.exitCode=1});
