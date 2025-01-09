#[allow(unused_field)]
module gig_sphere::gig_sphere {
    use std::string::{String};
    use sui::balance::{Balance, zero};
    use sui::coin::{Coin, take, put, value as coin_value};
    use sui::sui::SUI;
    use sui::object::{new};
    use sui::event;

    // Error codes for invalid gig and unauthorized actions
    const EINVALIDGIG: u64 = 3;   
    const EUNAUTHORIZED: u64 = 4; 

    /// Enum representing the possible statuses of a gig
    public enum GigStatus has copy, drop, store {
        Open,        
        InProgress,  
        Completed,   
    }

    /// User structure holding user-related information
    public struct User has store {
        id: u64,              
        name: String,         
        balance: Balance<SUI>, 
        posted_gigs: vector<u64>, 
        applied_gigs: vector<u64>, 
    }

    /// Gig structure holding gig-related details
    public struct Gig has store {
        id: u64,              
        description: String,  
        payment: u64,         
        deadline: u64,        
        poster_id: u64,       
        applicant_ids: vector<u64>, 
        status: GigStatus,    
    }

    /// GigManager structure for managing users, gigs, and their states
    public struct GigManager has key, store {
        id: UID,                  
        balance: Balance<SUI>,    
        gigs: vector<Gig>,        
        users: vector<User>,      
        gig_count: u64,           
        user_count: u64,          
        owner: address,           
    }

    // Event structure for tracking gig posting
    public struct GigPosted has copy, drop {
        gig_id: u64,           
        description: String,   
        payment: u64,          
    }

    // Event structure for tracking gig applications
    public struct GigApplied has copy, drop {
        gig_id: u64,           
        user_id: u64,          
    }

    // Event structure for tracking completed gigs
    public struct GigCompleted has copy, drop {
        gig_id: u64,           
        applicant_id: u64,     
        payment: u64,          
    }

    // Event structure for tracking account funding
    public struct AccountFunded has copy, drop {
        user_id: u64,          
        amount: u64,           
    }

    // Event structure for tracking gig assignment
    public struct GigAssigned has copy, drop {
        gig_id: u64,           
        assigned_to: u64,      
    }

    // Initialize the GigManager instance
    public entry fun create_manager(ctx: &mut TxContext) {
        // Generate unique ID for the manager
        let manager_uid = new(ctx);
        
        // Create a new GigManager instance
        let manager = GigManager {
            id: manager_uid,
            balance: zero<SUI>(),     
            gigs: vector::empty(),    
            users: vector::empty(),   
            gig_count: 0,             
            user_count: 0,            
            owner: tx_context::sender(ctx), 
        };
        
        // Share the GigManager object
        transfer::share_object(manager);
    }

    // Register a new user to the system
    public entry fun register_user(
        manager: &mut GigManager,
        name: String,
        _ctx: &mut TxContext
    ) {
        // Create a new User struct
        let new_user = User {
            id: manager.user_count,        
            name,                          
            balance: zero<SUI>(),          
            posted_gigs: vector::empty(),  
            applied_gigs: vector::empty(), 
        };
        
        // Add the user to the manager's users list
        vector::push_back(&mut manager.users, new_user);
        
        // Increment the user count
        manager.user_count = manager.user_count + 1;
    }

    // Post a new gig by a user
    public entry fun post_gig(
        manager: &mut GigManager,
        user_id: u64,
        description: String,
        payment: u64,
        deadline: u64,
        ctx: &mut TxContext
    ) {
        // Ensure that the user exists
        assert!(user_id < vector::length(&manager.users), EUNAUTHORIZED);
        
        // Get the user from the list
        let user = vector::borrow_mut(&mut manager.users, user_id);

        // Ensure that the user has enough funds to post the gig
        let temp_coin = take(&mut user.balance, payment, ctx);
        let user_balance_value = coin_value(&temp_coin);
        put(&mut user.balance, temp_coin);
        assert!(user_balance_value >= payment, EUNAUTHORIZED);

        // Transfer the payment to the manager
        let funds = take(&mut user.balance, payment, ctx);
        put(&mut manager.balance, funds);

        // Create a new Gig and add it to the manager's list of gigs
        let new_gig = Gig {
            id: manager.gig_count,
            description,
            payment,
            deadline,
            poster_id: user_id,
            applicant_ids: vector::empty(),
            status: GigStatus::Open, // The gig is initially open
        };
        
        // Add the gig to the gigs list and the user's posted gigs list
        vector::push_back(&mut manager.gigs, new_gig);
        vector::push_back(&mut user.posted_gigs, manager.gig_count);
        
        // Increment the gig count
        manager.gig_count = manager.gig_count + 1;

        // Emit an event for the gig being posted
        event::emit(GigPosted {
            gig_id: manager.gig_count - 1,
            description,
            payment,
        });
    }

