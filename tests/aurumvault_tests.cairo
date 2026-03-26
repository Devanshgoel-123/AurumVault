use aurumvault::aurumToken::interface::{
    DepositRecord, IAurumTokenDispatcher, IAurumTokenDispatcherTrait,
};
use aurumvault::pausable::interface::{IPausableDispatcher, IPausableDispatcherTrait};
use aurumvault::pragma::pragma::{IPragmaABIDispatcher, IPragmaABIDispatcherTrait};
use aurumvault::vault::interface::{IVaultDispatcher, IVaultDispatcherTrait};
use core::array::ArrayTrait;
use core::felt252;
use core::integer::u256;
use core::num::traits::Pow;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyTrait, EventsFilterTrait, declare, spy_events,
    start_cheat_block_timestamp, start_cheat_caller_address, start_cheat_caller_address_global,
    stop_cheat_block_timestamp, stop_cheat_caller_address, stop_cheat_caller_address_global,
};
use starknet::ContractAddress;

const DEPOSIT_FEE: u16 = 50;
const MINIMUM_DEPOSIT_IN_USD: u256 = 15_u256;
const BTC_USD_ASSET_ID: felt252 = 'BTC/USD';

const OWNER: ContractAddress = 0x1001.try_into().unwrap();
const VAULT: ContractAddress = 0x2002.try_into().unwrap();
const USER_ONE: ContractAddress = 0x3003.try_into().unwrap();
const USER_TWO: ContractAddress = 0x4004.try_into().unwrap();


#[starknet::interface]
trait IERC20Like<TContractState> {
    fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TContractState, from: ContractAddress, to: ContractAddress, amount: u256,
    ) -> bool;
}

#[starknet::interface]
trait IMockPriceOracle<TContractState> {
    fn set_price(ref self: TContractState, price: felt252);
}

fn deploy_aurum_token(owner: ContractAddress, vault: ContractAddress) -> IAurumTokenDispatcher {
    start_cheat_caller_address_global(owner);
    let contract = declare("aurumtoken").unwrap().contract_class();
    let constructor_calldata = array![];
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    stop_cheat_caller_address_global();
    IAurumTokenDispatcher { contract_address }
}

fn deploy_stonebtc(
    owner: ContractAddress, name: ByteArray, symbol: ByteArray,
) -> IERC20LikeDispatcher {
    start_cheat_caller_address_global(owner);
    let contract = declare("MockERC20").unwrap().contract_class();
    let mut calldata: Array<felt252> = array![];
    name.serialize(ref calldata);
    symbol.serialize(ref calldata);
    calldata.append(8);
    calldata.append(0); // initial_supply low
    calldata.append(0); // initial_supply high
    calldata.append(owner.into()); // recipient (zero, no initial mint)
    let (contract_address, _) = contract.deploy(@calldata).unwrap();
    stop_cheat_caller_address_global();
    IERC20LikeDispatcher { contract_address }
}

fn deploy_oracle(owner: ContractAddress) -> IPragmaABIDispatcher {
    start_cheat_caller_address_global(owner);
    let contract = declare("MockPriceOracle").unwrap().contract_class();
    let constructor_calldata = array![];
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    stop_cheat_caller_address_global();
    IPragmaABIDispatcher { contract_address }
}

fn deploy_vault(
    owner: ContractAddress,
    stonebtc_address: ContractAddress,
    aurum_token_address: ContractAddress,
    oracle_address: ContractAddress,
    deposit_fee: u16,
    minimum_deposit_in_usd: u256,
    btc_usd_asset_id: felt252,
) -> IVaultDispatcher {
    start_cheat_caller_address_global(owner);
    let contract = declare("vault").unwrap().contract_class();
    let constructor_calldata = array![
        owner.into(), stonebtc_address.into(), aurum_token_address.into(), oracle_address.into(),
        deposit_fee.into(), minimum_deposit_in_usd.low.into(), minimum_deposit_in_usd.high.into(),
        btc_usd_asset_id.into(),
    ];
    let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
    stop_cheat_caller_address_global();

    IVaultDispatcher { contract_address }
}

