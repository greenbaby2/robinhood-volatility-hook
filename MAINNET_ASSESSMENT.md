# Mainnet feasibility and liquidity explanation

The hook works mechanically on testnet, but its profitability and LVR protection are not established. With a budget below $250, the current recommendation is to publish the research, improve the fee design, and avoid funding a new custom pool as an income strategy yet. A small mainnet deployment can demonstrate code availability; deploying the hook alone earns nothing.

## What you would deploy and fund

The same wallet can deploy on Robinhood mainnet, chain 4663, using its mainnet ETH. Testnet contracts, approvals, and balances do not carry over. The observed mainnet native balance was approximately 0.0171971 ETH; that is not a full portfolio valuation.

1. Deploy the hook against the existing canonical Uniswap v4 PoolManager on mainnet. Do not deploy the rehearsal PoolManager, faucet token, or owner-only test router as production infrastructure.
2. Create a new pool for two existing assets, specifying your hook in its PoolKey. This creates a pool inside PoolManager, not a new ERC-20 token or a separate v3-style pair contract.
3. Supply liquidity to that new pool. For a two-sided active position, this generally requires both assets; exact proportions depend on current price and your chosen range. A hypothetical $200 symmetric position might allocate about $100 to each asset, but the actual mint amounts must be quoted.
4. Earn LP fees only while the position participates in trades. Your author royalty accrues separately on eligible swaps through pools using your deployed hook.

You can be a hook developer without being an LP if other people fund pools using your code. If you want your own pool to trade immediately and have no outside LPs, you must provide its liquidity. Publishing to Hookr does not supply capital or guarantee adoption.

Adding liquidity to an existing pool is also possible as a separate LP strategy, but it does not install your hook into that pool. A hook is immutable within the PoolKey. Dexscreener shows existing markets; it is not a place to attach a contract. [Uniswap hooks](https://developers.uniswap.org/docs/protocols/v4/concepts/hooks), [PoolManager](https://developers.uniswap.org/docs/protocols/v4/concepts/poolmanager)

## Live market sample

The Dexscreener API snapshot was fetched October 6, 2026 at 1:19 a.m. America/New_York. It is a search-based sample, not every Robinhood market. Figures are reported by Dexscreener and have not been independently reconstructed from chain history. Total liquidity is not the same as active executable depth. Reported volume is not proof of organic demand.

| Existing pool | Reported liquidity | Reported 24h volume | Assessment |
| --- | ---: | ---: | --- |
| [WETH/USDG Uniswap v3](https://dexscreener.com/robinhood/0x52e65b17fb6e5ba00ed806f37afcd2daa50271ca) | $24.38m | $243.07m | First pair to study for ordinary LP mechanics; deep competition makes a $250 custom pool hard to route into. |
| [PONS/WETH Uniswap v3](https://dexscreener.com/robinhood/0xed50bdeea8adc232f159486192a4157281d722ff) | $3.16m | $2.63m | More speculative token exposure; not selected for this first custom pool. |
| [HOOKR/ETH Uniswap v4](https://dexscreener.com/robinhood/0x590dcb6a87828bf688b48089a62239b693378f1fb64d2286e6a399ed8c005fdf) | $966,524 | $1.26m | Active, but the snapshot reports a 29.84% 24h price drop. High volume does not mean safer LP returns. |

WETH `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` and USDG `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` match Robinhood's official contract list. Tickers alone are not enough; search results include duplicate symbols. Additional token verification is required before any PONS or HOOKR purchase. [Official token addresses](https://docs.robinhood.com/chain/contracts/)

For research, prefer WETH/USDG as the benchmark and compare against adding liquidity to an existing market. For this hook as currently written, no mainnet funded pair is recommended yet. If a later pilot proceeds, keep the first exposure small and removable rather than allocating the entire budget. A new pool would have its own pool ID and start with no established volume.

## What the effectiveness tests actually show

Settlement, royalty claims, partial-fill handling, and liquidity removal passed. This demonstrates contract mechanics, not profitable execution or resistance to all adversarial trading.

An added real-PoolManager experiment split 1 ETH of swap input into 100 trades of 0.01 ETH. The per-trade signal ended at 2 ticks; the next trade still paid the 0.15% base fee. A single 1 ETH trade produced a 199-tick signal and a 0.488% next-trade fee. Both paths moved the pool price substantially. Small-trade fragmentation therefore avoids the intended surge response. This is an economic design limitation that is deliberately recorded by `testSplitTradesAvoidSurgeSignal`, not a profitability backtest.

The hook also cannot react to an external market price change before the first price-moving trade reaches this pool. It has no independent fair-value feed or arbitrage executor.

The large WETH/USDG reference pool returned `fee() = 100`, or 0.01%, in a direct mainnet RPC read. This prototype starts at 0.15% LP fee plus 0.10% of output as royalty, approximately 0.25% before price impact and gas. Even a zero-royalty deployment would retain its hardcoded 0.15% base fee. This is a material routing disadvantage against that reference, not evidence that all existing routes charge the same fee.

For scale only: at $100 daily volume through your new pool, 0.15% produces roughly $0.15 gross LP fees for the pool and a 0.10% output royalty is roughly $0.10. This assumes comparable dollar valuation of output and ignores rounding and price impact. Actual LP allocation depends on active liquidity and protocol fees; neither amount is net profit. Existing market volume cannot be assigned to your new pool in this calculation.

## Cost rehearsal

A read-only mainnet fork successfully simulated deploying a factory and this hook against the existing manager. At the sampled settings, Foundry estimated 4,268,130 gas at 0.040000001 gwei, totaling 0.00017072520426813 ETH. This is only factory plus hook deployment. It excludes pool initialization, approvals, acquiring assets, minting a position, swaps, withdrawals, and any bridge costs. No mainnet transaction was broadcast.

The liquidity budget is capital exposed to market and contract risk, not a gas charge. A sub-$250 budget can fund a technical experiment but does not buy a share of all Robinhood trading. Testnet success does not substitute for independent review, production-router integration, and competitive fee calibration.

## Publication status

The local project has source, MIT licensing for original files, upstream attribution, pinned dependencies, a restore script, tests, a proposed CI workflow, and deployment evidence. Public repository: https://github.com/greenbaby2/robinhood-volatility-hook. Reviewed source commit: `0e078775d044e527134c40f75ec9ddc373623c06`. Hookr submission should describe an unaudited experimental fee hook, not claim proven MEV capture or guaranteed returns.