    // User applies for a gig
    public entry fun apply_for_gig(
        manager: &mut GigManager,
        user_id: u64,
        gig_id: u64,
        _ctx: &mut TxContext
    ) {
        // Ensure that the user exists
        assert!(user_id < vector::length(&manager.users), EUNAUTHORIZED);
        
        // Ensure that the gig exists
        assert!(gig_id < vector::length(&manager.gigs), EINVALIDGIG);

        // Get the gig from the list
        let gig = vector::borrow_mut(&mut manager.gigs, gig_id);

        // Ensure the user hasn't already applied
        assert!(!vector::contains(&gig.applicant_ids, &user_id), EUNAUTHORIZED);

        // Add the user to the applicant list
        vector::push_back(&mut gig.applicant_ids, user_id);

        // Emit an event for the gig application
        event::emit(GigApplied {
            gig_id,
            user_id,
        });
    }

    // Assign a gig to a user
    public entry fun assign_gig(
        manager: &mut GigManager,
        gig_id: u64,
        user_id: u64,
        ctx: &mut TxContext
    ) {
        // Ensure the caller is the owner of the system
        assert!(manager.owner == tx_context::sender(ctx), EUNAUTHORIZED);

        // Ensure the gig and user exist
        assert!(gig_id < vector::length(&manager.gigs), EINVALIDGIG);
        assert!(user_id < vector::length(&manager.users), EUNAUTHORIZED);

        let gig = vector::borrow_mut(&mut manager.gigs, gig_id);
        
        // Ensure the gig is not assigned to the poster
        assert!(gig.poster_id != user_id, EUNAUTHORIZED);

        // Ensure that the user has applied for the gig
        assert!(vector::contains(&gig.applicant_ids, &user_id), EUNAUTHORIZED);

        // Change the gig status to InProgress
        gig.status = GigStatus::InProgress;

        // Emit an event for the gig assignment
        event::emit(GigAssigned {
            gig_id,
            assigned_to: user_id,
        });
    }

    // Fund a user's account with SUI coins
    public entry fun fund_account(
        manager: &mut GigManager,
        user_id: u64,
        coins: Coin<SUI>,
        _ctx: &mut TxContext
    ) {
        // Ensure that the user exists
        assert!(user_id < vector::length(&manager.users), EUNAUTHORIZED);

        // Get the user from the list
        let user = vector::borrow_mut(&mut manager.users, user_id);

        // Add the funds to the user's balance
        let amount = coin_value(&coins);
        put(&mut user.balance, coins);

        // Emit an event for the account funding
        event::emit(AccountFunded {
            user_id,
            amount,
        });
    }

    // Complete a gig and transfer payment to the applicant
    public entry fun complete_gig(
        manager: &mut GigManager,
        gig_id: u64,
        applicant_id: u64,
        ctx: &mut TxContext
    ) {
        // Ensure the caller is the owner of the system
        assert!(manager.owner == tx_context::sender(ctx), EUNAUTHORIZED);

        // Ensure the gig exists and is in progress
        assert!(gig_id < vector::length(&manager.gigs), EINVALIDGIG);
        let gig = vector::borrow_mut(&mut manager.gigs, gig_id);
        assert!(gig.status == GigStatus::InProgress, EUNAUTHORIZED);

        // Ensure the applicant is part of the gig
        assert!(vector::contains(&gig.applicant_ids, &applicant_id), EUNAUTHORIZED);

        // Update gig status to completed
        gig.status = GigStatus::Completed;

        // Transfer payment to the applicant
        let payment = take(&mut manager.balance, gig.payment, ctx);
        let applicant = vector::borrow_mut(&mut manager.users, applicant_id);
        put(&mut applicant.balance, payment);

        // Emit an event for the gig completion
        event::emit(GigCompleted {
            gig_id,
            applicant_id,
            payment: gig.payment,
        });
    }
}
