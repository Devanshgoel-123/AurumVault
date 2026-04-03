#[starknet::contract]
pub mod aurumtoken {
    use core::array::ArrayTrait;
    use aurumvault::aurumToken::errors::Errors;
    use aurumvault::aurumToken::interface::{DepositRecord, IAurumToken};
    use core::integer::u256;
    use core::num::traits::Zero;
    use starknet::storage::{
        Map, MutableVecTrait, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess, Vec, VecTrait,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address};
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc20::ERC20Component;

    pub const OWNER_ROLE: felt252 = selector!("OWNER_ROLE"); // Admin role for configuration
    pub const VAULT_ROLE: felt252 = selector!("VAULT_ROLE"); // Vault role for configuration

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    
    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;
    
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl AurumTokenImpl of IAurumToken<ContractState> {
        fn mint(
            ref self: ContractState, recipient: ContractAddress, amount: u256, stonebtc_amount: u256,
        ) {
            assert_only_vault(@self);
            assert_non_zero_address(recipient);
            assert_non_zero_amount(amount);
            assert_non_zero_amount(stonebtc_amount);
            assert(self.whitelist_seen.read(recipient), Errors::NOT_WHITELISTED);

            self.erc20.mint(recipient, amount);
            update_deposit_record(ref self, recipient, amount, stonebtc_amount);
            self.emit(SharesMinted { recipient, aubtc_amount: amount, stonebtc_deposited: stonebtc_amount });
        }

        fn set_vault(ref self: ContractState, new_vault: ContractAddress) {
            assert_only_owner(@self);
            assert_non_zero_address(new_vault);
            assert(new_vault != self.vault.read(), Errors::VAULT_ALREADY_SET);
            let old_vault = self.vault.read();
            self.accesscontrol._grant_role(VAULT_ROLE, new_vault);
            self.vault.write(new_vault);
            self.accesscontrol._revoke_role(VAULT_ROLE, old_vault);
            self.emit(VaultUpdated { old_vault, new_vault });
        }

        fn burn(ref self: ContractState, from: ContractAddress, amount: u256) {
            assert_only_vault(@self);
            assert_non_zero_address(from);
            assert_non_zero_amount(amount);

            self.erc20.burn(from, amount);
            self.emit(SharesBurned { from, aubtc_amount: amount });
        }

        fn add_to_whitelist(ref self: ContractState, address: ContractAddress) {
            assert_only_owner(@self);
            assert_non_zero_address(address);

            if !self.whitelist_seen.read(address) {
                self.whitelist_registry.push(address);
                self.whitelist_seen.write(address, true);
            }
            self.whitelist_seen.write(address, true);

            self.emit(WhitelistUpdated { address, approved: true });
        }

        fn remove_from_whitelist(ref self: ContractState, address: ContractAddress) {
            assert_only_owner(@self);
            assert_non_zero_address(address);

            self.whitelist_seen.write(address, false);
            self.emit(WhitelistUpdated { address, approved: false });
        }

        fn is_whitelisted(self: @ContractState, address: ContractAddress) -> bool {
            self.whitelist_seen.read(address)
        }

        fn get_all_whitelisted(self: @ContractState) -> Array<ContractAddress> {
            let mut result = array![];
            let len = self.whitelist_registry.len();
            let mut i: u64 = 0;
            while i < len {
                let address = self.whitelist_registry[i].read();
                if self.whitelist_seen.read(address) {
                    result.append(address);
                }
                i += 1;
            };

            result
        }

        fn get_deposit_record(self: @ContractState, address: ContractAddress) -> DepositRecord {
            self.deposit_records.read(address)
        }

        fn get_vault(self: @ContractState) -> ContractAddress {
            self.vault.read()
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.ownable.owner()
        }
    }

    impl ERC20HooksImpl of ERC20Component::ERC20HooksTrait<ContractState> {}

    impl ERC20ImmutableConfig of ERC20Component::ImmutableConfig {
        const DECIMALS: u8 = 18;
    }

    #[storage]
    pub struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage, // Share token state
        #[substorage(v0)]
        ownable: OwnableComponent::Storage, // Ownership state
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage, // Role management
        #[substorage(v0)]
        src5: SRC5Component::Storage, // SRC5 state
        vault: ContractAddress,
        whitelist_registry: Vec<ContractAddress>,
        whitelist_seen: Map<ContractAddress, bool>,
        deposit_records: Map<ContractAddress, DepositRecord>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        SharesMinted: SharesMinted,
        SharesBurned: SharesBurned,
        WhitelistUpdated: WhitelistUpdated,
        VaultUpdated: VaultUpdated,
    }


    #[derive(Drop, starknet::Event)]
    pub struct VaultUpdated {
        #[key]
        new_vault: ContractAddress,
        #[key]
        old_vault: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SharesMinted {
        #[key]
        recipient: ContractAddress,
        aubtc_amount: u256,
        stonebtc_deposited: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct SharesBurned {
        #[key]
        from: ContractAddress,
        aubtc_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct WhitelistUpdated {
        #[key]
        address: ContractAddress,
        approved: bool,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.ownable.initializer(owner);
        self.accesscontrol.initializer();
        self.vault.write(owner);
        self.erc20.initializer("Aurum BTC", "auBTC");
        self.accesscontrol.set_role_admin(OWNER_ROLE, OWNER_ROLE);
        self.accesscontrol.set_role_admin(VAULT_ROLE, OWNER_ROLE);
        self.accesscontrol._grant_role(OWNER_ROLE, owner);
        self.accesscontrol._grant_role(VAULT_ROLE, owner);
    }

    fn assert_only_vault(self: @ContractState) {
        let caller = get_caller_address();
        assert(self.accesscontrol.is_role_effective(VAULT_ROLE, caller), Errors::NOT_VAULT);
    }

    fn assert_only_owner(self: @ContractState) {
        let caller = get_caller_address();
        assert(caller == self.ownable.owner(), Errors::NOT_OWNER);
    }

    fn assert_non_zero_address(address: ContractAddress) {
        assert(!address.is_zero(), Errors::ZERO_ADDRESS);
    }

    fn assert_non_zero_amount(amount: u256) {
        assert(!amount.is_zero(), Errors::ZERO_AMOUNT);
    }

    fn update_deposit_record(
        ref self: ContractState, recipient: ContractAddress, aubtc_amount: u256, stonebtc_amount: u256,
    ) {
        let mut record = self.deposit_records.read(recipient);
        record.depositor = recipient;
        record.stonebtc_deposited = record.stonebtc_deposited + stonebtc_amount;
        record.aubtc_minted = record.aubtc_minted + aubtc_amount;
        record.timestamp = get_block_timestamp();
        record.deposit_count = record.deposit_count + 1_u32;
        self.deposit_records.write(recipient, record);
    }
}
