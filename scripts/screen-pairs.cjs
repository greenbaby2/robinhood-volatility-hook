// Read-only Dexscreener sample. Search results are not an exhaustive market census.
const fs = require('node:fs');
const queries = ['HOOKR','WETH USDG','USDG','PONS','WTH'];
(async()=>{
  const map = new Map(); const evidence=[];
  for(const q of queries) {
    const url='https://api.dexscreener.com/latest/dex/search?q='+encodeURIComponent(q);
    const r=await fetch(url,{signal:AbortSignal.timeout(20000)});if(!r.ok) throw Error(`${r.status} ${url}`);
    const data=await r.json();evidence.push({query:q,url,data});
    for(const p of data.pairs||[]) if(p.chainId==='robinhood') map.set(p.pairAddress.toLowerCase(),p);
  }
  const pairs=[...map.values()].sort((a,b)=>(b.volume?.h24||0)-(a.volume?.h24||0));
  const snapshot={fetchedAt:new Date().toISOString(),note:'Search-based sample; token authenticity and onchain depth not verified.',evidence,pairs};
  fs.mkdirSync('reports',{recursive:true});fs.writeFileSync('reports/dexscreener-snapshot.json',JSON.stringify(snapshot,null,2));
  console.log(JSON.stringify(pairs.slice(0,18).map(p=>({pair:p.baseToken.symbol+'/'+p.quoteToken.symbol,
    base:p.baseToken.address,quote:p.quoteToken.address,pool:p.pairAddress,dex:p.dexId,version:p.labels,
    liquidity:p.liquidity?.usd,volume24h:p.volume?.h24,volume1h:p.volume?.h1,
    tx24h:p.txns?.h24,change24h:p.priceChange?.h24,url:p.url})),null,2));
})().catch(e=>{console.error(e.message);process.exitCode=1});
