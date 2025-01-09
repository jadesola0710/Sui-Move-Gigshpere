#[allow(unused_field)]
module gig_sphere::gig_sphere {
    use std::string::{String};
    use sui::balance::{Balance, zero};
    use sui::coin::{Coin, take, put, value as coin_value};
    use sui::sui::SUI;
    use sui::object::{new};
    use sui::event;



    const EINVALIDGIG: u64 = 3;   
    const EUNAUTHORIZED: u64 = 4; 

    /// Enum representing gig status
    public enum GigStatus has copy, drop, store {
        Open,
        InProgress,
        Completed,
    }

    /// User structure for storing user details
    public struct User has store {
        id: u64,              // User ID
        name: String,         // Name
        balance: Balance<SUI>, // SUI balance
        posted_gigs: vector<u64>, // User's posted gigs
        applied_gigs: vector<u64>, // User's applied gigs
    }

    /// Gig structure for storing gig details
    public struct Gig has store {
        id: u64,              // Gig ID
        description: String,  // Gig description
        payment: u64,         // Payment amount
        deadline: u64,        // Deadline for completion
        poster_id: u64,       // Poster ID
        applicant_ids: vector<u64>, // Applicant IDs
        status: GigStatus,    // Gig status
    }

    /// GigManager structure for managing users and gigs
    public struct GigManager has key, store {
    id: UID,                  // Manager ID
    balance: Balance<SUI>,    // Manager balance
    gigs: vector<Gig>,        // List of gigs
    users: vector<User>,      // List of users
    gig_count: u64,           // Number of gigs
    user_count: u64,          // Number of users
    owner: address,           // Owner address
    }


    /// Event for tracking gig posting
    public struct GigPosted has copy, drop {
        gig_id: u64,
        description: String,
        payment: u64,
    }

    /// Event for tracking gig applications
    public struct GigApplied has copy, drop {
        gig_id: u64,
        user_id: u64,
    }

    /// Event for tracking completed gigs
    public struct GigCompleted has copy, drop {
        gig_id: u64,
        applicant_id: u64,
        payment: u64,
    }

    /// Event for tracking account funding
    public struct AccountFunded has copy, drop {
        user_id: u64,
        amount: u64,
    }

    /// Event for tracking gig assignment
    public struct GigAssigned has copy, drop {
        gig_id: u64,
        assigned_to: u64,
    }

    /// Initialize the GigManager
    public entry fun create_manager(ctx: &mut TxContext) {
    let manager_uid = new(ctx);
    let manager = GigManager {
        id: manager_uid,
        balance: zero<SUI>(),
        gigs: vector::empty(),
        users: vector::empty(),
        gig_count: 0,
        user_count: 0,
        owner: tx_context::sender(ctx), // Set owner to the transaction sender
    };
    transfer::share_object(manager);
}


    /// Register a new user
    public entry fun register_user(
        manager: &mut GigManager,
        name: String,
        _ctx: &mut TxContext
    ) {
        let new_user = User {
            id: manager.user_count,
            name,
            balance: zero<SUI>(),
            posted_gigs: vector::empty(),
            applied_gigs: vector::empty(),
        };
        vector::push_back(&mut manager.users, new_user);
        manager.user_count = manager.user_count + 1;
    }

    /// Post a new gig
    public entry fun post_gig(
        manager: &mut GigManager,
        user_id: u64,
        description: String,
        payment: u64,
        deadline: u64,
        ctx: &mut TxContext
    ) {
        assert!(user_id < vector::length(&manager.users), EUNAUTHORIZED);
        let user = vector::borrow_mut(&mut manager.users, user_id);

        // Verify user's balance
        let temp_coin = take(&mut user.balance, payment, ctx);
        let user_balance_value = coin_value(&temp_coin);
        put(&mut user.balance, temp_coin);
        assert!(user_balance_value >= payment, EUNAUTHORIZED);

        // Transfer payment to manager
        let funds = take(&mut user.balance, payment, ctx);
        put(&mut manager.balance, funds);

        // Create and add new gig
        let new_gig = Gig {
            id: manager.gig_count,
            description,
            payment,
            deadline,
            poster_id: user_id,
            applicant_ids: vector::empty(),
            status: GigStatus::Open,
        };
        vector::push_back(&mut manager.gigs, new_gig);
        vector::push_back(&mut user.posted_gigs, manager.gig_count);
        manager.gig_count = manager.gig_count + 1;

        // Emit GigPosted event
        event::emit(GigPosted {
            gig_id: manager.gig_count - 1,
            description,
            payment,
        });
    }

/// Assign a gig to a user
public entry fun assign_gig(
    manager: &mut GigManager,
    gig_id: u64,
    user_id: u64,
    ctx: &mut TxContext
) {
    // Verify the caller is the owner
    assert!(manager.owner == tx_context::sender(ctx), EUNAUTHORIZED);

    // Validate gig and user IDs
    assert!(gig_id < vector::length(&manager.gigs), EINVALIDGIG);
    assert!(user_id < vector::length(&manager.users), EUNAUTHORIZED);

    let gig = vector::borrow_mut(&mut manager.gigs, gig_id);
    assert!(gig.status == GigStatus::Open, EUNAUTHORIZED);

    // Prevent assigning gig to poster
    assert!(gig.poster_id != user_id, EUNAUTHORIZED);

    // Add the user as an applicant (if not already added) and update status
    if (!vector::contains(&gig.applicant_ids, &user_id)) {
        vector::push_back(&mut gig.applicant_ids, user_id);
    };

    
    gig.status = GigStatus::InProgress;

    // Emit an event
    event::emit(GigAssigned {
        gig_id,
        assigned_to: user_id,
    });
}



    /// Fund user account
    public entry fun fund_account(
        manager: &mut GigManager,
        user_id: u64,
        coins: Coin<SUI>,
        _ctx: &mut TxContext
    ) {
        assert!(user_id < vector::length(&manager.users), EUNAUTHORIZED);
        let user = vector::borrow_mut(&mut manager.users, user_id);

        let amount = coin_value(&coins);
        put(&mut user.balance, coins);

        event::emit(AccountFunded {
            user_id,
            amount,
        });
    }

/// Complete a gig and transfer payment
public entry fun complete_gig(
    manager: &mut GigManager,
    gig_id: u64,
    applicant_id: u64,
    ctx: &mut TxContext
) {
    // Verify the caller is the owner
    assert!(manager.owner == tx_context::sender(ctx), EUNAUTHORIZED);

    // Validate gig ID
    assert!(gig_id < vector::length(&manager.gigs), EINVALIDGIG);

    let gig = vector::borrow_mut(&mut manager.gigs, gig_id);
    assert!(gig.status == GigStatus::InProgress, EUNAUTHORIZED);

    // Ensure the applicant was part of the gig
    assert!(vector::contains(&gig.applicant_ids, &applicant_id), EUNAUTHORIZED);

    // Update gig status
    gig.status = GigStatus::Completed;

    // Transfer payment to the applicant
    let payment = take(&mut manager.balance, gig.payment, ctx);
    let applicant = vector::borrow_mut(&mut manager.users, applicant_id);
    put(&mut applicant.balance, payment);

    // Emit an event
    event::emit(GigCompleted {
        gig_id,
        applicant_id,
        payment: gig.payment,
    });
}



}
