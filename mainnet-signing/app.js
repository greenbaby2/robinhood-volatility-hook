'use strict';
const $ = id => document.getElementById(id);
const EXPECTED = '0xfe6fac6620c89f7dda96d1b3c34300c75abbe6b8';
let manifest, records, storageKey, provider, busy = false;
const report = text => { $('status').textContent = text; };
const rpc = (method,params=[]) => provider.request({method,params});
const persist = () => localStorage.setItem(storageKey,JSON.stringify(records));
function render() {
  $('steps').replaceChildren(...manifest.transactions.map((tx,i) => {
    const li = document.createElement('li');
    const r = records[i]; li.className = r?.confirmed ? 'done' : r?.hash ? 'current' : '';
    li.textContent = `${i+1}. ${tx.label} — ${r?.confirmed ? 'confirmed' : r?.hash ? 'pending' : 'unsigned'}`;
    if (r?.hash) { const a=document.createElement('a');a.href=`https://robinhoodchain.blockscout.com/tx/${r.hash}`;
      a.target='_blank';a.rel='noopener noreferrer';a.textContent=' receipt';li.append(a); }
    return li;
  }));
  $('next').disabled = busy || !provider || records.every(r=>r?.confirmed);
  $('export').disabled = !records.some(r=>r?.hash);
}
async function checkWallet() {
  if (BigInt(await rpc('eth_chainId')) !== 4663n) throw Error('Switch your wallet to Robinhood Chain Mainnet (4663), then reconnect.');
  const accounts=await rpc('eth_accounts');
  if (!accounts.some(a=>a.toLowerCase()===EXPECTED)) throw Error('Connect the specified mainnet wallet.');
}
async function sync() {
  for(let i=0;i<records.length;i++) if(records[i]?.hash) {
    const receipt=await rpc('eth_getTransactionReceipt',[records[i].hash]);
    if(receipt) {
      if(BigInt(receipt.status)!==1n) throw Error(`Transaction ${i+1} reverted. Save receipts and stop; do not restart the plan.`);
      records[i]={...records[i],confirmed:true,receipt};
    } else records[i]={...records[i],confirmed:false};
  }
  persist();render();
}
$('connect').onclick = async () => {
  try {
    const available=window.ethereum?.providers || (window.ethereum ? [window.ethereum] : []);
    if(!available.length) throw Error('Open this page in the browser containing your wallet extension.');
    provider=available[0];
    await rpc('eth_requestAccounts'); await checkWallet(); await sync();
    const balance=BigInt(await rpc('eth_getBalance',[EXPECTED,'latest']));
    report(`Connected. Balance: ${Number(balance)/1e18} ETH. Review each wallet confirmation before signing.`);
    render();
  } catch(e) {provider=null;report(e.message);render();}
};
$('next').onclick = async () => {
  if(busy) return;busy=true;render();
  try {
    await checkWallet();await sync();
    const i=records.findIndex(r=>!r?.confirmed);
    if(i<0) {report('Stage complete. All stage transactions confirmed. Save the receipts.');return;}
    if(records[i]?.hash) {report('The current transaction is pending. Wait, then click again to check its receipt.');return;}
    const tx=manifest.transactions[i];
    if(Date.now()/1000>manifest.expiresAt-300) throw Error('The rehearsal deadline is too close or expired. Stop and regenerate the remaining plan; save receipts first.');
    if(BigInt(await rpc('eth_getTransactionCount',[EXPECTED,'pending']))!==BigInt(tx.nonce))
      throw Error('Wallet nonce changed. Do not send this stale plan. Save receipts and regenerate or reconcile it.');
    const request={from:EXPECTED,...(tx.to?{to:tx.to}:{}),data:tx.data,value:tx.value,nonce:tx.nonce,chainId:'0x1237'};
    const gas=BigInt(await rpc('eth_estimateGas',[request]));
    const price=BigInt(await rpc('eth_gasPrice'));
    const cost=gas*price*2n;
    if(cost>1000000000000000n) throw Error('Estimated gas reserve exceeds 0.001 ETH for this transaction. Stop and review.');
    if(BigInt(await rpc('eth_getBalance',[EXPECTED,'pending']))<cost+BigInt(tx.value)) throw Error('Insufficient ETH for value and gas reserve.');
    report(`Confirm step ${i+1}: ${tx.label}\nEstimated gas cost at current price: ${Number(gas*price)/1e18} ETH.`);
    const hash=await rpc('eth_sendTransaction',[request]);
    if(!/^0x[0-9a-fA-F]{64}$/.test(hash)) throw Error('Wallet returned an invalid transaction hash. Stop and inspect wallet activity.');
    records[i]={hash,confirmed:false};persist();
    report(`Submitted step ${i+1}. Wait for confirmation, then click “Sign next transaction” to continue.`);
    await sync();
  } catch(e) {report(e.message);}
  finally {busy=false;render();}
};
$('export').onclick=()=>{
  const url=URL.createObjectURL(new Blob([JSON.stringify({manifestHash:manifest.transactionHash,chainId:4663,wallet:EXPECTED,records},null,2)],{type:'application/json'}));
  const a=document.createElement('a');a.href=url;a.download='mainnet-receipts.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
};
(async()=>{
  try {
    manifest=await (await fetch('/manifest.json')).json();
    if(manifest.chainId!==4663||manifest.wallet!==EXPECTED||manifest.transactions.length!==({deploy:2,fund:9,exit:5}[manifest.stage] || -1)) throw Error('Invalid mainnet manifest.');
    const bytes=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(JSON.stringify(manifest.transactions)));
    const digest=Array.from(new Uint8Array(bytes),v=>v.toString(16).padStart(2,'0')).join('');
    if(digest!==manifest.transactionHash) throw Error('Transaction checksum mismatch.');
    manifest.transactions.forEach((tx,i)=>{
      if(tx.from!==EXPECTED||BigInt(tx.chainId)!==4663n||BigInt(tx.value)>0n) throw Error('Unsafe transaction metadata.');
      if(i&&BigInt(tx.nonce)!==BigInt(manifest.transactions[i-1].nonce)+1n) throw Error('Nonce gap.');
    });
    storageKey='hook-mainnet-'+digest;
    records=JSON.parse(localStorage.getItem(storageKey)||'null')||Array(manifest.transactions.length).fill(null);
    if(!Array.isArray(records)||records.length!==manifest.transactions.length) throw Error('Invalid saved receipts.');
    $('wallet').textContent=EXPECTED;$('digest').textContent=digest;
    $('connect').disabled=false;render();report('Unsigned mainnet plan loaded. Connect your browser wallet to check network and balance.');
  }catch(e){report(e.message);}
})();