fn setup_vault_suite() -> (
    IAurumTokenDispatcher, IVaultDispatcher, IERC20LikeDispatcher, IPragmaABIDispatcher,
) {
    let stonebtc = deploy_stonebtc(OWNER, "StoneBTC", "stBTC");
    let oracle = deploy_oracle(OWNER);
    let token = deploy_aurum_token(OWNER, OWNER);
    let vault = deploy_vault(
        OWNER,
        stonebtc.contract_address,
        token.contract_address,
        oracle.contract_address,
        DEPOSIT_FEE,
        MINIMUM_DEPOSIT_IN_USD,
        BTC_USD_ASSET_ID,
    );

    start_cheat_caller_address(token.contract_address, OWNER);
    token.set_vault(vault.contract_address);
    token.add_to_whitelist(USER_ONE);
    stop_cheat_caller_address(token.contract_address);

    (token, vault, stonebtc, oracle)
}

fn set_oracle_price(oracle: IPragmaABIDispatcher, price: felt252) {
    let oracle_setter = IMockPriceOracleDispatcher { contract_address: oracle.contract_address };
    start_cheat_caller_address(oracle.contract_address, OWNER);
    oracle_setter.set_price(price);
    stop_cheat_caller_address(oracle.contract_address);
}

fn assert_deposit_record(
    record: DepositRecord,
    depositor: ContractAddress,
    stonebtc_deposited: u256,
    aubtc_minted: u256,
    expected_count: u32,
) {
    assert(record.depositor == depositor, 'depositor mismatch');
    assert(record.stonebtc_deposited == stonebtc_deposited, 'stonebtc record mismatch');
    assert(record.aubtc_minted == aubtc_minted, 'aubtc record mismatch');
    assert(record.deposit_count == expected_count, 'deposit count mismatch');
}

fn whitelist_user(token: IAurumTokenDispatcher, user: ContractAddress) {
    start_cheat_caller_address(token.contract_address, OWNER);
    token.add_to_whitelist(user);
    stop_cheat_caller_address(token.contract_address);
}

fn mint_and_approve_stonebtc(
    stonebtc: IERC20LikeDispatcher,
    user: ContractAddress,
    amount: u256,
    vault_address: ContractAddress,
) {
    start_cheat_caller_address(stonebtc.contract_address, OWNER);
    stonebtc.mint(user, amount);
    stop_cheat_caller_address(stonebtc.contract_address);

    start_cheat_caller_address(stonebtc.contract_address, user);
    let approved = stonebtc.approve(vault_address, amount);
    stop_cheat_caller_address(stonebtc.contract_address);
    assert(approved, 'approve failed');
}

fn deposit_for_user(vault: IVaultDispatcher, user: ContractAddress, amount: u256) -> u256 {
    start_cheat_caller_address(vault.contract_address, user);
    let minted = vault.deposit(amount);
    stop_cheat_caller_address(vault.contract_address);
    minted
}

// #[test]
// fn deposit_mints_shares_and_matches_formula() {
//     let (token, vault, stonebtc, _) = setup_vault_suite();
//     let deposit_amount = 1000_u256;
//     let expected_net_assets = 995_u256;
//     let expected_shares = expected_net_assets * 10_u256.pow(10);

//     let token_erc20 = IERC20LikeDispatcher { contract_address: token.contract_address };

//     start_cheat_caller_address(stonebtc.contract_address, OWNER);
//     stonebtc.mint(USER_ONE, deposit_amount);
//     stop_cheat_caller_address(stonebtc.contract_address);
//     println!("minted: {}", deposit_amount);
//     println!("expected: {}", expected_shares);
//     start_cheat_caller_address(stonebtc.contract_address, USER_ONE);
//     let approved = stonebtc.approve(vault.contract_address, deposit_amount);
//     stop_cheat_caller_address(stonebtc.contract_address);
//     assert(approved, 'approve failed');
//     println!("approved: {}", approved);

