use aurumvault::aurumToken::interface::{IAurumTokenDispatcher, IAurumTokenDispatcherTrait};
use core::integer::u256;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyTrait,
    EventsFilterTrait, declare, spy_events, start_cheat_caller_address,
    start_cheat_caller_address_global, stop_cheat_caller_address, stop_cheat_caller_address_global,
};
use starknet::ContractAddress;

const OWNER: ContractAddress = 0x1001.try_into().unwrap();
const VAULT: ContractAddress = 0x2002.try_into().unwrap();
const USER_ONE: ContractAddress = 0x3003.try_into().unwrap();
const USER_TWO: ContractAddress = 0x4004.try_into().unwrap();
const ZERO_ADDRESS: ContractAddress = 0.try_into().unwrap();

#[starknet::interface]
trait IERC20Like<TContractState> {
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
}

// fn deploy_token(owner: ContractAddress, vault: ContractAddress) -> IAurumTokenDispatcher {
//     start_cheat_caller_address_global(owner);
//     let contract = declare("aurumtoken").unwrap().contract_class();
//     let constructor_calldata = array![];
//     let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
//     stop_cheat_caller_address_global();

//     IAurumTokenDispatcher { contract_address }
// }

// #[test]
// fn deploys_with_mock_vault_and_owner() {
//     let token = deploy_token(OWNER, VAULT);
//     start_cheat_caller_address(token.contract_address, OWNER);
//     token.set_vault(VAULT);
//     stop_cheat_caller_address(token.contract_address);
//     assert(token.get_vault() == VAULT, 'Vault Mismatch');
//     assert(token.get_owner() == OWNER, 'Owner Mismatch');
// }

// #[test]
// fn add_to_whitelist_sets_active_and_emits_correct_key() {
//     let token = deploy_token(OWNER, VAULT);
//     start_cheat_caller_address(token.contract_address, OWNER);
//     token.set_vault(VAULT);
//     stop_cheat_caller_address(token.contract_address);
//     let mut spy = spy_events();
//     start_cheat_caller_address(token.contract_address, OWNER);
//     token.add_to_whitelist(USER_ONE);
//     stop_cheat_caller_address(token.contract_address);

//     assert(token.is_whitelisted(USER_ONE), 'not whitelisted');

//     let token_events = spy.get_events().emitted_by(token.contract_address);
//     assert(token_events.events.len() == 1_usize, 'event missing');

//     for (_, event) in token_events.events.span() {
//         assert(event.keys.len() == 2_usize, 'bad key count');
//         let expected_key: felt252 = USER_ONE.into();
//         assert(*event.keys.at(1_usize) == expected_key, 'wrong key');
//         assert(*event.data.at(0_usize) == 1, 'approved mismatch');
//     };
// }

// #[test]
// fn remove_from_whitelist_marks_inactive_and_keeps_only_active_addresses() {
//     let token = deploy_token(OWNER, VAULT);

//     start_cheat_caller_address(token.contract_address, OWNER);
//     token.add_to_whitelist(USER_ONE);
//     token.add_to_whitelist(USER_TWO);
//     token.remove_from_whitelist(USER_ONE);
//     stop_cheat_caller_address(token.contract_address);

//     assert(!token.is_whitelisted(USER_ONE), 'still active');
//     assert(token.is_whitelisted(USER_TWO), 'user two inactive');

//     let active = token.get_all_whitelisted();
//     assert(active.len() == 1, 'active size mismatch');

//     let mut has_user_two = false;
//     for address in active.span() {
//         if *address == USER_TWO {
//             has_user_two = true;
//         };
//         assert(*address != USER_ONE, 'inactive returned');
//     };
//     assert(has_user_two, 'active missing');
// }

// #[test]
// fn mint_as_vault_updates_balance_and_deposit_record() {
//     let token = deploy_token(OWNER, VAULT);
//     let erc20 = IERC20LikeDispatcher { contract_address: token.contract_address };

//     start_cheat_caller_address(token.contract_address, OWNER);
//     token.add_to_whitelist(USER_ONE);
//     stop_cheat_caller_address(token.contract_address);

//     let aubtc_amount = u256 { low: 1000, high: 0 };
//     let stonebtc_amount = u256 { low: 500, high: 0 };

//     start_cheat_caller_address(token.contract_address, VAULT);
//     token.mint(USER_ONE, aubtc_amount, stonebtc_amount);
//     stop_cheat_caller_address(token.contract_address);

//     assert(erc20.balance_of(USER_ONE) == aubtc_amount, 'minted balance bad');

//     let record = token.get_deposit_record(USER_ONE);
//     assert(record.depositor == USER_ONE, 'depositor mismatch');
//     assert(record.aubtc_minted == aubtc_amount, 'mint amount mismatch');
//     assert(record.stonebtc_deposited == stonebtc_amount, 'stone amount mismatch');
//     assert(record.deposit_count == 1_u32, 'deposit count mismatch');
// }

