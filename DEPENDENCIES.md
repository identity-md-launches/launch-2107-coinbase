# Vendored dependencies

- `openzeppelin-contracts`: [v5.0.2](https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.0.2); archive SHA-256 `18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a`; 6 vendored files.
- `forge-std`: [v1.9.7](https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7); archive SHA-256 `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`; 30 vendored files.

OpenZeppelin includes only the ERC-20 dependency closure and its MIT license.
Forge Standard Library includes its complete src directory and MIT/Apache licenses, for tests only.
Sources are unmodified. These are ordinary repository files, not submodules; no dependency installation or network access is needed to build or test.

`DEPENDENCIES.sha256` records the exact local dependency contents. Verify with `sha256sum -c DEPENDENCIES.sha256`.
