# COINBASE (COIN)

`src/CoinbaseToken.sol:CoinbaseToken` is an immutable, fixed-supply ERC-20.
Its constructor mints **1,000,000,000 COIN**, with **18 decimals**, to the immediate deployer.
The implementation extends the vendored OpenZeppelin Contracts v5.0.2 ERC-20 without overriding its transfer or approval logic.

## Deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity contract identifier | `CoinbaseToken` |
| Token name | `COINBASE` |
| Symbol | `COIN` |
| Decimals | `18` |
| Total supply, smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor transaction value | `0` |
| Initial recipient | `msg.sender`, the immediate deployer |
| Target launch chain | Ethereum, chain ID `1` |
| Compiler | Solidity `0.8.26` |
| EVM target | Cancun |
| Optimization | Enabled, 200 runs |
| Metadata | `bytecode_hash = "none"`, CBOR metadata disabled |

Deploy the creation bytecode from `out/CoinbaseToken.sol/CoinbaseToken.json` with no appended arguments.
There are no linked libraries, initialization calls, owner addresses, external dependencies at constructor execution, or post-deployment configuration.
Both ordinary creation and CREATE2 are supported. When the launch factory creates this token, the factory receives the entire supply; the transaction origin and the requester receive nothing in the constructor.
An extra deployment wrapper would receive the supply itself, so the designated factory must create the token directly.

The token emits one `Transfer(address(0), deployer, 10^27)` mint event.
`INITIAL_SUPPLY` is the named constant for the quantity minted.
The token has no owner, mint entry point, burn entry point, pause, blacklist, seizure, tax, rebase, upgrade mechanism, or configurable parameters.
The inherited `_mint` and `_burn` functions are internal and cannot be called after deployment through this contract's ABI.

## Assumptions and behavior

- Standard ERC-20 transfers and approvals are the intended transfer rules. Successful operations return `true`; invalid operations revert with OpenZeppelin's ERC-6093 custom errors.
- Every transfer delivers exactly its amount. There are no fees or address-specific exemptions, including for a factory, distributor, pool manager, or ordinary holder.
- Zero-value transfers to nonzero addresses are supported and emit `Transfer`. Self-transfers preserve balances. Transfers to the zero address and approvals for a zero spender revert.
- `approve` replaces an allowance; `approve(spender, 0)` revokes it. Finite allowances decrease on `transferFrom`; `type(uint256).max` is an unlimited allowance and does not decrease. Even a holder calling `transferFrom` on their own balance needs an allowance for that call.
- `approve` emits `Approval`, and successful transfers emit `Transfer`. This OpenZeppelin version does not emit `Approval` when `transferFrom` consumes an allowance; integrations should query `allowance` for current values.
- The token makes no external calls during deployment or transfers and does not invoke receiver callbacks. There are no oracles, signatures, randomness, scheduled operations, or maintenance transactions.
- Native ETH payments and unknown function selectors revert. There is no recovery function for assets sent to the token contract, including COIN sent to its own address or forcibly received ETH.

## Launch and operational responsibilities

The separate IdentityMD manifest and deployment steps select and deploy `CoinbaseToken` with the parameters above. This repository does not contain a launch manifest, sign transactions, or broadcast a deployment.
No application contracts are required for this task; contracts under `test/` are fixtures only.

The launch factory is responsible for distributing the supply after construction: 10% to the launch's MerkleDistributor, 80% to pool liquidity, and the remaining 10% to the requester address from the supplied launch economics. These allocations are transfers performed by the launch infrastructure, not additional minting or allocations hardcoded into this token.
The launch infrastructure also handles the IMD pair, pool configuration, opening price, and later claims. This token does not configure or operate a pool.

After launch, there are no token admin settings or privileged operators. The deployer should verify the deployed bytecode and metadata, the initial mint event, total supply, and completed allocation transfers, then publish the contract address and verified source.
Holders manage their own transfers and allowances. Approvals authorize the spender to move tokens, including tokens received later, up to the remaining allowance. Prefer bounded approvals; when changing an existing allowance, revoke it and confirm revocation before granting a new amount to reduce the standard approval replacement race.
There is no administrator able to reverse a transfer, recover lost tokens, freeze a compromised account, or upgrade the contract.

## Build and test

Foundry and Solidity 0.8.26 must be installed. All Solidity dependencies and their licenses are ordinary files under `lib/`; there are no submodules, package installation steps, RPC calls, or network requirements once the pinned compiler is available.
See [DEPENDENCIES.md](DEPENDENCIES.md) for provenance and [DEPENDENCIES.sha256](DEPENDENCIES.sha256) for checksums.

Run from the repository root:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x6c66e2f9fbc53a9ff7e8cd8ff02f6a9e98f8d5be97fac9c7f21541677f055e51 forge test
forge fmt --check
```

Tests do not read or change environment variables, access the filesystem, fork a chain, or require credentials. The seed above configures the test runner only.
The configuration runs each fuzz test 1,000 times and each stateful invariant through 256 sequences of up to 64 calls, with unexpected handler reverts treated as failures.

Coverage includes metadata and mint-event accuracy, direct and CREATE2 factory deployment, exact transfers, empty balances, self-transfers, zero and maximum values, finite and unlimited allowances, revocation, unauthorized spending, atomic rollback on failure, unavailable mint/admin/burn calls, runtime opcode restrictions, and fixed supply and allowance accounting across randomized transaction sequences.
The local launch-flow test checks exact token amounts for distribution, claims, and transfers into and out of a pool address. It does not execute a real Uniswap pool.

The supplied protected launch checks were reviewed as requirements. Their external launch infrastructure and runtime manifest inputs are supplied by the independent verifier; those checks are not copied or replaced here.
Local checks use Foundry build, unit tests, fuzzing, invariants, and formatting. Slither and Mythril are not part of this validation. This implementation and its tests still require the launch's independent review before release.