//     start_cheat_caller_address(vault.contract_address, USER_ONE);
//     let minted = vault.deposit(deposit_amount);
//     stop_cheat_caller_address(vault.contract_address);

//     assert(minted == expected_shares, 'share formula mismatch');
//     assert(token_erc20.balance_of(USER_ONE) == expected_shares, 'aubtc balance mismatch');
//     assert(vault.total_assets() == expected_net_assets, 'net assets mismatch');
// }

// #[test]
// fn deposit_deducts_fee_and_accumulates_fees() {
//     let (_, vault, stonebtc, _) = setup_vault_suite();
//     let deposit_amount = 1000_u256;
//     let expected_fee = 5_u256;
//     let expected_net_assets = 995_u256;

//     mint_and_approve_stonebtc(stonebtc, USER_ONE, deposit_amount, vault.contract_address);
//     let _ = deposit_for_user(vault, USER_ONE, deposit_amount);

//     let vault_stonebtc_balance = stonebtc.balance_of(vault.contract_address);
//     let reported_total_assets = vault.total_assets();

//     assert(vault_stonebtc_balance == deposit_amount, 'vault balance mismatch');
//     assert(reported_total_assets == expected_net_assets, 'net assets mismatch');
//     assert(vault_stonebtc_balance - reported_total_assets == expected_fee, 'fee mismatch');
// }

// #[test]
// fn deposit_updates_aurumtoken_deposit_registry() {
//     let (token, vault, stonebtc, _) = setup_vault_suite();
//     let deposit_amount = 1000_u256;
//     let expected_shares = 995_u256 * 10_u256.pow(10);
//     println!("expected_shares: {}", expected_shares);

//     mint_and_approve_stonebtc(stonebtc, USER_ONE, deposit_amount, vault.contract_address);
//     let minted = deposit_for_user(vault, USER_ONE, deposit_amount);
//     let fee_bps: u256 = 50_u16.into();
//     let fee = deposit_amount * fee_bps / 10000_u256;
//     let stonebtc_amount = deposit_amount - fee;
//     assert(minted == expected_shares, 'minted shares mismatch');
//     let record = token.get_deposit_record(USER_ONE);

//     assert_deposit_record(record, USER_ONE, stonebtc_amount, expected_shares, 1_u32);
// }

// #[test]
// fn second_deposit_uses_updated_assets_and_supply() {
//     let (_, vault, stonebtc, _) = setup_vault_suite();
//     let first_deposit = 1000_u256;
//     let second_deposit = 1000_u256;
//     let first_net_assets = 995_u256;
//     let second_net_assets = 995_u256;
//     mint_and_approve_stonebtc(
//         stonebtc, USER_ONE, first_deposit + second_deposit, vault.contract_address,
//     );

//     let first_minted = deposit_for_user(vault, USER_ONE, first_deposit);
//     println!("first_minted: {}", first_minted);
//     let total_assets_before_second = vault.total_assets()+ second_deposit;
//     println!("total_assets_before_second: {}", total_assets_before_second);
//     let total_supply_before_second = vault.total_supply();
//     println!("total_supply_before_second: {}", total_supply_before_second);
//     let expected_second_minted = ((second_net_assets) * total_supply_before_second)
//         / total_assets_before_second;
//     println!("expected_second_minted: {}", expected_second_minted);
//     let second_minted = deposit_for_user(vault, USER_ONE, second_deposit);
//     println!("second_minted: {}", second_minted);
//     assert(first_minted == first_net_assets * 10_u256.pow(10), 'first mint mismatch');
//     assert(second_minted == expected_second_minted, 'second mint mismatch');
// }

