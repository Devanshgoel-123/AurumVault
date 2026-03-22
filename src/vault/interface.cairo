use core::integer::u256;
use starknet::ContractAddress;
#[starknet::interface]
pub trait IVault<TContractState> {
    fn deposit(ref self: TContractState, amount: u256) -> u256;
    fn redeem(ref self: TContractState, amount: u256) -> u256;
    fn collect_fees(ref self: TContractState, recipient: ContractAddress);
    fn update_fee(ref self: TContractState, new_fee: u16);
    //Read functions 
    fn total_assets(self: @TContractState) -> u256;
    fn total_supply(self: @TContractState) -> u256;
    fn convert_to_shares(self: @TContractState, assets: u256) -> u256;
    fn convert_to_assets(self: @TContractState, shares: u256) -> u256;
    fn get_tvl_usd(self: @TContractState) -> u256;
}