use starknet::ContractAddress;
use core::array::Array;

#[starknet::interface]
pub trait IStrimz<TContractState> {  
    fn add_supported_token(ref self: TContractState, token_address: ContractAddress) -> bool;
    fn remove_supported_token(ref self: TContractState, token_address: ContractAddress) -> bool;
    fn is_token_supported(self: @TContractState, token_address: ContractAddress) -> bool;
    fn get_supported_tokens(self: @TContractState) -> Array<ContractAddress>;
    fn get_user_token_balance(
        self: @TContractState, user: ContractAddress, token: ContractAddress
    ) -> u256;
    fn get_user_all_balances(
        self: @TContractState, user: ContractAddress
    ) -> (Array<ContractAddress>, Array<u256>);
    fn deposit_token(
        ref self: TContractState, token_address: ContractAddress, amount: u256
    );
    fn withdraw_token(
        ref self: TContractState, token_address: ContractAddress, amount: u256
    ) -> u256;
    // fn get_balance(self: @TContractState, user_address: ContractAddress) -> u256;
    fn subscribe_to_plan(ref self: TContractState, plan: u32) -> bool;
    fn unsubscribe_from_plan(ref self: TContractState, plan: u32) -> bool;
    fn create_single_stream(
        ref self: TContractState,
        recipient: ContractAddress,
        amount: u256,
        interval: Strimz::Interval,
        start_time: u64,
        token: ContractAddress,
    ) -> u32;
    fn create_multiple_streams(
        ref self: TContractState,
        recipients: Array<ContractAddress>,
        amounts: Array<u256>,
        interval: Strimz::Interval,
        start_time: u64,
        token: ContractAddress,
    ) -> Array<u32>;
    //when streaming one payment
    fn stream_one(
        ref self: TContractState,
        address: ContractAddress,
        token: ContractAddress,
        recipient: ContractAddress,
        amount: u256,
        
    );
    //when streaming multiple payments
    fn stream_multiple(
        ref self: TContractState, token: ContractAddress, recipients: Array<ContractAddress>, amounts: Array<u256>,
    );
    fn edit_stream(ref self: TContractState, stream_id: u32, amount: u256) -> bool;
    fn delete_stream(ref self: TContractState, stream_id: u32) -> bool;
    fn pay_utility(
        ref self: TContractState,
        utility: u32,
        address: ContractAddress,
        amount: u256,
        interval: Strimz::Interval,
        start_time: u64,
        token: ContractAddress,
    ) -> bool;

