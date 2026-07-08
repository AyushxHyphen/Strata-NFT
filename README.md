# STRATA — a lineage-native NFT exchange

A working prototype (`index.html`) plus a Solidity reference contract
(`contracts/StrataMarketplace.sol`) for an NFT marketplace built around one
idea: **ownership history should be visible, valuable, and combinable** —
not a footnote in a database.

Open `index.html` directly in a browser. Everything runs client-side with
simulated wallets and a fictional `ORE` token, so there's nothing to install.

## Why it's different from a typical marketplace

Most NFT marketplace clones are the same four screens (mint, list, buy,
profile) reskinned. STRATA changes the underlying mechanics, not just the
theme:

| Mechanic | Typical marketplace | STRATA |
|---|---|---|
| **Royalties** | Flat % to original creator only | **Lineage Royalty Cascade** — 10% of every sale splits across the *entire* ownership chain, weighted toward more recent holders. Early buyers who pass a piece on keep earning from it, which rewards genuine circulation instead of just holding or flipping once. |
| **Artwork** | Static image, metadata only records `owner` | The artwork **is** the ownership record. Each token renders as a stack of geological strata; every transfer deposits a new visible band derived deterministically from the buyer's address. You can look at a piece and see how many hands it's passed through. |
| **Combining assets** | NFTs are terminal — you hold or sell | **Fusion Forge**: burn two owned tokens to mint a hybrid whose on-chain ancestry (`parentsOf`) permanently points at both parents, so collections form family trees instead of flat grids. |
| **Reputation** | Verified badges controlled by the platform | **Trust Vaults**: reputation is staked capital. Anyone can stake `ORE` behind a formation family; the stake itself is the signal, not an opaque checkmark. |
| **How a sale can happen** | One buyer, one seller | **Time-Capsule / crowd-unlock listings**: a token can be listed against a pooled reserve. It only changes hands once the crowd funds it together, and ownership then splits fractionally by contribution — useful for pieces priced above what any single collector wants to pay alone. |

## Files

```
index.html                        self-contained demo (HTML/CSS/vanilla JS)
contracts/StrataMarketplace.sol   reference Solidity implementation of the
                                   same four mechanics (ERC-721 based)
README.md                         this file
```

## How the demo simulates "blockchain" logic

The browser demo doesn't call a real chain, but every action follows the
same deterministic rules the Solidity contract enforces:

- **Deterministic generation** — a token's strata (color, band count,
  mineral flecks) are derived by hashing `(name, wallet, tokenId)` with a
  seeded PRNG (`mulberry32`), the same pattern used on-chain to derive
  traits from a `tokenId` without storing an image.
- **Royalty math is computed and shown before you confirm a purchase** —
  the buy modal breaks down exactly who gets paid and why, mirroring the
  `buy()` function in the contract.
- **Fusion burns and re-mints** rather than editing an existing token,
  matching `fuse()`'s `_burn` + `_safeMint` on-chain.

## Taking it further

To move from prototype to a real deployment:

1. Deploy `StrataMarketplace.sol` (or an audited derivative) to an EVM
   chain; swap the `ORE` token for native ETH/MATIC or an ERC-20.
2. Replace the client-side SVG generator with an on-chain-seeded renderer
   (Chainlink VRF or block-hash seeding) so strata art can't be gamed by
   simulating mints off-chain before submitting.
3. Wrap the crowd-unlock pool's resulting fractional ownership in an
   ERC-1155 or ERC-20 vault token so contributors can trade their share
   without needing the whole group to agree on a resale.
4. Add a subgraph (The Graph) indexing `Sold`, `Fused`, and
   `PoolContribution` events to power the activity feed from real chain
   data instead of local state.

## Notes

This is a design/demo artifact, not audited or production-ready code —
the Solidity file is meant to communicate the mechanics clearly rather
than be gas-optimized or fully hardened (no pausability, no royalty
edge-case handling for very long lineage chains, etc.).
