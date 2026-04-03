#[starknet::contract]
pub mod vault {
    use aurumvault::aurumToken::interface::{IAurumTokenDispatcher, IAurumTokenDispatcherTrait};
    use aurumvault::pausable::interface::IPausable;
    use aurumvault::pausable::pausable::pausable as PausableComponent;
    use aurumvault::pragma::pragma::{DataType, IPragmaABIDispatcher, IPragmaABIDispatcherTrait};
    use aurumvault::vault::errors::Errors;
    use aurumvault::vault::interface::IVault;
    use core::integer::u256;
    use core::num::traits::{Pow, Zero};
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::interfaces::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address, get_contract_address};

    pub const OWNER_ROLE: felt252 = selector!("OWNER_ROLE");
    pub const MINIMUM_DEPOSIT_IN_USD: u256 = 10_u256.pow(6);
    // ───────── Constants ─────────
    const HALF_HOUR_IN_SECONDS: u64 = 1800;
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;

    #[storage]
    pub struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage, // Ownership state
        #[substorage(v0)]
        pausable: PausableComponent::Storage, // Pausable state
        stonebtc_address: ContractAddress,
        aurum_token_address: ContractAddress,
        oracle_address: ContractAddress,
        deposit_fee: u16,
        accumulated_fees: u256,
        minimum_deposit_in_usd: u256,
        btc_usd_asset_id: felt252,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        OwnableEvent: OwnableComponent::Event,
        PausableEvent: PausableComponent::Event,
        Deposited: Deposited,
        Redeemed: Redeemed,
        FeeUpdated: FeeUpdated,
        FeesCollected: FeesCollected,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Deposited {
        #[key]
        depositor: ContractAddress,
        stonebtc_in: u256,
        fee_taken: u256,
        aubtc_minted: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Redeemed {
        #[key]
        redeemer: ContractAddress,
        aubtc_burned: u256,
        stonebtc_out: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct FeeUpdated {
        old_fee_bps: u16,
        new_fee_bps: u16,
    }

    #[derive(Drop, starknet::Event)]
    pub struct FeesCollected {
        #[key]
        recipient: ContractAddress,
        amount: u256,
    }


    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        stonebtc_address: ContractAddress,
        aurum_token_address: ContractAddress,
        oracle_address: ContractAddress,
        deposit_fee: u16,
        minimum_deposit_in_usd: u256,
        btc_usd_asset_id: felt252,
    ) {
        assert_non_zero_address(owner);
        assert_non_zero_address(stonebtc_address);
        assert_non_zero_address(aurum_token_address);
        assert_non_zero_address(oracle_address);
        assert(deposit_fee <= 1000, Errors::FEE_TOO_HIGH);
        assert(minimum_deposit_in_usd > MINIMUM_DEPOSIT_IN_USD, Errors::BELOW_MIN_DEPOSIT);
        self.ownable.initializer(owner);
        self.stonebtc_address.write(stonebtc_address);
        self.aurum_token_address.write(aurum_token_address);
        self.oracle_address.write(oracle_address);
        self.deposit_fee.write(deposit_fee);
        self.minimum_deposit_in_usd.write(minimum_deposit_in_usd);
        self.btc_usd_asset_id.write(btc_usd_asset_id);
    }

    #[abi(embed_v0)]
    impl VaultImpl of IVault<ContractState> {
        fn deposit(ref self: ContractState, amount: u256) -> u256 {
            assert_not_paused(@self);
            assert_non_zero_address(get_caller_address());
            assert_non_zero_amount(amount);
            let price_in_usd = get_btc_usd_price(@self);
            // let price_in_usd = 100000_u128;
            let asset_value_in_usd = get_asset_value_in_usd(@self, amount, price_in_usd);
            assert(
                asset_value_in_usd >= self.minimum_deposit_in_usd.read(), Errors::BELOW_MIN_DEPOSIT,
            );
            let caller = get_caller_address();
            let stone_btc_dispatcher = ERC20ABIDispatcher {
                contract_address: self.stonebtc_address.read(),
            };
            let stonebtc_balance = stone_btc_dispatcher.balance_of(caller);
            assert(stonebtc_balance >= amount, Errors::INSUFFICIENT_ASSETS);
            let fee_bps: u256 = self.deposit_fee.read().into();
            let fee = amount * fee_bps / 10000_u256;
            let net_amount = amount - fee;
            let shares_to_mint = self.convert_to_shares(net_amount);
            assert(stone_btc_dispatcher.transfer_from(caller, get_contract_address(), amount), Errors::TRANSFER_FAILED);
            self.accumulated_fees.write(self.accumulated_fees.read() + fee);
            let aubtc_dispatcher = IAurumTokenDispatcher {
                contract_address: self.aurum_token_address.read(),
            };
            aubtc_dispatcher.mint(caller, shares_to_mint, net_amount);
            self
                .emit(
                    Deposited {
                        depositor: caller,
                        stonebtc_in: amount,
                        fee_taken: fee,
                        aubtc_minted: shares_to_mint,
                    },
                );
            return shares_to_mint;
        }

        fn redeem(ref self: ContractState, amount: u256) -> u256 {
            assert_not_paused(@self);
            assert_non_zero_address(get_caller_address());
            assert_non_zero_amount(amount);
            let caller = get_caller_address();
            let erc20 = ERC20ABIDispatcher {
                contract_address: self.aurum_token_address.read(),
            };
            let aubtc_balance = erc20.balance_of(caller);
            assert(aubtc_balance >= amount, Errors::INSUFFICIENT_SHARES);
            let aubtc_dispatcher = IAurumTokenDispatcher {
                contract_address: self.aurum_token_address.read(),
            };
            let stonebtc_amount_to_return = self.convert_to_assets(amount);
            aubtc_dispatcher.burn(caller, amount);
            let stonebtc_dispatcher = ERC20ABIDispatcher {
                contract_address: self.stonebtc_address.read(),
            };
            assert(stonebtc_dispatcher.transfer(caller, stonebtc_amount_to_return), Errors::TRANSFER_FAILED);
            self
                .emit(
                    Redeemed {
                        redeemer: caller,
                        aubtc_burned: amount,
                        stonebtc_out: stonebtc_amount_to_return,
                    },
                );
            return stonebtc_amount_to_return;
        }

        fn collect_fees(ref self: ContractState, recipient: ContractAddress) {
            assert_non_zero_address(recipient);
            assert_only_owner(@self);
            let fee = self.accumulated_fees.read();
            self.accumulated_fees.write(0);
            let stonebtc_dispatcher = ERC20ABIDispatcher {
                contract_address: self.stonebtc_address.read(),
            };
            assert(stonebtc_dispatcher.transfer(recipient, fee), Errors::TRANSFER_FAILED);
            self.emit(FeesCollected { recipient, amount: fee });
        }

        fn update_fee(ref self: ContractState, new_fee: u16) {
            assert_only_owner(@self);
            assert_not_paused(@self);
            assert(new_fee <= 1000, Errors::FEE_TOO_HIGH);
            let old_fee = self.deposit_fee.read();
            self.deposit_fee.write(new_fee);
            self.emit(FeeUpdated { old_fee_bps: old_fee, new_fee_bps: new_fee });
        }


        //View Functions
        fn total_assets(self: @ContractState) -> u256 {
            let stonebtc_dispatcher = ERC20ABIDispatcher {
                contract_address: self.stonebtc_address.read(),
            };
            let stonebtc_balance = stonebtc_dispatcher.balance_of(get_contract_address());
            return stonebtc_balance - self.accumulated_fees.read();
        }

        fn total_supply(self: @ContractState) -> u256 {
            let aubtc_dispatcher = ERC20ABIDispatcher {
                contract_address: self.aurum_token_address.read(),
            };
            let aubtc_balance = aubtc_dispatcher.total_supply();
            return aubtc_balance;
        }

        fn convert_to_shares(self: @ContractState, assets: u256) -> u256 {
            let total_assets = self.total_assets();
            let total_supply = self.total_supply();
            if total_supply == 0 {
                return assets * 10_u256.pow(10);
            } else {
                return mul_div_down(assets, total_supply, total_assets);
            }
        }

        fn convert_to_assets(self: @ContractState, shares: u256) -> u256 {
            let total_assets = self.total_assets();
            let total_supply = self.total_supply();
            assert(total_supply > 0, Errors::ZERO_SUPPLY_AUBTC);
            return mul_div_down(shares, total_assets, total_supply);
        }

        fn get_tvl_usd(self: @ContractState) -> u256 {
            let price_in_usd = get_btc_usd_price(self);
            let asset_value_in_usd = get_asset_value_in_usd(self, self.total_assets(), price_in_usd);
            return asset_value_in_usd;
        }
    }

    fn assert_non_zero_address(address: ContractAddress) {
        assert(!address.is_zero(), Errors::ZERO_ADDRESS);
    }

    fn assert_only_owner(self: @ContractState) {
        let caller = get_caller_address();
        assert(caller == self.ownable.owner(), Errors::NOT_OWNER);
    }

    fn get_btc_usd_price(self: @ContractState) -> u128 {
        let pragma_dispatcher = IPragmaABIDispatcher {
            contract_address: self.oracle_address.read(),
        };
        let price = pragma_dispatcher
            .get_data_median(DataType::SpotEntry(self.btc_usd_asset_id.read()));
        assert(price.expiration_timestamp.is_none(), Errors::STALE_ORACLE);
        let current_timestamp = get_block_timestamp();
        assert(
            price.last_updated >= current_timestamp - HALF_HOUR_IN_SECONDS,
            Errors::STALE_ORACLE,
        );
        return price.price;
    }

    fn get_asset_value_in_usd(self: @ContractState, amount: u256, price_in_usd: u128) -> u256 {
        let price_in_usd: u256 = price_in_usd.into();
        let divider = 10_u256.pow(8);
        let price_in_usd = price_in_usd / divider;
        return mul_div_down(amount, price_in_usd, divider);
    }

    fn mul_div_down(x: u256, y: u256, denominator: u256) -> u256 {
        assert(!denominator.is_zero(), Errors::ZERO_AMOUNT);
        return (x * y) / denominator;
    }

    fn assert_non_zero_amount(amount: u256) {
        assert(!amount.is_zero(), Errors::ZERO_AMOUNT);
    }

    fn assert_not_paused(self: @ContractState) {
        assert(!self.pausable.is_paused(), Errors::PAUSED);
    }
}
