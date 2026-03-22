# Aurum Finance — Developer Onboarding Task

**Duration:** 3–4 days  
**Stack:** Cairo, Scarb, snforge, Starknet Sepolia  

---

## The Story

Aurum Finance is a fictional BTC yield protocol on Starknet. Users deposit **StoneBTC** — a made-up BTC-pegged token with 8 decimals — and receive **auBTC**, Aurum's yield-bearing share token with 18 decimals, in return. The protocol charges a small deposit fee, displays live TVL in USD, and has a minimum deposit threshold so small dusty deposits don't clog the system.

The whitepaper is done. The token contract spec is done. The vault spec is done. Nothing is written yet.

You're building it.

There are four phases: the share token, the vault, tests, and deployment. Do them in order. Each phase builds on the last.

---

## A Word Before You Start

A few things in this task are designed to be tricky. Not trick questions — just the kind of thing that looks fine until it silently produces wrong numbers or a confusing revert. If something feels off, it probably is. Read the spec carefully. The decimal mismatch between StoneBTC (8 decimals) and auBTC (18 decimals) will come up, and it will bite you if you treat them as the same unit.

---

## Phase 1 — The AurumToken Contract

**What it is:** `AurumToken` is the `auBTC` share token. It's an ERC20, but not a dumb one. It has access control, a deposit registry, a depositor whitelist, and rich events. The vault contract will call into it to mint and burn shares — so it needs to know who's allowed to do that.

---

### Spec

**Token parameters**
- Name: `Aurum BTC`
- Symbol: `auBTC`
- Decimals: 18

**Access control**
There is one privileged address called the `vault`. Only the vault can call `mint` and `burn`. The vault address is set in the constructor and stored. There is no way to change it after deployment.

There is also an `owner` — the deployer. The owner can manage the depositor whitelist.

**Depositor whitelist**
The protocol is invite-only at launch. The owner maintains a list of approved depositor addresses. The vault must check this list before minting shares to anyone.

Store approved addresses in two ways:
- A `StorageMap<ContractAddress, bool>` for O(1) lookup
- A `StorageVec<ContractAddress>` to keep an ordered list (useful for iterating all approved depositors)

Expose:
- `add_to_whitelist(address: ContractAddress)` — owner only
- `remove_from_whitelist(address: ContractAddress)` — owner only, sets the map entry to false (do not remove from the Vec — just mark inactive in the map)
- `is_whitelisted(address: ContractAddress) -> bool`
- `get_all_whitelisted() -> Array<ContractAddress>` — returns the Vec as an Array, filtering out addresses where the map entry is false

**Deposit registry**
Every time shares are minted, record a `DepositRecord` struct in storage keyed by the depositor's address:

```
struct DepositRecord {
    depositor: ContractAddress,
    stonebtc_deposited: u256,   // the raw StoneBTC amount (8 decimals)
    aubtc_minted: u256,         // the auBTC shares minted (18 decimals)
    timestamp: u64,
    deposit_count: u32,         // how many times this address has deposited
}
```

Store this as `StorageMap<ContractAddress, DepositRecord>`.

On each mint, update the record: add to `stonebtc_deposited`, add to `aubtc_minted`, increment `deposit_count`, update `timestamp`.

Expose `get_deposit_record(address: ContractAddress) -> DepositRecord`.

**Mint and burn**
- `mint(recipient: ContractAddress, amount: u256, stonebtc_amount: u256)` — vault only. Mints `amount` auBTC to `recipient`. Updates the deposit registry. Checks the whitelist.
- `burn(from: ContractAddress, amount: u256)` — vault only. Burns `amount` auBTC from `from`.

**Events**

Define these events. Apply `#[key]` to fields that should be indexed:

```
SharesMinted {
    #[key] recipient: ContractAddress,
    aubtc_amount: u256,
    stonebtc_deposited: u256,
}

SharesBurned {
    #[key] from: ContractAddress,
    aubtc_amount: u256,
}

WhitelistUpdated {
    #[key] address: ContractAddress,
    approved: bool,
}
```

**Errors**

Define an `Errors` module with felt252 constants for every error condition. Do not use inline string literals in assert statements. Required errors at minimum:

```
NOT_VAULT
NOT_OWNER
NOT_WHITELISTED
ZERO_AMOUNT
ZERO_ADDRESS
VAULT_ALREADY_SET
```

---

### What you'll figure out in this phase