// #[test]
// #[should_panic(expected: ('ZERO_AMOUNT',))]
// fn mint_zero_amount_reverts_with_zero_amount() {
//     let token = deploy_token(OWNER, VAULT);

//     start_cheat_caller_address(token.contract_address, OWNER);
//     token.add_to_whitelist(USER_ONE);
//     stop_cheat_caller_address(token.contract_address);

//     let zero_amount = u256 { low: 0, high: 0 };
//     let stonebtc_amount = u256 { low: 500, high: 0 };

//     start_cheat_caller_address(token.contract_address, VAULT);
//     token.mint(USER_ONE, zero_amount, stonebtc_amount);
// }

// #[test]
// #[should_panic(expected: ('ZERO_ADDRESS',))]
// fn mint_to_zero_address_reverts_with_zero_address() {
//     let token = deploy_token(OWNER, VAULT);
//     let zero_address: ContractAddress = ZERO_ADDRESS;
//     let aubtc_amount = u256 { low: 1000, high: 0 };
//     let stonebtc_amount = u256 { low: 500, high: 0 };

//     start_cheat_caller_address(token.contract_address, VAULT);
//     token.mint(zero_address, aubtc_amount, stonebtc_amount);
// }

// #[test]
// #[should_panic(expected: ('NOT_VAULT',))]
// fn mint_as_non_vault_reverts_with_not_vault() {
//     let token = deploy_token(OWNER, VAULT);
//     start_cheat_caller_address(token.contract_address, OWNER);
//     token.add_to_whitelist(USER_ONE);
//     stop_cheat_caller_address(token.contract_address);

//     let aubtc_amount = u256 { low: 1000, high: 0 };
//     let stonebtc_amount = u256 { low: 500, high: 0 };

//     start_cheat_caller_address(token.contract_address, USER_TWO);
//     token.mint(USER_ONE, aubtc_amount, stonebtc_amount);
// }

// #[test]
// #[should_panic(expected: ('NOT_WHITELISTED',))]
// fn mint_to_non_whitelisted_reverts_with_not_whitelisted() {
//     let token = deploy_token(OWNER, VAULT);
//     let aubtc_amount = u256 { low: 1000, high: 0 };
//     let stonebtc_amount = u256 { low: 500, high: 0 };

//     start_cheat_caller_address(token.contract_address, VAULT);
//     token.mint(USER_TWO, aubtc_amount, stonebtc_amount);
// }

// #[test]
// fn burn_shares_updates_balance_and_emits_correct_event() {
//     let token = deploy_token(OWNER, VAULT);
//     let erc20 = IERC20LikeDispatcher { contract_address: token.contract_address };

//     start_cheat_caller_address(token.contract_address, OWNER);
//     token.add_to_whitelist(USER_ONE);
//     stop_cheat_caller_address(token.contract_address);

//     let aubtc_amount = u256 { low: 1000, high: 0 };
//     let stonebtc_amount = u256 { low: 500, high: 0 };
//     let mut spy = spy_events();
//     start_cheat_caller_address(token.contract_address, VAULT);
//     token.mint(USER_ONE, aubtc_amount, stonebtc_amount);
//     stop_cheat_caller_address(token.contract_address);

//     assert(erc20.balance_of(USER_ONE) == aubtc_amount, 'minted balance bad');

//     start_cheat_caller_address(token.contract_address, VAULT);
//     token.burn(USER_ONE, aubtc_amount);
//     stop_cheat_caller_address(token.contract_address);

//     assert(erc20.balance_of(USER_ONE) == 0, 'burned balance bad');

//     let token_events = spy.get_events().emitted_by(token.contract_address);
//     assert(token_events.events.len() == 4, 'event missing');
//     let mut found_mint = false;
//     let mut found_burn = false;
//     let events = token_events.events;
//     let mut i = 0;
//     while i < events.len() {
//         let (_, event) = events.at(i);

//         // SharesMinted → keys.len() == 2 AND data.len() == 4
//         if event.data.len() == 4 {
//             found_mint = true;

//             assert(*event.data.at(0) == aubtc_amount.low.into(), 'mint low mismatch');
//             assert(*event.data.at(1) == aubtc_amount.high.into(), 'mint high mismatch');
//             assert(*event.data.at(2) == stonebtc_amount.low.into(), 'stonebtc low mismatch');
//             assert(*event.data.at(3) == stonebtc_amount.high.into(), 'stonebtc high mismatch');
//         }

//         if event.data.len() == 2 {
//             found_burn = true;

//             assert(*event.data.at(0) == aubtc_amount.low.into(), 'burn low mismatch');
//             assert(*event.data.at(1) == aubtc_amount.high.into(), 'burn high mismatch');
//         }

//         i += 1;
//     }
//     assert(found_mint, 'mint event not found');
//     assert(found_burn, 'burn event not found');
// }
