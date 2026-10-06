# WETH/USDG pilot handoff

Engineering rehearsal complete; no real deployment, swap, approval or deposit has been sent. This is an unaudited technical pilot, not an established income strategy. Original testnet evidence belongs to VolatilityRoyaltyHook. The new CumulativeVolatilityHook has a different address/bytecode and has only been deployed inside local forks.

## Amounts and current status

The first deposit is capped at **0.004 WETH plus 12 USDG**, approximately 22.80 USDG of combined value at the sampled WETH price. This is well below the user's under-$250 liquidity budget. Keep native ETH separately for gas; native ETH does not satisfy a WETH balance check. No asset purchase or wrapping has been performed.

Run the read-only preflight to check current balances and shortfalls locally. Its financial report is saved under the Git-ignored `signer-state` directory. Existing ETH may cover asset acquisition; determine this from fresh local balances and quotes. Do not send money to the hook address. Assets remain in your wallet until the PositionManager pulls the exact approved amounts while minting your LP NFT.

The revised factory + hook dry run estimated 4,293,817 gas at 0.040204001 gwei: **0.000172628622961817 ETH**, around 0.47 USDG at the sampled price. This excludes asset acquisition, approvals, pool initialization, minting, withdrawal, and revocations. Reserve additional native ETH and obtain fresh per-transaction estimates. A 0.001 ETH operating reserve is a planning allowance, not a quoted total cost or maximum fee guarantee.

## What changed

The original hook only retained the largest individual move, so fragments could avoid its surge response. The pilot accumulates absolute tick travel, capped at 455 ticks, with fixed decay of 8 ticks per second. Repeated trades at the same timestamp accumulate. Zero-movement trades do not prolong decay; idle signal clears within 57 seconds. Both unit and real-router fork tests cover this behavior.

This is still an endogenous, reactive activity fee. It cannot price the first externally adverse trade; slow trading can allow decay, and back-and-forth trades can raise fees. It is not a volatility oracle, MEV searcher or LVR hedge. LP fees remain 0.15%–1%, plus a 0.10% output royalty. Those fees may make your pool uncompetitive. No organic volume, frontend routing, Hookr acceptance, or net profit is established.

## Verified infrastructure

