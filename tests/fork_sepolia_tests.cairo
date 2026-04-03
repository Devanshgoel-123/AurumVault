use core::integer::u256;
use starknet::ContractAddress;
use core::num::traits::Pow;
#[starknet::interface]
pub trait IPragmaABI<TContractState> {
    fn get_decimals(self: @TContractState, data_type: DataType) -> u32;
    fn get_data_median(self: @TContractState, data_type: DataType) -> PragmaPricesResponse;
}

#[starknet::interface]
pub trait IERC20<TContractState> {
    fn name(self: @TContractState) -> ByteArray;
    fn symbol(self: @TContractState) -> ByteArray;
    fn decimals(self: @TContractState) -> u8;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
}

#[derive(Copy, Drop, Serde)]
pub enum DataType {
    SpotEntry: felt252,
}

#[derive(Copy, Drop, Serde)]
pub struct PragmaPricesResponse {
    pub price: u128,
    pub decimals: u32,
    pub last_updated: u64,
}

const PRAGMA_ORACLE: felt252 = 0x36031daa264c24520b11d93af622c848b2499b66b41d611bac95e13cfca131a;
const BTC_USD_ASSET_ID: felt252 = 18669995996566340;
const STRK_TOKEN: felt252 = 0x04718f5a0Fc34cC1AF16A1cdee98fFB20C31f5cD61D6Ab07201858f4287c938D;
const STRK_HOLDER: felt252 = 0x021a084dd1ebdf8fa827f2c89f15e95b52975101bbbdd8d2d8711fa8aae84c07;

#[test]
#[fork("SEPOLIA")]
fn test_strk_metadata() {
    let token_address: ContractAddress = STRK_TOKEN.try_into().unwrap();
    let token = IERC20Dispatcher { contract_address: token_address };

    let name = token.name();
    let symbol = token.symbol();
    let decimals = token.decimals();
    println!("name: {}", name);
    println!("symbol: {}", symbol);
    println!("decimals: {}", decimals);
    assert(name != "", 'Invalid name');
    assert(symbol != "", 'Invalid symbol');
    assert(decimals == 18, 'Wrong decimals');
}


#[test]
#[fork("SEPOLIA")]
fn test_impersonate_strk_holder() {
    let token_address: ContractAddress = STRK_TOKEN.try_into().unwrap();
    let holder: ContractAddress = STRK_HOLDER.try_into().unwrap();

    let token = IERC20Dispatcher { contract_address: token_address };

    let balance = token.balance_of(holder);
    println!("balance: {}", balance);
    assert(balance > 0, 'Holder has zero balance');
}

#[test]
#[fork("SEPOLIA")]
fn test_pragma_btc_price_sanity() {
    let oracle_address: ContractAddress = PRAGMA_ORACLE.try_into().unwrap();
    let oracle = IPragmaABIDispatcher { contract_address: oracle_address };
    let response = oracle.get_data_median(DataType::SpotEntry(BTC_USD_ASSET_ID));
    println!("response: {:?}", response.last_updated);
    let price = response.price;
    let divider = 10_u128.pow(response.decimals);
    assert(price / divider > 10_000, 'BTC price too low');
    assert(price / divider < 200_000, 'BTC price too high');
}
