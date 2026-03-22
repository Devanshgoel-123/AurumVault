#[starknet::component]
pub mod pausable {
    use aurumvault::pausable::errors::Errors;
    use aurumvault::pausable::interface::IPausable;
    use core::num::traits::Zero;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::access::ownable::OwnableComponent::InternalImpl;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    pub struct Storage {
        paused: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        OwnableEvent: OwnableComponent::Event,
        Paused: Paused,
        Unpaused: Unpaused,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Paused {
        #[key]
        caller: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Unpaused {
        #[key]
        caller: ContractAddress,
    }

    fn assert_non_zero_address(address: ContractAddress) {
        assert(!address.is_zero(), Errors::ZERO_ADDRESS);
    }

    #[embeddable_as(PausableImpl)]
    impl Pausable<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>,
        impl Owner: OwnableComponent::HasComponent<TContractState>
    > of IPausable<ComponentState<TContractState>> {
        fn pause(ref self: ComponentState<TContractState>) {
            let ownable = get_dep_component!(@self, Owner);
            ownable.assert_only_owner();
            self.paused.write(true);
            self.emit(Paused { caller: get_caller_address() });
        }

        fn unpause(ref self: ComponentState<TContractState>) {
            let ownable = get_dep_component!(@self, Owner);
            ownable.assert_only_owner();
            self.paused.write(false);
            self.emit(Unpaused { caller: get_caller_address() });
        }

        fn is_paused(self: @ComponentState<TContractState>) -> bool {
            self.paused.read()
        }
    }
}
