use core::integer::u256;
use starknet::ContractAddress;

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct DepositRecord {
    pub depositor: ContractAddress,
    pub stonebtc_deposited: u256,
    pub aubtc_minted: u256,
    pub timestamp: u64,
    pub deposit_count: u32,
}

#[starknet::interface]
pub trait IAurumToken<TContractState> {
    fn mint(
        ref self: TContractState, recipient: ContractAddress, amount: u256, stonebtc_amount: u256,
    );
    fn burn(ref self: TContractState, from: ContractAddress, amount: u256);
    fn add_to_whitelist(ref self: TContractState, address: ContractAddress);
    fn remove_from_whitelist(ref self: TContractState, address: ContractAddress);
    fn is_whitelisted(self: @TContractState, address: ContractAddress) -> bool;
    fn get_all_whitelisted(self: @TContractState) -> Array<ContractAddress>;
    fn get_deposit_record(self: @TContractState, address: ContractAddress) -> DepositRecord;
}
