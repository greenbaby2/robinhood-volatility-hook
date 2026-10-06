# Robinhood Chain volatility hook research

This project evaluates Gemini's dynamic-fee and developer-royalty proposal. It includes real PoolManager integration tests and a completed wallet-signed testnet lifecycle rehearsal, with live state recorded in `reports/testnet-readback.json`. It is not an audited strategy or a guarantee of yield. See `HOOKR_SUBMISSION.md` for the publication draft and remaining source-publication requirements.

Start with [the testnet setup and costs](TESTNET.md). Read [the mainnet feasibility assessment](MAINNET_ASSESSMENT.md) before considering real capital. The broader strategy is in [the review and deployment roadmap](ROADMAP.md).

## Prototype behavior

`src/VolatilityRoyaltyHook.sol` serves dynamic-fee pools and exact-input swaps only. LP fees start at 0.15% and cap at 1%. After a swap, it replaces the signal only if that swap's tick movement exceeds the decayed prior signal. The next swap pays a fee based on that signal. Linear decay expires 60 seconds after the signal's anchor; dust observations do not reset the anchor. Parameters are research choices, not calibrated trading recommendations.

The optional immutable royalty ranges from 0 to 25 basis points of actual output. At 10 bps, 1,000 output tokens produces a claim on 1 token for the author and 999 for the trader. Fees accrue as PoolManager ERC-6909 claims owned by the hook, in the output currency. Only the immutable author can redeem them, to a chosen nonzero recipient, through `claim(currency, recipient, amount)`. Native ETH claims use currency address zero. A failed redemption rolls back without blocking swaps. Use only conventional tokens in experiments.

The hook cannot identify arbitrageurs or observe external fair value. It cannot charge retrospectively for the first price-moving swap. Small repeated trades can avoid a large per-swap signal, and deliberate trading can raise subsequent users' fees. There is no emergency admin or upgrade path. Liquidity removal is not hooked.

## Build and test

The downloaded Solidity repositories are pinned in `dependencies.lock.json` and ignored by Git. Restore them with `npm run bootstrap`; this checks out exact revisions and refuses mismatches. Do not silently substitute the latest version. Preserve third-party licenses as described in THIRD_PARTY_NOTICES.md.

```powershell
npm.cmd ci --ignore-scripts
npm.cmd run bootstrap
npm.cmd run compile
& '.\node_modules\@foundry-rs\forge-win32-amd64\bin\forge.exe' test -vv
```

The bundled npm test runner is Windows-specific. On other systems, install Foundry and run `forge test -vv`. Foundry downloads Solidity 0.8.26 on first use. The npm compiler is also pinned to 0.8.26. Both builds target Cancun with 200 optimizer runs.

Validation: the original 25 Solidity tests passed, including 1,024 fuzz cases across fee bounds and real settlement. An additional test demonstrates the economic weakness of the fee signal under split trades. Seven browser-signing guard tests passed using a mocked wallet provider. The 16-transaction lifecycle was first simulated and then completed on testnet; live postconditions are in reports/testnet-readback.json. This does not establish compatibility with the official Universal Router or PositionManager, a Hookr listing, or profitability. The patched npm toolchain audit reports zero known vulnerabilities. The GitHub workflow is prepared but has not run on hosted CI.

## Files

- `src/VolatilityRoyaltyHook.sol`: fee and royalty prototype.
- `src/HookFactory.sol`: CREATE2 factory; constructor checks enforce address permission bits.
- `script/DeployHook.s.sol`: chain-checked salt mining and deployment, requiring explicit environment values.
- `test/VolatilityRoyaltyHook.t.sol`: callback unit tests with a mock manager.
- `scripts/compile.cjs`: compile without a globally installed Foundry.
- `dependencies.lock.json` and `package-lock.json`: dependency versions.

Do not deploy the test harness. Do not commit private keys or put them in chat. Use a local encrypted wallet or hardware signer for future transactions.
