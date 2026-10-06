# Third party source attribution

The original project files marked MIT are covered by LICENSE. Vendored repositories are excluded from this repository and restored at the exact revisions in `dependencies.lock.json`. Their files retain their own licenses; the project MIT license does not relicense upstream code.

- OpenZeppelin Uniswap Hooks supplies BaseHook, under its upstream MIT license.
- Uniswap v4-core supplies PoolManager, interfaces, and libraries. Individual files have differing SPDX terms, including BUSL-1.1 for PoolManager and MIT for many libraries. Consult each file and the pinned repository license before production use or redistribution.
- Solmate supplies the ERC-20 test token base and upstream core dependencies under its upstream licenses.
- Foundry forge-std supplies testing and script utilities under its upstream licenses.

The economic idea began with user-supplied Gemini text. This repository replaces that example's incompatible API usage and changes fee observation and royalty accounting. It is not a fork of Hookr's native protocol and is not affiliated with Hookr, Uniswap, Robinhood, or OpenZeppelin.
