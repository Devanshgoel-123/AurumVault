/// A mock price oracle that returns configurable prices for testing.
#[starknet::contract]
pub mod MockPriceOracle {
    use aurumvault::pragma::pragma::{DataType, IPragmaABI, PragmaPricesResponse};
    use starknet::get_block_timestamp;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        price: felt252,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.price.write(1000000_u128.into());
    }

    #[starknet::interface]
    pub trait IMockPriceOracle<TContractState> {
        fn set_price(ref self: TContractState, price: felt252);
    }

    #[abi(embed_v0)]
    impl MockPriceOracleSetImpl of IMockPriceOracle<ContractState> {
        fn set_price(ref self: ContractState, price: felt252) {
            self.price.write(price);
        }
    }

    #[abi(embed_v0)]
    impl MockPriceOracleImpl of IPragmaABI<ContractState> {
        fn get_decimals(self: @ContractState, data_type: DataType) -> u32 {
            8_u32
        }

        fn get_data_median(self: @ContractState, data_type: DataType) -> PragmaPricesResponse {
            let price = self.price.read();
            let price_u128: u128 = price.try_into().unwrap();
            return PragmaPricesResponse {
                price: price_u128,
                decimals: 8_u32,
                last_updated: get_block_timestamp(),
                num_sources_aggregated: 1_u32,
                expiration_timestamp: None,
            };
        }
    }
}
