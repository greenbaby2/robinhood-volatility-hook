// Export only the two zero-value deployment transactions from a successful dry run.
// This file never sends transactions and cannot export a funding plan.
const fs = require('node:fs');
const crypto = require('node:crypto');
const {keccak_256} = require('js-sha3');
const runPath = 'broadcast/MainnetPilot.s.sol/4663/dry-run/run-latest.json';
const run = JSON.parse(fs.readFileSync(runPath));
const wallet = '0xfe6fac6620c89f7dda96d1b3c34300c75abbe6b8';
if(Date.now()-fs.statSync(runPath).mtimeMs>600000) throw Error('Rerun the deployment simulation first');
if(run.transactions.length!==2) throw Error('Only the deployment stage can be exported here');
const [factory,hook] = run.transactions;
const compiled = JSON.parse(fs.readFileSync('artifacts/PilotHookFactory.sol/PilotHookFactory.json'));
if(factory.transaction.input.toLowerCase()!==compiled.bytecode.object.toLowerCase()) throw Error('Factory bytecode mismatch');
const method = '0x'+keccak_256('deploy(bytes32,address,address,uint16)').slice(0,8);
const data=hook.transaction.input.toLowerCase();
const encodedAddress = a => a.slice(2).padStart(64,'0');
if(data.length!==2+8+64*4 || !data.startsWith(method) ||
  data.slice(74,138)!==encodedAddress('0x8366a39cc670b4001a1121b8f6a443a643e40951') ||
  data.slice(138,202)!==encodedAddress(wallet) || BigInt('0x'+data.slice(202))!==10n) throw Error('Unexpected deployment parameters');
if(factory.transaction.to || hook.transaction.to.toLowerCase()!==factory.contractAddress.toLowerCase()) throw Error('Wrong deployment target');
const transactions = run.transactions.map((item,i)=>{
  const tx=item.transaction;
  if(BigInt(tx.chainId)!==4663n || tx.from.toLowerCase()!==wallet || BigInt(tx.value||0)!==0n) throw Error('Wrong chain, wallet, or value');
  if(i && BigInt(tx.nonce)!==BigInt(factory.transaction.nonce)+1n) throw Error('Nonce gap');
  return {label:i?'Deploy cumulative royalty hook':'Deploy pilot factory',from:wallet,chainId:'0x1237',
    ...(tx.to?{to:tx.to}:{}),data:tx.input,value:'0x0',nonce:tx.nonce,simulatedGas:tx.gas};
});
const result = {schema:1,stage:'deploy',chainId:4663,wallet,createdAt:new Date().toISOString(),
  expiresAt:Math.floor(Date.now()/1000)+1200,transactions,
  transactionHash:crypto.createHash('sha256').update(JSON.stringify(transactions)).digest('hex'),
  note:'Unsigned, real-mainnet deployment plan. No funding. Refresh nonce, fees, simulation, and expiry before wallet signing. Do not load in the testnet signer.'};
fs.mkdirSync('signer-state',{recursive:true});
fs.writeFileSync('signer-state/mainnet-deploy.json',JSON.stringify(result,null,2));
fs.writeFileSync('signer-state/mainnet-manifest.json',JSON.stringify(result,null,2));
console.log('Prepared signer-state/mainnet-deploy.json (ignored by Git); no transaction sent.');
