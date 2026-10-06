# Robinhood Chain hook strategy review and deployment roadmap

The viable idea is to earn fees by supplying useful liquidity and, separately, earn a disclosed royalty when traders use pools containing your code. Blockchain activity does not itself entitle a hook to tokens. Revenue requires real flow, competitive execution, liquidity, and a distribution channel. Net returns can be negative even while fee balances rise.

As of October 6, 2026, Robinhood's documentation lists mainnet chain ID 4663 and testnet 46630. Use `https://rpc.mainnet.chain.robinhood.com` and `https://rpc.testnet.chain.robinhood.com`; Gemini's RPC is not the documented endpoint. [Robinhood deployment guide](https://docs.robinhood.com/chain/deploy-smart-contracts/)

## What needs correcting in the proposal

| Claim or implementation | Assessment |
| --- | --- |
| A high fee captures the whole price disparity | A 3% fee against a roughly 2.5% arbitrage opportunity can deter execution, yielding no fee. A stale inventory position still has economic exposure. |
| Before-swap tick movement detects the incoming arbitrage | It sees already-settled pool state. Without an independent price reference or actual arbitrage execution it does not know the external opportunity. |
| The original state tracks volatility across swaps | It stores the pre-swap tick, and permits a surge only when `block.number` increases. Subsequent same-block swaps receive the base fee, creating a cheap bypass. |
| Fifty ticks produces more than 3% | The supplied formula yields 1,500 + 50 × 120 = 7,500 millionths, or 0.75%. About 247 ticks gives 3.114%, not a guaranteed collectible profit. |
| Production Solidity | The pasted API imports and callback signatures do not match the dependencies used here. The replacement uses the current BaseHook internal override pattern and separate SwapParams type. |
| Royalties always arrive in native ETH | The pasted contract charges output currency. A token output pays tokens; WETH output pays WETH. It also lets exact-output traders skip the royalty. |
| Every blueprint generates author royalties | A listing alone creates no payment obligation. Your deployed fee logic and adoption determine revenue; the current publication flow does not establish Gemini's advertised marketplace royalty arrangement. |
| Pools automatically get aggregator flow | Deployment, publication, and routing integration are different steps. A fee that looks lower can still have worse execution after depth, royalty, gas, and price impact. |

The positive returned after-swap delta must offset the hook's withdrawal or claim creation. The current implementation pairs it with `mint`, accrues ERC-6909 claims, and permits only the author to redeem them separately with `burn` and `take`. Exact-output swaps are rejected. Real PoolManager integration tests now verify settlement; official router integration remains a separate gate. [Uniswap core source](https://github.com/Uniswap/v4-core)

On Arbitrum-derived chains, `block.number` should not be assumed to count local sequencer blocks. The prototype uses timestamps for decay; verify chain timestamp behavior in the fork. Hookr itself documents parent-chain block counting for its guard. [Hookr launchpad documentation](https://hookr.fun/docs/launchpad)

## Two distinct deployment paths

### Use Hookr recapture for the initial economic experiment

Hookr documents a separate arbitrage-recapture root backed by a What The Hook executor. It trades against another venue rather than merely inferring volatility. Native ETH is the required quote currency. Its published split allocates 40% of realized recapture profit to the designated creator; LP participation depends on routing. These are shares of realized profit, not percentages of swap volume. [Recapture concept](https://hookr.fun/docs/concepts/arbitrage-recapture), [market guide](https://hookr.fun/docs/guides/open-a-recapture-market)

Use the current SDK and its documented `root: ROOTS.recapture` option for a reviewed market configuration. First inspect and pin the SDK release, validate its exported addresses against deployed code, read the coordinator's opening pause and protocol-share values, and simulate the complete market creation. Do not assume a new pair has a reference venue or profitable recapture opportunities. [SDK](https://hookr.fun/docs/integrations/sdk)

The docs differ on whether the recapture option is exposed in the app launch picker: the concept page mentions a picker, while the market guide says direct coordinator calls are needed. Resolve that against the current app and SDK before creating a market. Do not use undocumented UI assumptions.

Founding liquidity can be irrevocably locked and pool parameters cannot be changed. Decide whether that fits your capital plan before opening a market. Supplying an ordinary removable external LP position is a separate activity from launching a market. [Known limitations](https://hookr.fun/docs/security/known-limitations)

### Develop and publish your own Uniswap hook

The supplied contract is a standalone hook. It is not a drop-in module for Hookr's sealed roots, and it cannot be attached to an already-created pool. Create a new pool with this address in `PoolKey.hooks`. LPs must voluntarily supply that pool and traders must choose it.

Hookr's external catalog accepts submissions for manual review with pinned public source, failure-path tests, the exact PoolKey, and deployment readback. Listing does not install code into its native launch system. Integrating a new executor into the native system requires a partner review and a new root. [Publishing guide](https://hookr.fun/docs/integrations/partner-review)

Uniswap routing is a separate gate for dynamic-fee and return-delta hooks. Hookr reports its default root is allowlisted and its recapture roots are not submitted; neither status applies to this new contract. Direct router compatibility also does not imply the Uniswap app will discover or route to a pool. [Routing documentation](https://hookr.fun/docs/integrations/hooklist-and-routing)

## Roadmap with completion gates

1. **Select the experiment.** Choose one conventional token pair with genuine external trading, define the maximum capital at risk, recipient wallet, and whether the goal is LP returns, developer royalties, or market-creator recapture. Start with zero royalty as a control. Do not assume $HOOKR volume or Pons graduation terms from the pasted text.
2. **Establish a baseline.** Collect historical swaps, liquidity, external reference prices, gas, and route availability for that pair. Replay identical capital and range policies under static fees and the prototype. Include first-swap adverse selection, quiet periods, fragmented trades, manipulated signals, and different trade arrival patterns. Gate: positive incremental marked-to-market return after costs across multiple market conditions, not merely higher gross fees. Historical routes must not be assumed to persist when fees change.
3. **Complete contract integration tests.** Use the real pinned PoolManager and routers. Cover both directions, native and ERC-20 settlement, partial fills, min-output protection after royalty, max amounts, dust, exact-output rejection, invalid permissions, unauthorized callbacks, receiver reverts and reentrancy, token transfer failures, and multiple pools. Check net manager deltas settle to zero and author credits equal trader deductions. Fuzz the full transaction path. Gate: passing tests and independent review of the actual release commit.
4. **Run an unfunded mainnet fork and a testnet rehearsal.** Record a fixed mainnet block, chain ID, PoolManager and router runtime hashes. Deploy factory and hook locally, initialize a pool, add liquidity, swap, collect fees, and remove liquidity. On testnet use a verified testnet v4 deployment or explicitly deploy a local test stack; never reuse mainnet addresses by assumption. Gate: receipts and reproducible balances for the entire lifecycle.
5. **Publish evidence and arrange routing.** Verify deployed source and exact compiler settings. Submit the hook to Hookr's analyzer and publication flow. Prepare Uniswap hooklist and routing submissions separately. Disclose exact-input-only behavior, immutable royalty, output currency, fee cap, and lack of external-price protection. Gate: an actual quote and route through the intended integration, not just catalog visibility.
6. **Consider a capped mainnet pilot.** Set the budget only after tests and review. Use a small removable position for the standalone hook, a recipient known to accept ETH, bounded approvals, explicit minimum amounts, and deadlines. Monitor fees, inventory value, external prices, reverted swaps, gas, and organic volume. Gate: measurable net performance and operational reliability before increasing exposure.

These are engineering gates, not promises of an audit schedule or return. The user selected testnet first; current rehearsal results are in TESTNET.md. The custom path requires more work than the current recapture integration. Mainnet remains outside the current launch scope.

## Custom hook deployment sequence

Uniswap's deployment page currently lists Robinhood's v4 PoolManager as `0x8366a39CC670B4001A1121B8F6A443A643e40951`. Treat this as a documented address to verify through your RPC, not as an address attested by this project. [Uniswap deployments](https://developers.uniswap.org/deployments)

After the preceding gates, install Foundry or use the Windows binary in `node_modules`. The following commands use a local encrypted Foundry account named `pilot`; create it locally without exposing the secret in command history. First simulate factory deployment:

```powershell
forge create src/HookFactory.sol:HookFactory --rpc-url $env:RH_RPC_URL --account pilot
```

Only when the simulation and target network are correct, append `--broadcast` to deploy the factory and record its address. Then set the following environment values for the chosen rehearsal network:

```powershell
$env:EXPECTED_CHAIN_ID = '46630'
$env:RH_RPC_URL = 'https://rpc.testnet.chain.robinhood.com'
$env:HOOK_FACTORY = '<your verified factory address>'
$env:POOL_MANAGER = '<verified manager on this network>'
$env:ROYALTY_RECIPIENT = '<your receiving wallet>'
$env:ROYALTY_BPS = '0'
forge script script/DeployHook.s.sol:DeployHook --rpc-url $env:RH_RPC_URL --account pilot
```

The script mines a salt for the exact factory, creation bytecode, and constructor arguments. The required low 14 address bits are `0x10c4`: afterInitialize, beforeSwap, afterSwap, and afterSwapReturnDelta. A different author, royalty, compiler, or manager changes the salt search. After reviewing the simulated result, `--broadcast` executes it. Verify factory bytecode before calling it; the script checks code presence, not trusted runtime hashes. These deployment scripts compile but have not been rehearsed on a live network.

Initialize through the verified manager using sorted currencies, `fee = 0x800000`, valid tick spacing, your deployed hook, and the desired initial square-root price. The square-root price is `sqrt(rawCurrency1/rawCurrency0) * 2^96`; token decimals and currency ordering must be accounted for. Verify a round-trip price calculation before signing. Initialization creates no liquidity.

Mint a position through the network's verified PositionManager using its current ABI and bounded amounts. ERC-20 PositionManager flows normally involve Permit2 approvals. Simulate the complete action encoding, including settlement and token refund, against the exact release. Perform bounded exact-input router swaps; verify the royalty is included in the final output minimum. Collect position fees explicitly, then test removal. Pool initialization, liquidity minting, trading, and fee collection scripts are intentionally future integration work pending the pair, position range, budget, and full settlement tests.

## Measure income without confusing it with profit

Developer revenue is the sum of actual output royalties valued at realizable prices, minus payout and conversion costs. At hypothetical eligible output value of $500,000 and 10 bps, gross royalty is approximately $500; this is arithmetic, not a volume forecast. Different trade modes, fees, prices, and routing make it different from exactly 0.1% of a dashboard's gross volume.

LP performance is ending inventory marked to market plus collected fees and verified incentives, minus contributed capital and gas or rebalancing costs. Compare that with holding the initial assets and with the same liquidity strategy using static fees. Do not subtract impermanent loss a second time if it is already captured in the inventory comparison.

If you are both LP and author, moving value from your own traders or your own swaps into the author wallet is not new external income. Self-trading loses fees and gas overall. Rewards or airdrops belong in the model only when an actual program and eligibility rules are verified; none is assumed here.