#[test]
fn two_users_receive_proportional_shares() {
    let (token, vault, stonebtc, _) = setup_vault_suite();
    let token_erc20 = IERC20LikeDispatcher { contract_address: token.contract_address };
    let user_one_deposit = 1000_u256;
    let user_two_deposit = 2000_u256;
    let user_one_net = 995_u256;
    let user_two_net = 1990_u256;

    whitelist_user(token, USER_ONE);
    whitelist_user(token, USER_TWO);
    mint_and_approve_stonebtc(stonebtc, USER_ONE, user_one_deposit, vault.contract_address);
    mint_and_approve_stonebtc(stonebtc, USER_TWO, user_two_deposit, vault.contract_address);

    let minted_user_one = deposit_for_user(vault, USER_ONE, user_one_deposit);
    let minted_user_two = deposit_for_user(vault, USER_TWO, user_two_deposit);

    assert(minted_user_one == user_one_net * 10_u256.pow(10), 'user one mint mismatch');
    assert(minted_user_two == user_two_net * 10_u256.pow(10), 'user two mint mismatch');
    assert(minted_user_two == minted_user_one * 2_u256, 'user proportionality mismatch');
    assert(token_erc20.balance_of(USER_ONE) == minted_user_one, 'user one balance mismatch');
    assert(token_erc20.balance_of(USER_TWO) == minted_user_two, 'user two balance mismatch');
}

#[test]
fn redeem_all_returns_net_assets_deposited() {
    let (token, vault, stonebtc, _) = setup_vault_suite();
    let deposit_amount = 1000_u256;
    let expected_net_assets = 995_u256;
    let token_erc20 = IERC20LikeDispatcher { contract_address: token.contract_address };

    mint_and_approve_stonebtc(stonebtc, USER_ONE, deposit_amount, vault.contract_address);
    let minted = deposit_for_user(vault, USER_ONE, deposit_amount);
    let stonebtc_before_redeem = stonebtc.balance_of(USER_ONE);

    start_cheat_caller_address(vault.contract_address, USER_ONE);
    let redeemed_assets = vault.redeem(minted);
    stop_cheat_caller_address(vault.contract_address);

    let stonebtc_after_redeem = stonebtc.balance_of(USER_ONE);
    assert(redeemed_assets == expected_net_assets, 'redeemed amount mismatch');
    assert(
        stonebtc_after_redeem - stonebtc_before_redeem == expected_net_assets,
        'stonebtc returned mismatch',
    );
    assert(token_erc20.balance_of(USER_ONE) == 0_u256, 'shares not fully burned');
}

#[test]
fn deposit_emits_deposited_event_with_expected_keys_and_data() {
    let (token, vault, stonebtc, _) = setup_vault_suite();
    let _token_erc20 = IERC20LikeDispatcher { contract_address: token.contract_address };
    let deposit_amount = 1000_u256;
    let expected_fee = 5_u256;
    let expected_minted = 995_u256 * 10_u256.pow(10);

    mint_and_approve_stonebtc(stonebtc, USER_ONE, deposit_amount, vault.contract_address);
    let mut spy = spy_events();
    let minted = deposit_for_user(vault, USER_ONE, deposit_amount);
    assert(minted == expected_minted, 'mint mismatch');

    let vault_events = spy.get_events().emitted_by(vault.contract_address);
    assert(vault_events.events.len() == 1_usize, 'deposited event missing');
    let (_, event) = vault_events.events.at(0_usize);

    assert(event.keys.len() == 2_usize, 'invalid keys length');
    assert(*event.keys.at(1_usize) == USER_ONE.into(), 'depositor key mismatch');
    assert(event.data.len() == 6_usize, 'invalid data length');
    assert(*event.data.at(0_usize) == deposit_amount.low.into(), 'stonebtc low mismatch');
    assert(*event.data.at(1_usize) == deposit_amount.high.into(), 'stonebtc high mismatch');
    assert(*event.data.at(2_usize) == expected_fee.low.into(), 'fee low mismatch');
    assert(*event.data.at(3_usize) == expected_fee.high.into(), 'fee high mismatch');
    assert(*event.data.at(4_usize) == minted.low.into(), 'minted low mismatch');
    assert(*event.data.at(5_usize) == minted.high.into(), 'minted high mismatch');
}

