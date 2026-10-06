# Volatility royalty hook submission draft

Submission page: https://hookr.fun/integrate/hooks

Direct form: https://github.com/Hookr-fun/hookr-contracts/issues/new?template=external-hook.yml

Select the hook publication path. This draft requests source and external-catalog review for a testnet prototype. It does not request native Hookr module admission, production routing, or a mainnet launch. Do not submit until the source repository is public and its exact commit is included.

## Suggested title

External hook review for VolatilityRoyaltyHook with Robinhood testnet evidence

## Source and dependencies

Public repository: REQUIRED BEFORE SUBMISSION

Exact commit: REQUIRED BEFORE SUBMISSION

Hook contract: `src/VolatilityRoyaltyHook.sol`

Factory: `src/HookFactory.sol`

Compiler: Solidity 0.8.26, Cancun, optimizer enabled with 200 runs. Dependencies are pinned in `dependencies.lock.json` and `package-lock.json`. The contract builds on OpenZeppelin BaseHook and Uniswap v4-core; it is not claimed as a wholly original hook framework. Original project source currently uses MIT SPDX identifiers. Preserve third-party licenses and add the repository license file before publication.

## Behavior and permissions

Reactive dynamic LP fee from 1,500 to 10,000 millionths, with a 30-tick threshold and 60-second signal decay. This is not an external price oracle, an arbitrage executor, or guaranteed LVR capture. Parameters are experimental.

The prototype accepts exact-input swaps and rejects exact-output swaps. It charges 10 basis points of actual output on this deployment. Royalties accrue as PoolManager ERC-6909 claims held by the hook. Only the immutable author can redeem them to a selected recipient. A failed redemption does not block subsequent swaps.

Permission bits: `0x10c4`, comprising `afterInitialize`, `beforeSwap`, `afterSwap`, and `afterSwapReturnDelta` in Solidity. Use `afterSwapReturnsDelta` where a catalog schema uses the plural spelling. No upgrade or fee-configuration admin exists. Liquidity removal is not hooked.

## Testnet deployment evidence

- Chain: Robinhood Chain Testnet, 46630. No mainnet deployment.
- Hook: `0x2461be785303ad46678fc0d10268ec72365c50c4`
- Author wallet: `0xfe6fac6620c89f7dda96d1b3c34300c75abbe6b8`
- Isolated PoolManager: `0x8535a86fdae3461e739a386c9bbbace29b9db69c`
- Test-only owner-controlled router: `0x7efbc5658509e32a0594be4f511ce1ff9cabd5d0`
- Valueless faucet token: `0xba7ae894dea95b1ded46cad070011e2bd500c9bc`
- PoolKey: currency0 zero address, currency1 test-token address above, fee `0x800000`, tick spacing 60, hooks address above.
- Pool ID: `0x6afec37a6a83d453891bfc1ef5a6544592685019666ede48672619af58299b48`
- Hook explorer: https://explorer.testnet.chain.robinhood.com/address/0x2461be785303ad46678fc0d10268ec72365c50c4

At testnet block 129668987, readback verified matching hook/router runtime with constructor immutable fields normalized for comparison, the configured manager, recipient and router owner, royalty and permission bits, zero remaining active pool liquidity, zero royalty claims, and zero token allowance to the router. Readback is recorded in `reports/testnet-readback.json`; reproduce with `node scripts/verify-testnet.cjs` after building.

The pool is a completed rehearsal with no remaining liquidity, not an active trading market. This PoolManager is a separately deployed test instance, not a claimed canonical Uniswap deployment. Explorer source verification and a receipt export should be included separately when available; bytecode readback does not imply explorer verification.

## Validation and limitations

The original 25 Solidity tests passed, including real PoolManager settlement tests and 1,024 fuzz cases across two properties. A further test demonstrates split-trade avoidance of the surge signal; see MAINNET_ASSESSMENT.md. Seven local browser-signing tests passed using a mocked provider. The lifecycle covers both trade directions, royalty redemption, partial fills, min-output checks, unauthorized claims, failed ETH reception, fee collection, complete liquidity removal, and approval revocation.

Security status: unaudited research prototype. Official Universal Router and PositionManager integration is not validated. No production routing approval, independent economic validation, organic volume, or profitability is claimed. Manipulable endogenous price signals and first-trade adverse selection remain limitations. Testnet results are not a mainnet safety endorsement.

## Before pressing submit

Supply the public source URL and exact commit, preserve license and attribution files, attach the declared test outputs and live readback, export the rehearsal receipts, and run HookrScan in Source mode if testnet addresses are unsupported. Keep testnet evidence distinct from any future production deployment. Submission is manual review and does not promise acceptance, native builder inclusion, or royalties from other developers' pools.