Addresses are in `src/mainnet/PilotActions.sol`; local verification is in `signer-state/mainnet-preflight.json`. Sources: [official Uniswap deployments](https://developers.uniswap.org/docs/protocols/v4/deployments) and [Robinhood tokens](https://docs.robinhood.com/chain/contracts/).

- Chain 4663; the original wallet is the hook author and LP NFT recipient.
- Existing canonical PoolManager and PositionManager; no custom custody router.
- Existing Universal Router at 0x8876789976decbfcbbbe364623c63652db8c0904. The fork verified its ABI includes minHopPriceX36; older example encodings revert.
- WETH has 18 decimals; USDG has 6. Initial raw sqrt price is read from the existing WETH/USDG v3 reference with matching token order, so no hand-entered decimal conversion is used.
- ERC20 approvals to Permit2 and Permit2 approvals to PositionManager are capped. Deposit-stage Permit2 approval expires after 20 minutes. Both approval layers are revoked after minting.

## Evidence and repeatable checks

The initial fork evidence used Robinhood block 81389284. The repeat runner selects and records a recent block because the public RPC prunes historical state; an exact older-block rerun requires an archive RPC or a complete existing local cache. It uses real deployed token/periphery code and storage. Wallet token balances are **artificially seeded only inside tests**, and no transaction is broadcast. Tests cover:

- Exact deployment, funding and exit scripts, NFT ownership and approval revocation.
- Atomic initialize + fixed-liquidity mint through the official PositionManager.
- Both swap directions through the official Universal Router and royalty redemption in both tokens.
- Full burn/withdrawal, rejected unauthorized burns, impossible minimum amounts, deadlines and expired Permit2 allowances.
- Split-trade signal accumulation through the actual router.

```powershell
npm.cmd ci --ignore-scripts
npm.cmd run bootstrap
& '.\node_modules\@foundry-rs\forge-win32-amd64\bin\forge.exe' test --summary
node scripts/run-mainnet-fork.cjs
node scripts/mainnet-preflight.cjs
```

Ordinary CI skips the network-dependent tests and marks them skipped. The separate Mainnet fork rehearsal workflow can be manually dispatched. A passing fork demonstrates this sampled path, not all token upgrades, market conditions or adversarial behavior. The WETH/USDG tokens are proxies; checking their proxy bytecode alone does not pin their implementations.

## Funding sequence (wallet signatures are a later step)

1. Recheck the wallet, network, balances, current fees, and token addresses. Decide whether to proceed with this small experimental position. Acquire **at most the pilot amounts** in the same mainnet wallet through a verified swap/wrap route, leaving native ETH for gas. Asset acquisition is separate and has not been scripted or authorized for execution.
2. Prepare the two deployment transactions with the dry run below. Refresh if the wallet nonce changes. A local unsigned export can be produced with `node scripts/prepare-mainnet-deployment.cjs`; it is deliberately excluded from Git. **Do not use the testnet signing page for this mainnet plan.** The separate mainnet signer starts with `node scripts/mainnet-signing-server.cjs` at http://127.0.0.1:8766. It requires the correct wallet/network, validates the manifest checksum, checks nonce/expiry and estimates gas before each wallet signature. It never signs automatically or receives private keys. Browser-provider behavior is covered by mocked tests; no real mainnet signature has been requested.
3. After deployment signatures and confirmed receipts, verify the actual hook with `node scripts/verify-mainnet-hook.cjs ACTUAL_HOOK_ADDRESS`. The script compares local runtime, all repeated immutable values and getters, and produces `reports/mainnet-hook-readback.json`. A predicted dry-run address is not proof of deployment.
4. Independently compare the fresh v3 reference price against an external WETH/USDG market quote. Supply `REVIEWED_REFERENCE_TICK` only after review; the funding script rejects movement over 10 ticks during simulation. Choose the position range consciously: default +/-600 ticks is about +/-6% around the rounded center. Outside the range you stop earning active LP fees and may hold mostly one asset.
5. Set `PILOT_HOOK` and `PILOT_CODEHASH` from verified readback and run the funding dry run. The script rejects an already initialized pool in its simulated starting state. It mints a fixed liquidity amount with both input maxima capped and 0.5% input headroom. Initialization and minting are atomic in one multicall. The deadline is 20 minutes. Regenerate stale plans, do not increase limits to force a failing mint through.
6. Export the fresh successful funding dry run with `node scripts/prepare-mainnet-stage.cjs fund`. Review every transaction, then sign the funded plan only when ready. The plan has nine transactions: two ERC20 approvals, two Permit2 approvals, atomic initialize/mint, and four revocations. If interrupted after mint, preserve receipts and complete revocations separately; do not replay the whole deposit. Obtain your actual tokenId from the PositionManager ERC721 Transfer event (not a previously predicted nextTokenId).
7. Verify NFT owner, pool key, ticks, liquidity, token debits and zero residual allowances. A tiny manual swap can verify operation but is self-funded trading, not revenue evidence. Hookr submission and any frontend routing are separate from deployment.

Dry-run deployment, with no broadcast flag:

```powershell
& '.\node_modules\@foundry-rs\forge-win32-amd64\bin\forge.exe' script script/MainnetPilot.s.sol:DeployMainnetPilot --rpc-url https://rpc.mainnet.chain.robinhood.com --sender 0xfE6Fac6620c89f7DDa96d1B3c34300C75aBBe6b8
node scripts/prepare-mainnet-deployment.cjs
```

After actual verified deployment and asset acquisition, set the reviewed public parameters above, then simulate `script/MainnetPilot.s.sol:FundMainnetPilot` with the same RPC and sender arguments. Simulation refuses an undeployed hook or insufficient asset balances. No fake balances are used in live preparation scripts.

## Exit prepared before entry

`ExitMainnetPilot` checks the wallet owns the NFT and that its full PoolKey matches the verified pilot. It burns the position and takes both tokens directly to the wallet, then revokes approvals. No swap to ETH is bundled with withdrawal.

Use the actual `PILOT_TOKEN_ID` and fresh `EXIT_MIN_WETH` / `EXIT_MIN_USDG` quotes in raw units. At least one minimum must be nonzero; a legitimately one-sided position may have a zero minimum for the absent asset. The tiny minimums in fork tests are test fixtures, not production recommendations. Quote current redeemable amounts with a chosen slippage tolerance and simulate the exact exit before signing. Export it with `node scripts/prepare-mainnet-stage.cjs exit`; the separate mainnet signer accepts this five-transaction stage. The deadline is 20 minutes. Hook author claims are separate from LP fees; redeem accrued WETH/USDG using the hook's `claim` function after reading actual claim balances.

Readiness means the engineering path has been rehearsed and the next step is an informed funding/signing decision. It is not an audit, an investment recommendation, or a claim that this new pool will attract traders.