#[test]
fn redeem_emits_redeemed_event_with_expected_keys_and_data() {
    let (token, vault, stonebtc, _) = setup_vault_suite();
    let token_erc20 = IERC20LikeDispatcher { contract_address: token.contract_address };
    let deposit_amount = 1000_u256;

    mint_and_approve_stonebtc(stonebtc, USER_ONE, deposit_amount, vault.contract_address);
    let minted = deposit_for_user(vault, USER_ONE, deposit_amount);

    let mut spy = spy_events();
    start_cheat_caller_address(vault.contract_address, USER_ONE);
    let redeemed = vault.redeem(minted);
    stop_cheat_caller_address(vault.contract_address);

    assert(token_erc20.balance_of(USER_ONE) == 0_u256, 'shares not burned');
    assert(redeemed == 995_u256, 'redeemed mismatch');
    let vault_events = spy.get_events().emitted_by(vault.contract_address);
    assert(vault_events.events.len() == 1_usize, 'redeemed event missing');
    let (_, event) = vault_events.events.at(0_usize);

    assert(event.keys.len() == 2_usize, 'invalid keys length');
    assert(*event.keys.at(1_usize) == USER_ONE.into(), 'redeemer key mismatch');
    assert(event.data.len() == 4_usize, 'invalid data length');
    assert(*event.data.at(0_usize) == minted.low.into(), 'burned low mismatch');
    assert(*event.data.at(1_usize) == minted.high.into(), 'burned high mismatch');
    assert(*event.data.at(2_usize) == redeemed.low.into(), 'out low mismatch');
    assert(*event.data.at(3_usize) == redeemed.high.into(), 'out high mismatch');
}

#[test]
fn redeem_after_external_yield_returns_more_than_net_deposit() {
    let (token, vault, stonebtc, _) = setup_vault_suite();
    let _token_erc20 = IERC20LikeDispatcher { contract_address: token.contract_address };
    let deposit_amount = 1000_u256;
    let simulated_yield = 100_u256;
    let net_deposit = 995_u256;

    mint_and_approve_stonebtc(stonebtc, USER_ONE, deposit_amount, vault.contract_address);
    start_cheat_caller_address(stonebtc.contract_address, OWNER);
    stonebtc.mint(OWNER, simulated_yield);
    let transferred = stonebtc.transfer(vault.contract_address, simulated_yield);
    stop_cheat_caller_address(stonebtc.contract_address);
    assert(transferred, 'yield transfer failed');

    let minted = deposit_for_user(vault, USER_ONE, deposit_amount);
    start_cheat_caller_address(vault.contract_address, USER_ONE);
    let redeemed = vault.redeem(minted);
    stop_cheat_caller_address(vault.contract_address);

    assert(redeemed > net_deposit, 'yield not reflected');
}

#[test]
#[should_panic(expected: ('PAUSED',))]
fn deposit_when_paused_reverts_with_paused() {
    let (token, vault, stonebtc, _) = setup_vault_suite();
    whitelist_user(token, USER_ONE);
    let pausable = IPausableDispatcher { contract_address: vault.contract_address };
    let deposit_amount = 1000_u256;
    start_cheat_caller_address(vault.contract_address, OWNER);
    pausable.pause();
    stop_cheat_caller_address(vault.contract_address);
    mint_and_approve_stonebtc(stonebtc, USER_ONE, deposit_amount, vault.contract_address);
    start_cheat_caller_address(vault.contract_address, USER_ONE);
    let _ = deposit_for_user(vault, USER_ONE, deposit_amount);
    stop_cheat_caller_address(vault.contract_address);
}

#[test]
#[should_panic(expected: ('BELOW_MINIMUM_DEPOSIT',))]
fn deposit_below_minimum_usd_reverts() {
    let (token, vault, stonebtc, oracle) = setup_vault_suite();
    let deposit_amount = 10_u256;
    whitelist_user(token, USER_ONE);
    set_oracle_price(oracle, 1);

    mint_and_approve_stonebtc(stonebtc, USER_ONE, deposit_amount, vault.contract_address);
    let _ = deposit_for_user(vault, USER_ONE, deposit_amount);
}

