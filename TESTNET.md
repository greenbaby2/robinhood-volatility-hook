# Robinhood testnet rehearsal and starting costs

The user completed the wallet-signed testnet rehearsal using `0xfE6Fac6620c89f7DDa96d1B3c34300C75aBBe6b8`. Live readback at block 129668987 verified deployed hook/router code and configuration, zero remaining active liquidity, cleared royalty claims, and revoked token approval. See `reports/testnet-readback.json`. The rehearsal uses an isolated copy of Uniswap v4 PoolManager, a valueless faucet token, and an owner-only test router; it does not use a claimed canonical testnet manager or publish to Hookr. The instructions below describe the completed flow; do not replay the old manifest.

## Starting cost

| Item | Testnet amount |
| --- | --- |
| Wallet balance observed October 6, 2026 | 0.01151310063 test ETH |
| Full 16-transaction gas estimate | 0.000283546254177312 test ETH |
| Temporary liquidity payment ceiling | 0.0004 test ETH |
| Buy payment | 0.00001 test ETH |
| Suggested wallet reserve for rehearsal | 0.001 test ETH |
| Real money needed for this rehearsal | $0, using existing test ETH and minted test tokens |

The wallet currently has more than the suggested reserve. The liquidity and swap values are separate from gas; they are not all permanent costs. Unused native input is refunded and the rehearsal withdraws all liquidity at the end. A failed or interrupted sequence can leave a position open until resumed or removed by the owner.

Foundry estimated 14,177,312 gas at 0.020000001 gwei on the fork; the public RPC gas-price read was 0.01 gwei. These are observations, not a guaranteed charge. The wallet performs a fresh gas estimate before each transaction. Reserve figures allow headroom for timing and rollup fee differences. Do not buy mainnet ETH for this test.

Robinhood's docs identify testnet as chain 46630 with RPC `https://rpc.testnet.chain.robinhood.com`. Its terms say test tokens have no monetary value and are not convertible into Robinhood rewards. [Network details](https://docs.robinhood.com/chain/connecting/), [testnet terms](https://docs.robinhood.com/chain/terms-of-service/)

## What passed

- 25 Solidity tests: 10 callback unit tests, 13 tests with the real pinned PoolManager, and 2 deployment-script tests.
- 512 fuzz cases for fee bounds and 512 for round-trip real settlement.
- Native ETH and ERC-20 swap settlement in both directions; mint and redemption of royalties; failed-claim isolation; unauthorized and excessive claims.
- Net-output slippage enforcement after royalties, partial-fill refunds, position ownership, fee collection, complete withdrawal, and expiry checks.
- The complete 16-transaction script simulated successfully on the Robinhood testnet fork at block 129659432, using the supplied wallet's real testnet balance and nonce.
- A direct unsigned RPC opcode probe returned the expected result for PUSH0, TSTORE, and TLOAD. This resolves the specific capability concern behind Foundry's generic unknown-chain EIP-3855 warning; it is not an attestation of every chain feature.
- Seven local signing tests with a mocked wallet provider: wrong manifest chain, tampering, wrong wallet network, stale nonce, wrong account, expired deadline, and one-transaction submission with receipt tracking.

The script removes all liquidity and revokes token approval at the end. All addresses in the unsigned manifest are predicted simulation addresses until confirmed transactions exist. Do not describe them as live deployments.

## Sign with a browser wallet

1. Keep the supplied account selected in the browser wallet and select Robinhood Chain Testnet, chain 46630.
2. Start the local page with `npm.cmd run signing`, if it is not already running. Open `http://127.0.0.1:8765` in the browser containing that wallet extension.
3. Connect the wallet. The page does not request a private key. It checks the chain, account, balance, manifest checksum, and pending nonce before submitting.
4. Click **Sign next transaction**, inspect the wallet confirmation, and approve only the test transaction you expect. Repeat after each receipt confirms. There are 16 transactions.
5. Save receipts when complete. Live verification should check deployed code, hook bits, owner and author, pool configuration, zero remaining liquidity, zero router approval, and cleared royalty claims.

The wallet's starting nonce in the current dry run is 109. If other wallet activity changes it, the page refuses to send a stale plan. Transaction deadlines expire one hour after the simulated block timestamp; finish promptly. Never restart the entire lifecycle to repair a partial run without reconciling the receipts and current nonce first. Share only public transaction hashes when asking for help.

The localhost server serves static files on the loopback interface. It cannot sign transactions and does not handle secrets. Its manifest and local receipt record contain only public transaction data. Review the source under `signing/` before use. A successful local signing test is not proof that your extension is connected or that a transaction was sent.

## Rebuild an unsigned plan

Use a fresh fork for a fresh, entirely unstarted rehearsal:

```powershell
& '.\node_modules\@foundry-rs\forge-win32-amd64\bin\forge.exe' script script/TestnetLifecycle.s.sol:TestnetLifecycle --rpc-url 'https://rpc.testnet.chain.robinhood.com' --sender 0xfE6Fac6620c89f7DDa96d1B3c34300C75aBBe6b8 --non-interactive
npm.cmd run prepare-signing
```

No `--broadcast` is used. The browser-wallet route sends the resulting unsigned transactions one at a time. Do not also broadcast the same plan through Foundry. Foundry keystore or hardware-wallet signing is an alternative, but needs an explicit signer configuration for the same wallet.

Reconstruct dependencies using the pinned lock file and `git -C lib/v4-core submodule update --init lib/solmate lib/forge-std`, then `npm.cmd ci --ignore-scripts`. Run Solidity tests with the bundled forge executable and signing tests with `npm.cmd run test:signing`.

## What this does not establish

Mainnet readiness still requires independent security review, adversarial economic evaluation, compatibility tests with the intended production routers, and an actual trading pair and capital budget. Hookr publication and routing review remain separate work. The rehearsal demonstrates mechanics using test assets; it does not demonstrate organic volume or investment returns.