    fn get_user_streams(self: @TContractState, user: ContractAddress) -> Array<u32>;
    fn get_user_utilities(self: @TContractState, user: ContractAddress) -> Array<u32>;
    fn has_utility(self: @TContractState, user: ContractAddress, utility: u32) -> bool;
    fn cancel_utility(ref self: TContractState, utility: u32) -> bool;

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
        streams: Map<u32, Stream>,
        user_streams: Map<ContractAddress, u32>,
        next_stream_id: u32,
        user_stream_count: Map<ContractAddress, u32>, // Track number of streams per user
        user_stream_at_index: Map<(ContractAddress, u32), u32>, // Maps (user, index) -> stream_id
        user_utilities: Map<(ContractAddress, u32), bool>, // Maps (user, utility) -> is_active
        utility_stream_id: Map<(ContractAddress, u32), u32>, // Maps (user, utility) -> stream_id
        supported_tokens: Map<ContractAddress, bool>,
        supported_tokens_list: Map<u32, ContractAddress>,
        supported_tokens_count: u32,
        user_token_balances: Map<(ContractAddress, ContractAddress), u256>, // (user, token) -> balance
          
       
    } 
   


    const PLAN_BRONZE: u32 = 0;
    const PLAN_SILVER: u32 = 1;
    const PLAN_GOLD: u32 = 2;

    const BRONZE_PRICE: u256 = 100000000000000000; // 0.1 STRK
    const SILVER_PRICE: u256 = 200000000000000000; // 0.2 STRK
    const GOLD_PRICE: u256 = 300000000000000000; // 0.3 STRK

    #[derive(Copy, Drop, Clone, Serde, starknet::Store)]
    #[allow(starknet::store_no_default_variant)]
    pub enum Interval {
        Daily,
        Weekly,
        BiWeekly,
        Monthly,
    }
    #[derive(Copy, Drop, Serde, starknet::Store)]
    pub struct Stream {
        id: u32,
        sender: ContractAddress,
        recipient: ContractAddress,
        amount: u256,
        interval: Interval,
        active: bool,
        start_time: u64,
        token: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        DepositSuccessiful: DepositSuccessiful,
        PlanActivated: PlanActivated,
        PlanDeactivated: PlanDeactivated,
        StreamCreated: StreamCreated,
        StreamEdited: StreamEdited,
        StreamDeleted: StreamDeleted,
        WithdrawSuccessful: WithdrawSuccessful,
        TokenAdded: TokenAdded,
        TokenRemoved: TokenRemoved,
    }

    #[derive(Drop, starknet::Event)]
    pub struct DepositSuccessiful {
        #[key]
        pub user_address: ContractAddress,
        pub amount: u256,
        pub token: ContractAddress,
        pub new_balance: u256,
        
    }
    #[derive(Drop, starknet::Event)]
    pub struct PlanActivated {
        #[key]
        pub plan: u32,
        pub address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PlanDeactivated {
        #[key]
        pub plan: u32,
        pub address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct StreamCreated {
        #[key]
        stream_id: u32,
        sender: ContractAddress,
        recipient: ContractAddress,
        amount: u256,
        start_time: u64,
        token: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct StreamEdited {
        #[key]
        stream_id: u32,
        new_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct StreamDeleted {
        #[key]
        stream_id: u32,
    }

    #[derive(Drop, starknet::Event)]
    pub struct WithdrawSuccessful {
        #[key]
        pub user_address: ContractAddress,
        pub amount: u256,
        pub remaining_balance: u256,
        pub token: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TokenAdded {
        #[key]
        token_address: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    pub struct TokenRemoved {
        #[key]
        token_address: ContractAddress
    }

    #[derive(Copy, Drop, Clone, Serde, PartialEq)]
    enum Utility {
        gas,
        Electricity,
        Water,
        data,
        airtime,
    }


    #[constructor]
    fn constructor(ref self: ContractState) {      
        self.supported_tokens_count.write(0);

        let strk = contract_address_const::<0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>();
        self._add_token(strk);
        // Initialize plan prices
        self.plan_prices.write(PLAN_BRONZE, BRONZE_PRICE);
        self.plan_prices.write(PLAN_SILVER, SILVER_PRICE);
        self.plan_prices.write(PLAN_GOLD, GOLD_PRICE);
    }


    #[abi(embed_v0)]
    impl StrimzImpl of super::IStrimz<ContractState> {
        fn deposit_token(
            ref self: ContractState, token_address: ContractAddress, amount: u256
        ) {
            self._assert_token_supported(token_address);
            
            let user = get_caller_address();
            let contract_address = get_contract_address();
            
            // Transfer tokens from user to contract
            self._transfer_from(token_address, user, contract_address, amount);
            
            // Update user's token balance
            let current_balance = self.user_token_balances.read((user, token_address));
            let new_balance = current_balance + amount;
            self.user_token_balances.write((user, token_address), new_balance);
            
            self.emit(DepositSuccessiful{ user_address: user, token: token_address, amount, new_balance });
        }


        fn withdraw_token(
            ref self: ContractState, token_address: ContractAddress, amount: u256
        ) -> u256 {
            self._assert_token_supported(token_address);
            
            let user = get_caller_address();
            let balance = self.user_token_balances.read((user, token_address));
            assert(balance >= amount, 'Insufficient balance');
            
            // Update balance before transfer
            self.user_token_balances.write(
                (user, token_address), balance - amount
            );
            
            // Transfer tokens to user
            self._transfer(token_address, user, amount);
            let remaining_balance =self.user_token_balances.read((user, token_address));
            
            self.emit(WithdrawSuccessful { user_address: user, amount, remaining_balance, token: token_address});

            remaining_balance
            
        }

        fn add_supported_token(
            ref self: ContractState, token_address: ContractAddress
        ) -> bool {          
            assert(!self.supported_tokens.read(token_address), 'Token already supported');
            self._add_token(token_address);
            true
        }

        fn remove_supported_token(
            ref self: ContractState, token_address: ContractAddress
        ) -> bool {          
            assert(self.supported_tokens.read(token_address), 'Token not supported');
            self.supported_tokens.write(token_address, false);
            self.emit(TokenRemoved { token_address });
            true
        }

        fn is_token_supported(
            self: @ContractState, token_address: ContractAddress
        ) -> bool {
            self.supported_tokens.read(token_address)
        }

        fn get_supported_tokens(self: @ContractState) -> Array<ContractAddress> {
            let mut tokens = ArrayTrait::new();
            let count = self.supported_tokens_count.read();
            
            let mut i: u32 = 0;
            loop {
                if i >= count {
                    break;
                }
                let token = self.supported_tokens_list.read(i);
                if self.supported_tokens.read(token) {
                    tokens.append(token);
                }
                i += 1;
            };
            
            tokens
        }

        fn get_user_token_balance(
            self: @ContractState, user: ContractAddress, token: ContractAddress
        ) -> u256 {
            self.user_token_balances.read((user, token))
        }

        fn get_user_all_balances(
            self: @ContractState, user: ContractAddress
        ) -> (Array<ContractAddress>, Array<u256>) {
            let mut tokens = ArrayTrait::new();
            let mut balances = ArrayTrait::new();
            
            let count = self.supported_tokens_count.read();
            let mut i: u32 = 0;
            
            loop {
                if i >= count {
                    break;
                }
                let token = self.supported_tokens_list.read(i);
                if self.supported_tokens.read(token) {
                    let balance = self.user_token_balances.read((user, token));
                    tokens.append(token);
                    balances.append(balance);
                }
                i += 1;
            };
            
            (tokens, balances)
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

        fn unsubscribe_from_plan(ref self: ContractState, plan: u32) -> bool {
            let user_address = get_caller_address();
            self.plan_status.write((user_address, plan), false);

            self.emit(PlanDeactivated { plan: plan, address: user_address });

            false
        }

        fn create_single_stream(
            ref self: ContractState,
            recipient: ContractAddress,
            amount: u256,
            interval: Interval,
            start_time: u64,
            token: ContractAddress
        ) -> u32 {
            let user_address = get_caller_address();
            // let user_balance: u256 = self.user_balance.read(user_address);
            // assert(user_balance >= amount, 'insufficient balance');

            // Create new stream
            let stream_id = self.next_stream_id.read();
            let stream = Stream {
                id: stream_id,
                sender: user_address,
                recipient: recipient,
                amount: amount,
                interval: interval,
                active: true,
                start_time: start_time,
                token: token,
            };

            self.streams.write(stream_id, stream);

            // Add stream_id to user's streams using the index mapping
            let current_count = self.user_stream_count.read(user_address);
            self.user_stream_at_index.write((user_address, current_count), stream_id);
            self.user_stream_count.write(user_address, current_count + 1);

            // Increment stream id
            self.next_stream_id.write(stream_id + 1);

            // Emit event
            self
                .emit(
                    StreamCreated {
                        stream_id, sender: user_address, recipient, amount, start_time, token
                    },
                );

            stream_id
        }

        fn create_multiple_streams(
            ref self: ContractState,
            recipients: Array<ContractAddress>,
            amounts: Array<u256>,
            interval: Interval,
            start_time: u64,
            token: ContractAddress,
        ) -> Array<u32> {
            // Validate arrays have same length
            assert(recipients.len() == amounts.len(), 'arrays length mismatch');

            let user_address = get_caller_address();
            let mut total_amount: u256 = 0;

            // Track created stream IDs
            let mut created_stream_ids = ArrayTrait::new();

            // Calculate total amount for all streams
            let mut i: u32 = 0;
            loop {
                if i >= amounts.len() {
                    break;
                }
                total_amount += *amounts[i];
                i += 1;
            };

            // Create streams for each recipient
            let mut j: u32 = 0;

            loop {
                if j >= recipients.len() {
                    break;
                }

                // Create individual stream
                let stream_id = self.next_stream_id.read();
                let stream = Stream {
                    id: stream_id,
                    sender: user_address,
                    recipient: *recipients[j],
                    amount: *amounts[j],
                    interval: interval,
                    active: true,
                    start_time: start_time,
                    token: token,
                };

                self.streams.write(stream_id, stream);

                // Track stream for user
                let current_count = self.user_stream_count.read(user_address);
                self.user_stream_at_index.write((user_address, current_count), stream_id);
                self.user_stream_count.write(user_address, current_count + 1);

                // Add stream ID to return array
                created_stream_ids.append(stream_id);

                // Emit event for this stream
                self
                    .emit(
                        StreamCreated {
                            stream_id,
                            sender: user_address,
                            recipient: *recipients[j],
                            amount: *amounts[j],
                            start_time: start_time,
                            token: token,
                        },
                    );

                // Increment stream id
                self.next_stream_id.write(stream_id + 1);
                j += 1;
            };

            // Return array of all created stream IDs
            created_stream_ids
        }

        fn stream_one(
            ref self: ContractState,
            address: ContractAddress,
            token: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) {
            let user_address = get_caller_address();
            let user_balance: u256 = self.user_balance.read(user_address);
            assert(user_balance >= amount, 'insufficient balance');
            self._transfer(token, recipient, amount);
        }

        fn stream_multiple(
            ref self: ContractState, token: ContractAddress, recipients: Array<ContractAddress>, amounts: Array<u256>,
        ) {
            // Validate arrays have same length
            assert(recipients.len() == amounts.len(), 'arrays length mismatch');

            let user_address = get_caller_address();
            let mut total_amount: u256 = 0;

            // Calculate total amount needed
            let mut i: u32 = 0;
            loop {
                if i >= amounts.len() {
                    break;
                }
                total_amount += *amounts[i];
                i += 1;
            };

            // Verify user has sufficient balance for all transfers
            let user_balance: u256 = self.user_balance.read(user_address);
            assert(user_balance >= total_amount, 'insufficient total balance');

            // Process each transfer
            let mut j: u32 = 0;
            loop {
                if j >= recipients.len() {
                    break;
                }
                self._transfer(token, *recipients[j], *amounts[j]);
                j += 1;
            }
        }

        fn edit_stream(ref self: ContractState, stream_id: u32, amount: u256) -> bool {
            let caller = get_caller_address();

            // Read existing stream
            let mut stream = self.streams.read(stream_id);
            assert(stream.sender == caller, 'Not stream owner');
            assert(stream.active, 'Stream not active');

            // Update amount
            stream.amount = amount;
            self.streams.write(stream_id, stream);

            self.emit(StreamEdited { stream_id, new_amount: amount });

            true
        }

        fn delete_stream(ref self: ContractState, stream_id: u32) -> bool {
            let caller = get_caller_address();

            // Read existing stream
            let mut stream = self.streams.read(stream_id);
            assert(stream.sender == caller, 'Not stream owner');
            assert(stream.active, 'Stream already inactive');

            // Deactivate stream
            stream.active = false;
            self.streams.write(stream_id, stream);

            self.emit(StreamDeleted { stream_id });

            true
        }

        fn get_user_streams(self: @ContractState, user: ContractAddress) -> Array<u32> {
            let mut streams = ArrayTrait::new();
            let count = self.user_stream_count.read(user);

            let mut i: u32 = 0;
            loop {
                if i >= count {
                    break;
                }
                let stream_id = self.user_stream_at_index.read((user, i));
                streams.append(stream_id);
                i += 1;
            };

            streams
        }

        fn pay_utility(
            ref self: ContractState,
            utility: u32,
            address: ContractAddress,
            amount: u256,
            interval: Interval,
            start_time: u64,
            token: ContractAddress,
            
        ) -> bool {
            let user = get_caller_address();

            // Check if utility payment already exists
            let has_utility = self.user_utilities.read((user, utility));
            assert(!has_utility, 'Utility payment exists');

            // Create a stream for utility payment
            let stream_id = self.create_single_stream(address, amount, interval, start_time, token);

            // Map utility to user and store stream ID
            self.user_utilities.write((user, utility), true);
            self.utility_stream_id.write((user, utility), stream_id);

            true
        }

        fn get_user_utilities(self: @ContractState, user: ContractAddress) -> Array<u32> {
            let mut utilities = ArrayTrait::new();
            let mut i: u32 = 0;

            // Iterate through possible utilities
            // Assuming utilities are numbered 0-3 based on your enum
            loop {
                if i >= 4 {
                    break;
                }
                if self.user_utilities.read((user, i)) {
                    utilities.append(i);
                }
                i += 1;
            };

            utilities
        }

        fn has_utility(self: @ContractState, user: ContractAddress, utility: u32) -> bool {
            self.user_utilities.read((user, utility))
        }

        fn cancel_utility(ref self: ContractState, utility: u32) -> bool {
            let user = get_caller_address();

            // Check if utility payment exists
            let has_utility = self.user_utilities.read((user, utility));
            assert(has_utility, 'No utility payment found');

            // Get the associated stream ID
            let stream_id = self.utility_stream_id.read((user, utility));

            // Cancel the stream
            self.delete_stream(stream_id);

            // Remove utility mapping
            self.user_utilities.write((user, utility), false);

            true
        }
    }


    #[generate_trait]
    impl ERC20Impl of ERC20Trait {
        fn _transfer_from(
            ref self: ContractState,
            token: ContractAddress,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) {
            let token_dispatcher = IERC20Dispatcher { contract_address: token };
            
            assert(token_dispatcher.balance_of(sender) >= amount, 'insufficient funds');
            let contract_address = get_contract_address();
            
            assert(
                token_dispatcher.allowance(sender, contract_address) >= amount,
                'insufficient allowance',
            );

            let success = token_dispatcher.transfer_from(sender, recipient, amount);
            assert(success, 'ERC20 transfer_from failed!');
        }

        fn _transfer(
            ref self: ContractState, token: ContractAddress, recipient: ContractAddress, amount: u256
        ) {
            let token_dispatcher = IERC20Dispatcher { contract_address: token };
            let success = token_dispatcher.transfer(recipient, amount);
            assert(success, 'ERC20 transfer failed!');
        }
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn _add_token(ref self: ContractState, token_address: ContractAddress) {
            let count = self.supported_tokens_count.read();
            self.supported_tokens.write(token_address, true);
            self.supported_tokens_list.write(count, token_address);
            self.supported_tokens_count.write(count + 1);
            
            self.emit(TokenAdded { token_address });
        }

        fn _assert_token_supported(self: @ContractState, token_address: ContractAddress) {
            assert(self.supported_tokens.read(token_address), 'Token not supported');
        }
    }
}