#[test]
#[should_panic(expected: ('STALE_ORACLE',))]
fn deposit_with_stale_oracle_reverts() {
    let (token, vault, stonebtc, oracle) = setup_vault_suite();
    let deposit_amount = 1000_u256;
    whitelist_user(token, USER_ONE);
    set_oracle_price(oracle, 1000000);
    start_cheat_block_timestamp(oracle.contract_address, 1_u64);
    start_cheat_block_timestamp(vault.contract_address, 1862_u64);
    mint_and_approve_stonebtc(stonebtc, USER_ONE, deposit_amount, vault.contract_address);
    let _ = deposit_for_user(vault, USER_ONE, deposit_amount);
    stop_cheat_block_timestamp(oracle.contract_address);
    stop_cheat_block_timestamp(vault.contract_address);
}

#[test]
#[should_panic]
//Failure data:
//(0x45524332303a20696e73756666696369656e7420616c6c6f77616e6365 ('ERC20: insufficient allowance'), 0x454e545259504f494e545f4641494c4544 ('ENTRYPOINT_FAILED'), 0x454e545259504f494e545f4641494c4544 ('ENTRYPOINT_FAILED'))
fn deposit_without_approval_reverts() {
    let (token, vault, stonebtc, _) = setup_vault_suite();
    let deposit_amount = 1000_u256;
    whitelist_user(token, USER_ONE);

    start_cheat_caller_address(stonebtc.contract_address, OWNER);
    stonebtc.mint(USER_ONE, deposit_amount);
    stop_cheat_caller_address(stonebtc.contract_address);
    let _ = deposit_for_user(vault, USER_ONE, deposit_amount);
}

#[test]
#[should_panic(expected: ('NOT_WHITELISTED',))]
fn deposit_by_non_whitelisted_user_reverts() {
    let (_, vault, stonebtc, _) = setup_vault_suite();
    let deposit_amount = 1000_u256;

    mint_and_approve_stonebtc(stonebtc, USER_TWO, deposit_amount, vault.contract_address);
    let _ = deposit_for_user(vault, USER_TWO, deposit_amount);
}

#[test]
#[should_panic(expected: ('FEE_TOO_HIGH',))]
fn update_fee_above_max_reverts() {
    let (_, vault, _, _) = setup_vault_suite();
    start_cheat_caller_address(vault.contract_address, OWNER);
    vault.update_fee(1001);
    stop_cheat_caller_address(vault.contract_address);
}

#[test]
fn collect_fees_owner_transfers_out_and_resets_counter() {
    let (token, vault, stonebtc, _) = setup_vault_suite();
    let deposit_amount = 1000_u256;
    let expected_fee = 5_u256;

    whitelist_user(token, USER_ONE);
    mint_and_approve_stonebtc(stonebtc, USER_ONE, deposit_amount, vault.contract_address);
    let _ = deposit_for_user(vault, USER_ONE, deposit_amount);

    let treasury = USER_TWO;
    let treasury_before = stonebtc.balance_of(treasury);
    println!("treasury_before: {}", treasury_before);
    start_cheat_caller_address(vault.contract_address, OWNER);
    vault.collect_fees(treasury);
    stop_cheat_caller_address(vault.contract_address);

    let treasury_after_first = stonebtc.balance_of(treasury);
    println!("treasury_after_first: {}", treasury_after_first);
    assert(treasury_after_first - treasury_before == expected_fee, 'fee transfer mismatch');

    start_cheat_caller_address(vault.contract_address, OWNER);
    vault.collect_fees(treasury);
    stop_cheat_caller_address(vault.contract_address);
    let treasury_after_second = stonebtc.balance_of(treasury);
    println!("treasury_after_second: {}", treasury_after_second);
    assert(treasury_after_second == treasury_after_first, 'fee counter not reset');
}

#[test]
#[should_panic]
fn collect_fees_non_owner_reverts() {
    let (_, vault, _, _) = setup_vault_suite();
    start_cheat_caller_address(vault.contract_address, USER_ONE);
    vault.collect_fees(USER_ONE);
    stop_cheat_caller_address(vault.contract_address);
}

