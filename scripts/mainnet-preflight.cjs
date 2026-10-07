// Read-only RPC preflight. Never requests accounts, signatures, or transactions.
const fs = require('node:fs');
const {keccak_256} = require('js-sha3');
const RPC = process.env.ROBINHOOD_RPC || 'https://rpc.mainnet.chain.robinhood.com';
const addresses = {
  wallet:'0xfe6fac6620c89f7dda96d1b3c34300c75abbe6b8',
  manager:'0x8366a39cc670b4001a1121b8f6a443a643e40951',
  position:'0x58daec3116aae6d93017baaea7749052e8a04fa7',
  router:'0x8876789976decbfcbbbe364623c63652db8c0904',
  permit2:'0x000000000022d473030f116ddee9f6b43ac78ba3',
  weth:'0x0bd7d308f8e1639fab988df18a8011f41eacad73',
  usdg:'0x5fc5360d0400a0fd4f2af552add042d716f1d168',
  reference:'0x52e65b17fb6e5ba00ed806f37afcd2daa50271ca'
};
let id = 0;
async function rpc(method,params) {
  const r = await fetch(RPC,{method:'POST',headers:{'content-type':'application/json'},
    body:JSON.stringify({jsonrpc:'2.0',id:++id,method,params}),signal:AbortSignal.timeout(20000)});
  if (!r.ok) throw Error(`RPC HTTP ${r.status}`);
  const body = await r.json(); if(body.error) throw Error(JSON.stringify(body.error)); return body.result;
}
const word = n => BigInt(n).toString(16).padStart(64,'0');
const selector = s => keccak_256(s).slice(0,8);
(async()=>{
  if(BigInt(await rpc('eth_chainId',[]))!==4663n) throw Error('Wrong chain');
  const block = '0x'+(BigInt(await rpc('eth_blockNumber',[]))-256n).toString(16);
  const call = (to,signature,args='') => rpc('eth_call',[{to,data:'0x'+selector(signature)+args},block]);
  const codes = {};
  for(const [name,address] of Object.entries(addresses)) if(name!=='wallet') {
    const code = await rpc('eth_getCode',[address,block]);
    if(code==='0x') throw Error(`No code: ${name}`);
    codes[name] = '0x'+keccak_256(Buffer.from(code.slice(2),'hex'));
  }
  const addressResult = value => '0x'+value.slice(-40).toLowerCase();
  if(addressResult(await call(addresses.position,'poolManager()'))!==addresses.manager) throw Error('Periphery mismatch');
  if(addressResult(await call(addresses.reference,'token0()'))!==addresses.weth ||
     addressResult(await call(addresses.reference,'token1()'))!==addresses.usdg) throw Error('Reference token order');
  if(BigInt(await call(addresses.weth,'decimals()'))!==18n || BigInt(await call(addresses.usdg,'decimals()'))!==6n) throw Error('Unexpected decimals');
  const eth = BigInt(await rpc('eth_getBalance',[addresses.wallet,block]));
  const weth = BigInt(await call(addresses.weth,'balanceOf(address)',word(addresses.wallet)));
  const usdg = BigInt(await call(addresses.usdg,'balanceOf(address)',word(addresses.wallet)));
  const slot = (await call(addresses.reference,'slot0()')).slice(2);
  const sqrt = BigInt('0x'+slot.slice(0,64));
  const tick = BigInt.asIntN(24,BigInt('0x'+slot.slice(64,128)));
  const price = Number(sqrt * sqrt * 1000000000000n / (1n<<192n));
  const report = {checkedAt:new Date().toISOString(),chainId:4663,block:Number(BigInt(block)),addresses,codeHashes:codes,
    reference:{tick:Number(tick),sqrtPriceX96:sqrt.toString(),approxUSDGPerWETH:price,source:'v3 spot; independent price review required'},
    wallet:{nativeETH:Number(eth)/1e18,weth:Number(weth)/1e18,usdg:Number(usdg)/1e6},
    pilotCaps:{weth:0.019,usdg:50},
    shortfall:{weth:Number(weth<19000000000000000n?19000000000000000n-weth:0n)/1e18,
      usdg:Number(usdg<50000000n?50000000n-usdg:0n)/1e6},
    gasPriceWei:BigInt(await rpc('eth_gasPrice',[])).toString(),
    fundingReady:weth>=19000000000000000n && usdg>=50000000n,
    note:'Read-only balances and contract preflight, not a security audit or transaction approval. Native ETH is separate from WETH. Code hashes describe this block; proxy implementation upgrades need separate review.'};
  fs.mkdirSync('signer-state',{recursive:true});
  fs.writeFileSync('signer-state/mainnet-preflight.json',JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report,null,2));
})().catch(e=>{console.error(e.message);process.exitCode=1;});
