// Select and record a recent block: the public RPC is not an archive service.
const fs=require('node:fs');
const path=require('node:path');
const {spawnSync}=require('node:child_process');
(async()=>{
  const rpc=process.env.ROBINHOOD_RPC || 'https://rpc.mainnet.chain.robinhood.com';
  let block=process.env.FORK_BLOCK;
  if(!block) {
    const response=await fetch(rpc,{method:'POST',headers:{'content-type':'application/json'},
      body:JSON.stringify({jsonrpc:'2.0',id:1,method:'eth_blockNumber',params:[]}),signal:AbortSignal.timeout(20000)});
    if(!response.ok) throw Error(`RPC HTTP ${response.status}`);
    const data=await response.json(); if(data.error) throw Error(JSON.stringify(data.error));
    block=(BigInt(data.result)-256n).toString();
  }
  if(!/^[1-9][0-9]*$/.test(block)) throw Error('Invalid FORK_BLOCK');
  const metadata={startedAt:new Date().toISOString(),chainId:4663,block,mode:'local fork, no broadcast',
    balances:'Artificial test balances only; no real wallet funds changed'};
  console.log(JSON.stringify(metadata));
  const forge=process.platform==='win32'?path.resolve('node_modules/@foundry-rs/forge-win32-amd64/bin/forge.exe'):'forge';
  const result=spawnSync(forge,['test','--match-path','test/Mainnet*.t.sol','-vv'],{
    env:{...process.env,RUN_MAINNET_FORK:'true',FORK_BLOCK:block},stdio:'inherit',windowsHide:true});
  if(result.error) throw result.error;
  metadata.passed=result.status===0;
  fs.mkdirSync('reports',{recursive:true});
  fs.writeFileSync('reports/fork-run-metadata.json',JSON.stringify(metadata,null,2)+'\n');
  process.exitCode=result.status ?? 1;
})().catch(e=>{console.error(e.message);process.exitCode=1;});
