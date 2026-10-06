const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const {webcrypto} = require('node:crypto');
const base = {chainId:4663,stage:'deploy',wallet:'0xfe6fac6620c89f7dda96d1b3c34300c75abbe6b8',transactions:[0,1].map(i=>({label:'Mock deployment '+i,from:'0xfe6fac6620c89f7dda96d1b3c34300c75abbe6b8',chainId:'0x1237',nonce:'0x'+i.toString(16),value:'0x0',data:'0x6000'}))};
base.transactionHash = require('node:crypto').createHash('sha256').update(JSON.stringify(base.transactions)).digest('hex');
// Wallet methods below are mocked; make time-dependent guard tests deterministic.
base.expiresAt = Math.floor(Date.now()/1000) + 3600;
async function setup(options={}) {
  const elements=new Map();
  const element=()=>({textContent:'',disabled:false,children:[],append(x){this.children.push(x)},replaceChildren(...x){this.children=x},click(){}});
  const get=id=>{if(!elements.has(id)) elements.set(id,element());return elements.get(id)};
  let sent=0;
  const provider={request:async({method})=>{
    if(method==='eth_requestAccounts'||method==='eth_accounts') return options.accounts || [base.wallet];
    if(method==='eth_chainId') return options.chain || '0x1237';
    if(method==='eth_getBalance') return '0x2386f26fc10000';
    if(method==='eth_getTransactionCount') return options.nonce || base.transactions[0].nonce;
    if(method==='eth_estimateGas') return '0x100000';
    if(method==='eth_gasPrice') return '0x989680';
    if(method==='eth_sendTransaction') {sent++;return '0x'+'ab'.repeat(32)};
    if(method==='eth_getTransactionReceipt') return {status:'0x1',transactionHash:'0x'+'ab'.repeat(32)};
    throw Error(method);
  }};
  const storage=new Map();
  const context={document:{getElementById:get,createElement:element},window:{ethereum:provider},crypto:webcrypto,
    TextEncoder,Blob,URL,Date,setTimeout,localStorage:{getItem:k=>storage.get(k),setItem:(k,v)=>storage.set(k,v)},
    fetch:async()=>({json:async()=>options.manifest || structuredClone(base)})};
  await vm.runInNewContext(fs.readFileSync('mainnet-signing/app.js','utf8'),context);
  return {get,storage,sent:()=>sent};
}
test('rejects a manifest for another network',async()=>{
  const app=await setup({manifest:{...base,chainId:46630}});
  assert.match(app.get('status').textContent,/Invalid mainnet manifest/);
});
test('rejects modified transaction data',async()=>{
  const changed=structuredClone(base);changed.transactions[0].data+='00';
  const app=await setup({manifest:changed});assert.match(app.get('status').textContent,/checksum mismatch/);
});
test('never sends on testnet',async()=>{
  const app=await setup({chain:'0xb626'});await app.get('connect').onclick();
  assert.match(app.get('status').textContent,/Switch your wallet/);assert.equal(app.sent(),0);
});
test('stale nonce prevents signing',async()=>{
  const app=await setup({nonce:'0x999'});await app.get('connect').onclick();await app.get('next').onclick();
  assert.match(app.get('status').textContent,/nonce changed/);assert.equal(app.sent(),0);
});
test('wrong account cannot connect',async()=>{
  const app=await setup({accounts:['0x0000000000000000000000000000000000000001']});
  await app.get('connect').onclick();assert.match(app.get('status').textContent,/specified mainnet wallet/);assert.equal(app.sent(),0);
});
test('expired plan cannot be signed',async()=>{
  const app=await setup({manifest:{...base,expiresAt:1}});await app.get('connect').onclick();await app.get('next').onclick();
  assert.match(app.get('status').textContent,/deadline/);assert.equal(app.sent(),0);
});
test('one click sends one transaction and records a receipt',async()=>{
  const app=await setup();await app.get('connect').onclick();await app.get('next').onclick();
  assert.equal(app.sent(),1);
  const records=JSON.parse([...app.storage.values()][0]);assert.equal(records[0].confirmed,true);
});
test('unknown stage stays disabled',async()=>{
  const app=await setup({manifest:{...base,stage:'anything'}});
  assert.match(app.get('status').textContent,/Invalid mainnet manifest/);assert.equal(app.sent(),0);
});
test('nonzero ETH transfer is rejected even with a valid checksum',async()=>{
  const changed=structuredClone(base);changed.transactions[0].value='0x1';
  changed.transactionHash=require('node:crypto').createHash('sha256').update(JSON.stringify(changed.transactions)).digest('hex');
  const app=await setup({manifest:changed});assert.match(app.get('status').textContent,/Unsafe transaction metadata/);assert.equal(app.sent(),0);
});
