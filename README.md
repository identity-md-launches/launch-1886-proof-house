# Proof House (ARTIFACTS)

An immutable, fixed-supply ERC-20. The constructor creates the entire supply once
and credits the immediate deployer (`msg.sender`). Standard transfers and
allowances are provided by the vendored OpenZeppelin Contracts v5.0.2 ERC-20.

## Token and deployment parameters

| Parameter | Value |
| --- | --- |
| Deployable artifact | `src/ProofHouseToken.sol:ProofHouseToken` |
| Solidity contract identifier | `ProofHouseToken` |
| Name | `Proof House` |
| Symbol | `ARTIFACTS` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Supply constant | `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18` |
| Constructor arguments | None (`[]`) |
| Native currency sent on deployment | `0` |
| Intended launch chain | Ethereum, chain ID `1` |
| Solidity compiler | `0.8.26` |
| EVM target | `cancun` |
| Optimizer | Enabled, 200 runs |
| Bytecode metadata hash | `none` |

Deploy this artifact directly using CREATE or CREATE2. It requires no external
contracts, libraries to link, initialization call, owner address, or configuration.
With the launch factory as deployer, the factory receives all `10^27` units;
the wallet that called the factory receives no constructor allocation. Direct
deployment by a wallet instead credits that wallet. The constructor emits one
`Transfer(address(0), deployer, INITIAL_SUPPLY)` event.

The token has no owner, mint entry point, burn entry point, pause, blacklist,
seizure power, transfer fees, rebasing, upgrade mechanism, proxy, or external
calls. There are no additional application contracts. `INITIAL_SUPPLY` cannot
be changed, and no callable operation changes `totalSupply()`.

## Transfer and approval behavior

- `transfer`, `approve`, and `transferFrom` return `true` on success and revert
  with OpenZeppelin ERC-20 custom errors on failure.
- Transfers deliver exactly the specified amount. Self-transfers preserve
  balances; zero-value transfers between nonzero addresses succeed and emit
  `Transfer`. No recipient callback is made.
- Transfers to the zero address and approvals to a zero spender revert.
  Insufficient balances or allowances revert atomically, including restoration
  of allowance when a transfer fails after allowance validation.
- Approvals replace the current allowance. Finite allowances decrease when
  spent. The maximum `uint256` approval is an unlimited allowance and does not
  decrease. There is no deployer bypass of allowances.
- `approve` emits `Approval`; successful transfers emit `Transfer`.
  OpenZeppelin v5 does not emit `Approval` when `transferFrom` spends an
  allowance, so integrations should read `allowance()` for its current value.

Assumptions: the requested custom token uses ordinary ERC-20 transfer semantics;
no taxes, special privileges, or optional permit/governance extensions were
requested. All amounts accepted by the contract use the smallest units.

## Build and check

Foundry and Solidity 0.8.26 must be available. All Solidity dependencies and
licenses are included as ordinary files under `lib/`; installation commands,
submodules, network calls, environment variables, and RPC access are unnecessary
for the tests. The compiler is pinned by version, with no local compiler binary
or machine-specific path in the project.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x995bd73264353c0a3a438f67bbf38b0459007a09fcbc8dd004ed79b51d7b1a69 forge test
forge fmt --check
```

The seed is passed to the runner, not read or set by Solidity tests. No seed is
hardcoded in `foundry.toml`, so other seeds can be used. Fuzz tests run 512 cases
each. The stateful invariant runs 128 sequences of 64 calls, comparing balances
and allowances with an independent model through transfers, approvals,
delegated spending, and rejected overdrafts.

The unit and fuzz suites cover metadata, a single constructor mint, direct and
factory deployment, exact allocation and claim transfers, events, zero/full/self
transfers, allowances and revocation, unlimited allowances, invalid recipients,
insufficient funds or approval, failure atomicity, absence of administrative
entry points, rejection of native currency, and prohibited runtime opcodes.
The factory fixture exercises token movements in both directions but is not a
Uniswap integration test. The supplied protected integration harness depends on
the platform's factory, pool, and manifest infrastructure and runs separately.

Dependency versions, original archive URLs and SHA-256 hashes are recorded in
`lib/openzeppelin-contracts/UPSTREAM.md` and `lib/forge-std/UPSTREAM.md`.

## After launch

There are no owner settings or maintenance transactions. The launch operator
is responsible for deploying the specified artifact, confirming the name,
symbol, decimals, and exact supply, checking that the factory received it, and
verifying the deployed source with the build settings above.

The factory handles the launch's 10% swarm allocation, 80% pool allocation, and
10% remainder according to the supplied launch policy and economics. Those
transfers are not constructor allocations. Pool creation, pricing, distribution,
and the launch manifest belong to the platform's subsequent launch process;
this repository contains only the token and its tests.

Holders and integrations manage their own custody and allowances. Use allowances
appropriate to the intended spend; an unlimited approval lets that spender move
all current and future holdings until revoked. When replacing a nonzero
allowance, account for the standard ERC-20 approval transaction-ordering race
(revoke first and confirm/reconcile spending before approving again).

The contract rejects ordinary ETH payments. Tokens transferred to this contract
or another contract without a withdrawal mechanism cannot be rescued by an
administrator. There is no recovery mechanism for mistaken token transfers or
lost keys.

## Review scope

The supplied security reference was applied to supply arithmetic, authorization,
failure atomicity, external calls, and deployment behavior. The implementation
adds only a constant supply and constructor mint to the vendored ERC-20; no
oracle, randomness, signature, vault, or proxy mechanisms are involved.
Verification uses Foundry unit, fuzz, and invariant tests plus manual source
review. Slither and Mythril were not run. This work is not an independent
security audit; independent review and platform deployment checks remain part
of release. No transaction was broadcast by this project work.
