use starknet::ContractAddress;

#[starknet::interface]
pub trait IStrimz<TContractState> {
    fn deposit(ref self: TContractState, amount: u256);
    fn get_balance(self: @TContractState, user_address: ContractAddress) -> u256;
    fn subscribe_to_plan(ref self: TContractState, plan: u32) -> bool;
    fn unsubscribe_from_plan(ref self: TContractState, plan: u32) -> bool;
    //when streaming one payment
    fn stream_one(ref self: TContractState, address: ContractAddress) -> bool;
    //when streaming multiple payments
    fn stream_multiple(ref self: TContractState, address: ContractAddress) -> bool;
    fn edit_stream(ref self: TContractState, address: ContractAddress, amount: u32) -> bool;
    fn delete_stream(ref self: TContractState, stream_id: u32) -> bool;
    fn pay_utility(
        ref self: TContractState,
        utility: u32,
        address: ContractAddress,
        amount: u32,
        interval: u32,
    ) -> bool;
    // fn _get_plan_enum(ref self: TContractState, plan: u32) -> Plan;
}


#[starknet::contract]
pub mod Strimz {
    use core::starknet::storage::{Map};
    use starknet::{
        ContractAddress, contract_address_const, get_caller_address, get_contract_address,
    };
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use core::starknet::storage::{
        StorageMapReadAccess, StorageMapWriteAccess, StoragePointerWriteAccess,
        StoragePointerReadAccess,
    };

    #[storage]
    struct Storage {
        user_balance: Map<ContractAddress, u256>,
        user_plan: Map<ContractAddress, u32>,
        plan_prices: Map<u32, u256>,
        plan_status: Map<(ContractAddress, u32), bool>,
    }


    const PLAN_BRONZE: u32 = 0;
    const PLAN_SILVER: u32 = 1;
    const PLAN_GOLD: u32 = 2;

    const BRONZE_PRICE: u256 = 100000000000000000; // 0.1 STRK
    const SILVER_PRICE: u256 = 200000000000000000; // 0.2 STRK
    const GOLD_PRICE: u256 = 300000000000000000; // 0.3 STRK


    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        DepositSuccessiful: DepositSuccessiful,
        PlanActivated: PlanActivated,
    }

    #[derive(Drop, starknet::Event)]
    pub struct DepositSuccessiful {
        #[key]
        pub user_address: ContractAddress,
        pub amount: u256,
        pub new_balance: u256,
    }
    #[derive(Drop, starknet::Event)]
    pub struct PlanActivated {
        #[key]
        pub plan: u32,
        pub address: ContractAddress,
    }

    #[derive(Copy, Drop, Clone, Serde, PartialEq)]
    enum Utility {
        gas,
        Electricity,
        Water,
        wifi,
    }

    #[derive(Copy, Drop, Clone, Serde, PartialEq)]
    enum Interval {
        daily,
        weekly,
        bi_weekly,
        monthly,
    }
   
    #[constructor]
    fn constructor(ref self: ContractState) {
        // Initialize plan prices
        self.plan_prices.write(PLAN_BRONZE, BRONZE_PRICE);
        self.plan_prices.write(PLAN_SILVER, SILVER_PRICE);
        self.plan_prices.write(PLAN_GOLD, GOLD_PRICE);
    }


    #[abi(embed_v0)]
    impl StrimzImpl of super::IStrimz<ContractState> {
        fn deposit(ref self: ContractState, amount: u256) {
            let user_address = get_caller_address();
            let contract_address = get_contract_address();
            self._transfer_from(user_address, contract_address, amount);
            let current_balance = self.user_balance.read(user_address);
            let new_balance = current_balance + amount;
            self.user_balance.write(user_address, new_balance);

            self
                .emit(
                    DepositSuccessiful {
                        user_address: user_address, amount: amount, new_balance: new_balance,
                    },
                )
        }
        fn get_balance(self: @ContractState, user_address: ContractAddress) -> u256 {
            let user_balance = self.user_balance.read(user_address);
            user_balance
        }

        fn subscribe_to_plan(ref self: ContractState, plan: u32) -> bool {
            let user_address = get_caller_address();

            let current_plan_status = self.plan_status.read((user_address, plan));
            assert(!current_plan_status, 'Plan already active');
            let user_balance = self.user_balance.read(user_address);

            let plan_price = self.plan_prices.read(plan);
            assert(user_balance >= plan_price, 'Insufficient balance');

            self.user_balance.write(user_address, user_balance - plan_price);

            self.user_plan.write(user_address, plan);
            self.plan_status.write((user_address, plan), true);

            // Emit event
            self.emit(PlanActivated { plan: plan, address: user_address });

            true
        }

        

        // fn _get_plan_enum(plan: u32) -> Plan {
        //     match plan {
        //         0 => Plan::Bronze,
        //         1 => Plan::Silver,
        //         2 => Plan::Gold,
        //         _ => panic_with_felt252('Invalid plan')
        //     }
        // }
    }


    #[generate_trait]
    impl ERC20Impl of ERC20Trait {
        fn _transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) {
            let eth_dispatcher = IERC20Dispatcher {
                contract_address: contract_address_const::<
                    0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d,
                >() // STRK token Contract Address
            };

            assert(eth_dispatcher.balance_of(sender) >= amount.into(), 'insufficient funds');
            let caller = get_caller_address();
            let contract_address = get_contract_address();
            eth_dispatcher.approve(caller, amount);

            assert(
                eth_dispatcher.allowance(sender, contract_address) >= amount.into(),
                'insufficient allowance',
            );

            let success = eth_dispatcher.transfer_from(sender, recipient, amount.into());
            assert(success, 'ERC20 transfer_from failed!');
        }
        fn check_allowance(self: @ContractState, owner: ContractAddress) -> u256 {
            let eth_dispatcher = IERC20Dispatcher {
                contract_address: contract_address_const::<
                    0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d,
                >(),
            };
            let contract_address = get_contract_address();
            eth_dispatcher.allowance(owner, contract_address)
        }

        fn _transfer(ref self: ContractState, recipient: ContractAddress, amount: u128) {
            let eth_dispatcher = IERC20Dispatcher {
                contract_address: contract_address_const::<
                    0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d,
                >() // STRK token Contract Address
            };
            let success = eth_dispatcher.transfer(recipient, amount.into());
            assert(success, 'ERC20 transfer failed!');
        }
    }
}
