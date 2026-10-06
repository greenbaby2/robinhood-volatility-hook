// Convert an unsigned Foundry dry run into a browser-wallet transaction manifest.
const fs = require('node:fs');
const crypto = require('node:crypto');
const source = 'broadcast/TestnetLifecycle.s.sol/46630/dry-run/run-latest.json';
const run = JSON.parse(fs.readFileSync(source));
const wallet = '0xfe6fac6620c89f7dda96d1b3c34300c75abbe6b8';
const names = ['Deploy isolated PoolManager','Deploy free test token','Deploy hook factory',
  'Deploy mined royalty hook','Deploy owner-only rehearsal router','Initialize test pool',
  'Mint free test tokens','Approve test-token spending','Add temporary liquidity',
  'Buy test tokens','Sell test tokens','Claim test ETH royalty','Claim test-token royalty',
  'Collect LP fees','Remove all liquidity','Revoke token approval'];
if (run.transactions.length !== names.length) throw Error('Unexpected lifecycle transaction count');
const transactions = run.transactions.map((t,i) => {
  const x = t.transaction;
  if (BigInt(x.chainId) !== 46630n || x.from.toLowerCase() !== wallet) throw Error('Wrong wallet or chain');
  if (i && BigInt(x.nonce) !== BigInt(run.transactions[i-1].transaction.nonce) + 1n) throw Error('Nonce gap');
  if (BigInt(x.value || '0x0') > 400000000000000n) throw Error('Unexpected value');
  return {label:names[i],from:wallet, ...(x.to ? {to:x.to} : {}),data:x.input,value:x.value || '0x0',nonce:x.nonce,
    chainId:'0xb626',simulatedGas:x.gas,expectedContract:t.contractAddress};
});
const hash = crypto.createHash('sha256').update(JSON.stringify(transactions)).digest('hex');
const expiresAt = Number(BigInt('0x' + transactions[9].data.slice(-64)));
if (expiresAt < Date.now()/1000) throw Error('Simulation deadline expired; rerun the dry run.');
const manifest = {schema:1,chainId:46630,wallet,createdAt:new Date().toISOString(),transactionHash:hash,
  expiresAt,
  note:'Unsigned testnet rehearsal. Isolated manager; no Hookr listing. Ends with zero LP liquidity.',transactions};
fs.mkdirSync('signing', {recursive:true});
fs.writeFileSync('signing/manifest.json', JSON.stringify(manifest,null,2));
console.log(`Prepared ${transactions.length} unsigned testnet transactions; first nonce ${BigInt(transactions[0].nonce)}; SHA256 ${hash}`);