- How to embed `ERC20Component` from OpenZeppelin and expose the standard interface
- How `OwnableComponent` works and how to gate functions behind it
- What `#[key]` does on event fields — why `recipient` is a key but `amount` is not
- How to store and retrieve a custom struct from contract storage
- How `StorageVec` and `StorageMap` work together for the same dataset
- The difference between `felt252`, `u32`, `u64`, `u256`, `ContractAddress` — and which one to use for what
- Why `get_all_whitelisted` returns `Array<ContractAddress>` and not `StorageVec<ContractAddress>` (hint: you can't return storage types across contract boundaries)

---

## Phase 2 — The AurumVault Contract

**What it is:** `AurumVault` is the ERC4626-style vault. It holds StoneBTC, mints auBTC by calling AurumToken, handles fees, enforces a USD minimum deposit using the Pragma oracle, and can be paused.

This contract is more complex. Read the full spec before writing a line.

---

### Spec

**Constructor parameters**
- `stonebtc_address: ContractAddress` — the StoneBTC token
- `aurum_token_address: ContractAddress` — the AurumToken contract
- `oracle_address: ContractAddress` — the Pragma oracle
- `owner: ContractAddress`

Store all of these. They are immutable after deployment.

**Fee mechanism**
The vault charges a deposit fee expressed in basis points. 1 basis point = 0.01%. The default fee is 50 basis points (0.5%).

Store the fee as `u16`. The owner can update it, but it must never exceed 1000 basis points (10%).

When a user deposits, the fee is deducted from the deposit amount before shares are calculated. The fee amount stays in the vault as protocol revenue. Expose a `collect_fees(recipient: ContractAddress)` function for the owner to withdraw accumulated fees.

Track accumulated fees as a separate `u256` storage variable — do not just infer it from the balance.

**Minimum deposit in USD**
The vault enforces a minimum deposit of $10 USD equivalent. Before accepting any deposit, the vault must:

1. Read the BTC/USD price from Pragma
2. Convert the StoneBTC deposit amount to USD
3. Reject if below $10

StoneBTC has 8 decimals. The Pragma price feed returns a price with its own decimal count (read it from the response). You will need to normalise both to the same scale before multiplying. Get this wrong and you'll either reject all deposits or accept dust deposits silently.

Also reject if the oracle price is stale — `last_updated_timestamp` more than 30 minutes behind `get_block_timestamp()`. Revert with a `STALE_ORACLE` error.

**Shares math (ERC4626 formulas)**

```
shares = (assets * total_supply) / total_assets     // on deposit
assets = (shares * total_assets) / total_supply     // on redeem
```

For the initial deposit (total_supply == 0), shares equal the asset amount scaled from 8 to 18 decimals:

```
shares = assets * 10^10
```

This is the scaling factor between StoneBTC (8 dec) and auBTC (18 dec). Think carefully about why this is necessary and add a comment in the code explaining it.

Rounding: always round in favour of the vault. Shares round down on deposit, assets round down on redemption.

**Deposit flow**

`deposit(assets: u256) -> u256`

1. Read oracle price, check staleness, check USD minimum
2. Check caller is whitelisted (call `is_whitelisted` on AurumToken)
3. Pull StoneBTC from caller via `transferFrom` — this requires the caller to have approved the vault first
4. Deduct fee, update `accumulated_fees`
5. Calculate shares using the formula above
6. Call `mint` on AurumToken, passing the net assets (after fee) as the `stonebtc_amount`
7. Emit a `Deposited` event
8. Return shares minted

**Redeem flow**

`redeem(shares: u256) -> u256`

1. Check caller has enough auBTC shares
2. Calculate assets owed using the formula above
3. Call `burn` on AurumToken
4. Transfer StoneBTC back to caller
5. Emit a `Redeemed` event
6. Return assets transferred

**Pausable component**

Write a `PausableComponent` that any contract can embed. It should live in its own file (e.g. `src/components/pausable.cairo`). It provides:

- `paused: bool` in its own storage namespace
- `pause()` and `unpause()` in the impl
- `assert_not_paused()` — panics with `PAUSED` error if paused

Embed it into AurumVault. Gate `deposit` and `redeem` behind `assert_not_paused()`. The `pause` and `unpause` functions on the vault are owner-only.

This is the point of writing it as a component — if you later build a second vault or a lending contract, you drop in the same component without rewriting the logic.

**Read functions**

- `total_assets() -> u256` — StoneBTC balance of the vault minus accumulated fees
- `total_supply() -> u256` — total auBTC in circulation (call ERC20 totalSupply on AurumToken)
- `convert_to_shares(assets: u256) -> u256`
- `convert_to_assets(shares: u256) -> u256`
- `get_tvl_usd() -> u256` — total_assets converted to USD using Pragma price, returned as a u256 with 18 decimals of precision

**Events**

```
Deposited {
    #[key] depositor: ContractAddress,
    stonebtc_in: u256,
    fee_taken: u256,
    aubtc_minted: u256,
}

Redeemed {
    #[key] redeemer: ContractAddress,
    aubtc_burned: u256,
    stonebtc_out: u256,
}

FeeUpdated {
    old_fee_bps: u16,
    new_fee_bps: u16,
}

FeesCollected {
    #[key] recipient: ContractAddress,
    amount: u256,
}
```

**Errors**

Extend the Errors module (or create one in the vault):

```
PAUSED
STALE_ORACLE
BELOW_MIN_DEPOSIT
NOT_WHITELISTED
INSUFFICIENT_SHARES
INSUFFICIENT_ASSETS
FEE_TOO_HIGH
ZERO_AMOUNT
ZERO_ADDRESS
```

---

### What you'll figure out in this phase

- How to call another contract using a dispatcher (`IAurumTokenDispatcher`, `IPragmaOracleDispatcher`)
- The approval flow: why `transferFrom` reverts if the user forgot to call `approve` first, and what the error looks like
- The decimal normalisation problem: StoneBTC is 8 decimals, auBTC is 18, the oracle price has its own decimals — you need all three in the same unit before doing math
- Why `u16` for basis points and not `felt252` or `u256`
- How `PausableComponent` isolates its storage from the host contract
- What `get_block_timestamp()` returns and how to use it for staleness checks
- How to structure cross-contract calls that can fail — what happens if AurumToken's `mint` reverts mid-deposit

---

## Phase 3 — Tests

Write all tests using `snforge`. No exceptions — do not test by deploying manually.

---

### Phase 3a — Unit Tests

**AurumToken tests**

- Deploy the token with a mock vault address and an owner
- Add an address to the whitelist — verify `is_whitelisted` returns true, verify `WhitelistUpdated` event emitted with correct key
- Remove from whitelist — verify returns false, Vec entry still exists but map marks it inactive
- `get_all_whitelisted` returns only active addresses
- Mint shares as the vault address — use `start_cheat_caller_address` to impersonate the vault
- Verify deposit registry is updated correctly after mint: struct fields match what was passed
- Mint zero amount — expect panic with `ZERO_AMOUNT`
- Mint to zero address — expect panic with `ZERO_ADDRESS`
- Try to mint as a non-vault address — expect panic with `NOT_VAULT`
- Try to mint to a non-whitelisted address — expect panic with `NOT_WHITELISTED`
- Burn shares — verify balance decreases, `SharesBurned` event emitted
- Try to burn more than balance — expect panic

**AurumVault tests**

- Deploy vault with a mock oracle, mock StoneBTC, and real AurumToken
- Deposit flow: mint StoneBTC to user, approve vault, deposit — verify auBTC balance matches formula
- Verify fee is deducted: if fee is 50bps and user deposits 1000 StoneBTC, net assets are 995, fee accumulates 5
- Verify deposit registry on AurumToken is updated after deposit
- Second deposit: verify share calculation uses updated total_assets and total_supply
- Two different users deposit — verify each gets proportionally correct shares
- Redeem: deposit, then redeem all shares — verify StoneBTC returned equals net assets deposited (no yield yet, so 1:1 minus fee)
- Simulate yield: transfer extra StoneBTC directly to vault address, then redeem — verify user gets more than deposited
- Deposit when paused — expect panic with `PAUSED`
- Deposit below USD minimum — mock oracle to return a price that makes the deposit fail the threshold
- Deposit with stale oracle — mock `last_updated_timestamp` to be 31 minutes ago — expect panic with `STALE_ORACLE`
- Deposit without approving vault — expect panic (this is the approval trap — understand the error message)
- Deposit as non-whitelisted address — expect panic with `NOT_WHITELISTED`
- Fee update above 1000bps — expect panic with `FEE_TOO_HIGH`
- `collect_fees` as owner — verify accumulated fees transfer out and counter resets
- `collect_fees` as non-owner — expect panic

Use `spy_events` to assert events in the deposit and redeem tests. Check both key fields and data fields.

Use `start_cheat_block_timestamp` for the staleness test.

---

### Phase 3b — Fork Tests

Configure a Sepolia fork in `Scarb.toml`. Write a separate test module tagged `#[fork('sepolia')]`.

- Read a real ERC20 token on Sepolia (e.g. STRK or WBTC) — verify name, symbol, decimals match expected values
- Find a real address that holds STRK on Sepolia (look on Starkscan). Impersonate it with `start_cheat_caller_address`. Verify `balance_of` returns a non-zero value.
- Call the real Pragma oracle on Sepolia and read the BTC/USD price. Assert it is within a sane range — somewhere between $10,000 and $200,000. This is a sanity check that your oracle dispatcher code actually works against a live contract.
- Verify the oracle response's `decimals` field — make sure your normalisation code handles whatever Pragma actually returns, not what you assumed it would return.

Fork tests are slow. Keep them in a separate file and only run them explicitly. Do not mix them with unit tests.

---

## Phase 4 — Deploy to Sepolia

### Step 1 — Build and inspect

Run `scarb build`. Look at the output in `target/dev/`. Understand:

- What is the Sierra JSON file and what is the CASM JSON file
- What a ClassHash is and how it is derived from the Sierra code
- Why two different contract addresses can share the same ClassHash
- What happens if you re-declare an already-declared contract

### Step 2 — Set up starkli

Install `starkli`. Create a Sepolia account using `starkli account oz init`. Fund it with Sepolia ETH from the faucet at faucet.starknet.io.

### Step 3 — Deploy in order

Deploy in this order. Each step depends on the address from the previous one.

1. **Declare and deploy StoneBTC** — this is a plain ERC20 you write quickly just for testing (name: `Stone BTC`, symbol: `SBTC`, decimals: `8`). Mint yourself some tokens.
2. **Declare and deploy AurumToken** — constructor needs `vault_address` and `owner`. For now, use your own wallet as `vault_address` — you'll redeploy or update after vault is deployed. Actually, think about this problem: AurumToken needs to know the vault address at deploy time, but the vault needs to know the AurumToken address. How do you break this circular dependency? There are a few valid approaches — pick one and document why.
3. **Declare and deploy AurumVault** — pass the StoneBTC address, AurumToken address, Pragma Sepolia oracle address, and your wallet as owner.

Record every contract address and transaction hash.

### Step 4 — Execute the full flow using starkli

Run through this sequence using `starkli invoke` and `starkli call`:

1. Add your wallet to the AurumToken whitelist
2. Approve AurumVault to spend your StoneBTC
3. Deposit StoneBTC into the vault — note the auBTC you receive
4. Check your auBTC balance
5. Check `get_tvl_usd` — verify it returns a reasonable number
6. Redeem your auBTC — verify StoneBTC comes back minus the fee
7. Collect fees as owner — verify `accumulated_fees` goes to zero

For each step, find the transaction on Starkscan (Sepolia). Verify the events emitted match what you defined in the contract.

Then try one intentional failure: try to deposit without approving first. Read the revert reason. Understand why it says what it says.

---

## Advanced — AVNU Swap Integration

If you've finished everything above, extend AurumVault with a `swap_stonebtc_to_eth` function.

The idea: the protocol wants to let users exit into ETH in one transaction instead of redeeming StoneBTC and swapping manually. The function should:

1. Accept a `shares` amount from the caller
2. Redeem the shares internally for StoneBTC
3. Call AVNU's Exchange contract on Sepolia to swap StoneBTC for ETH
4. Send the ETH to the caller

You'll need to figure out AVNU's `swap()` interface, the calldata structure for `ExactInputSingleParams`, and how to handle minimum output / slippage. AVNU's docs are at doc.avnu.fi and their Sepolia Exchange contract is listed there.

This is intentionally open-ended. Reading a live contract's ABI, decoding what calldata it expects, and debugging a multi-contract call is exactly the kind of work you'll do on real protocol integrations. The process of figuring it out is the point.

---

## Submission Checklist

When you're done, share:

- Your Scarb project with all contracts, components, and tests
- Sepolia addresses for StoneBTC, AurumToken, and AurumVault
- A Starkscan link to your deposit transaction and your redeem transaction
- A short note — bullet points — on anything that confused you, any bug you hit, or any part of the spec that was ambiguous. This is genuinely useful feedback, not a formality.

---

## Resources

| Resource | URL |
|---|---|
| Cairo Book | book.cairo-lang.org |
| OpenZeppelin Cairo | docs.openzeppelin.com/contracts-cairo |
| snforge docs | foundry-rs.github.io/starknet-foundry |
| Pragma oracle docs | docs.pragma.build |
| Starknet Sepolia faucet | faucet.starknet.io |
| Starkscan Sepolia | sepolia.starkscan.co |
| AVNU docs (advanced) | doc.avnu.fi |
