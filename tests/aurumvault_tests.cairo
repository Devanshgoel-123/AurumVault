use aurumvault::aurumToken::interface::{
    DepositRecord, IAurumTokenDispatcher, IAurumTokenDispatcherTrait,
};
use aurumvault::pragma::pragma::{IPragmaABIDispatcher, IPragmaABIDispatcherTrait};
use aurumvault::vault::interface::{IVaultDispatcher, IVaultDispatcherTrait};
use core::array::ArrayTrait;
use core::felt252;
use core::integer::u256;
use core::num::traits::Pow;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    start_cheat_caller_address_global, stop_cheat_caller_address, stop_cheat_caller_address_global,
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

#[test]
fn deposit_mints_shares_and_matches_formula() {
    let (token, vault, stonebtc, _) = setup_vault_suite();
    let deposit_amount = 1000_u256;
    let expected_net_assets = 995_u256;
    let expected_shares = expected_net_assets * 10_u256.pow(10);

    let token_erc20 = IERC20LikeDispatcher { contract_address: token.contract_address };

    start_cheat_caller_address(stonebtc.contract_address, OWNER);
    stonebtc.mint(USER_ONE, deposit_amount);
    stop_cheat_caller_address(stonebtc.contract_address);
    println!("minted: {}", deposit_amount);
    println!("expected: {}", expected_shares);
    start_cheat_caller_address(stonebtc.contract_address, USER_ONE);
    let approved = stonebtc.approve(vault.contract_address, deposit_amount);
    stop_cheat_caller_address(stonebtc.contract_address);
    assert(approved, 'approve failed');
    println!("approved: {}", approved);

    start_cheat_caller_address(vault.contract_address, USER_ONE);
    let minted = vault.deposit(deposit_amount);
    stop_cheat_caller_address(vault.contract_address);

    assert(minted == expected_shares, 'share formula mismatch');
    assert(token_erc20.balance_of(USER_ONE) == expected_shares, 'aubtc balance mismatch');
    assert(vault.total_assets() == expected_net_assets, 'net assets mismatch');
}


