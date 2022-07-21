# SPDX-License-Identifier: MIT
%lang starknet
%builtins pedersen range_check ecdsa

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.starknet.common.syscalls import (get_contract_address, get_caller_address)
from starkware.cairo.common.uint256 import ( Uint256, uint256_add, uint256_sub, uint256_eq )
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.serialize import serialize_word

from openzeppelin.access.ownable import Ownable
from openzeppelin.security.safemath import SafeUint256
from onlydust.stream.default_implementation import stream

# cycle represents each mindfullness session
struct Cycle:
    member score : felt # 0 - 100
    member start_time : Uint256
    member end_time : Uint256
    member owner : felt
end

# user struct stores user device identifier and cycle count for user
struct User: 
    member user_device : felt
    member cycle_count : felt
end

# Event of a new device has been initiated
@event
func init_device_called(user_address: felt):
end

# Event of a new cycle starting
@event
func init_cycle_called(cycle_id: felt, user_address: felt):
end

# Event of a cycle ending
@event
func end_cycle_called(cycle_id: felt):
end

# Cycles stored here
@storage_var
func stored_cycles_storage(cycle_id: felt) -> (cycle: Cycle):
end

# Cycle counter for reference
@storage_var
func cycle_count_storage() -> (cycle_count: felt):
end

# Device Count
@storage_var
func device_count_storage() -> (device_count: felt):
end

# User data storage, new elements initiated from init_device
@storage_var
func user_data_storage(address: felt) -> (user_data: User):
end

# Mapping for watcher to user address 
@storage_var
func watcher_reference_storage(watcher: felt) -> (address: felt):
end

# array for cycle ids based on user address and user's cycle index
@storage_var
func user_cycles(address: felt, index: felt) -> (cycle_id: felt):
end

# Last Cycle ending time for all users
@storage_var
func last_cycle_storage(address: felt) -> (last_time: Uint256):
end

# Refresh period before users can start another cycle
@storage_var
func refresh_period_storage() -> (refresh_period: Uint256):
end

@constructor
func constructor{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(owner: felt):
    Ownable.initializer(owner)
    return()
end

@view
func stored_cycles{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(ID: felt) -> (cycle: Cycle):
    let (cycle) = stored_cycles_storage.read(ID)
    return (cycle)
end

@view
func user_cycle_count{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(address: felt) -> (user_cycle_count: felt):
    let (user_data) = user_data_storage.read(address)
    return (user_cycle_count=user_data.cycle_count)
end


@view
func cycle_count{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (cycle_count: felt):
    let (cycle_count) = cycle_count_storage.read()
    return (cycle_count)
end

@view
func device_count{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (device_count: felt):
    let (device_count) = device_count_storage.read()
    return (device_count)
end

@view
func last_cycle_end{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(address: felt) -> (LastTime: Uint256):
    let (LastTime) = last_cycle_storage.read(address)
    return (LastTime)
end

@view
func refresh_period{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }() -> (refresh_period: Uint256):
    let (refresh_period) = refresh_period_storage.read()
    return(refresh_period)
end

@external
func set_refresh_period{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(refresh_period: Uint256) -> ():
    Ownable.assert_only_owner()
    refresh_period_storage.write(refresh_period)
    return()
end


@external
func init_device{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(user_device: felt, user_address: felt, watcher_address: felt) -> ():
    let new_user = User(
        user_device=user_device,
        cycle_count=0
    )
    let (device_count) = device_count_storage.read()
    let new_count = device_count + 1
    device_count_storage.write(new_count)

    user_data_storage.write(user_address, new_user)
    watcher_reference_storage.write(watcher_address, user_address)

    init_device_called.emit(user_address)
    return()
end

@external
func init_cycle{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(start_time: Uint256) -> (cycle_id: felt):
    alloc_locals
    let (caller_address) = get_caller_address()
    with_attr error_message("address hasn't been initiated"):
        let (watcher_address) = watcher_reference_storage.read(caller_address)
    end

    # init new cycle data with data passed in from mobile device
    let new_cycle = Cycle(
        score=0,
        start_time=start_time,
        end_time=Uint256(0,0),
        owner=caller_address
    )

    let (current_cycle_count) = cycle_count_storage.read()
    let new_cycle_count = current_cycle_count + 1
    cycle_count_storage.write(new_cycle_count)
    
    stored_cycles_storage.write(new_cycle_count, new_cycle)

    # get user data
    let (user_data) = user_data_storage.read(caller_address)

    # increment cycle count in user data
    let new_user_data = User(
        user_device=user_data.user_device,
        cycle_count=user_data.cycle_count + 1
    )
    # write incremented user cycle count in storage
    user_data_storage.write(caller_address, new_user_data)

    return(new_cycle_count)
end

@external
func end_cycle{
        syscall_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr
    }(cycle_id: felt, score: felt, end_time: Uint256) -> ():
    alloc_locals
    let (watcher_address) = get_caller_address()
    let (cycle_data) = stored_cycles_storage.read(cycle_id)
    let (supposed_user_address) = watcher_reference_storage.read(watcher_address)

    with_attr error_message("invalid watcher is closing the cycle"):
        assert cycle_data.owner = supposed_user_address
    end

    with_attr error_message("end time has been set"):
        uint256_eq(Uint256(0,0), cycle_data.end_time)
    end

    # set end time and score in cycle data
    let new_cycle_data = Cycle(
            score=score,
            start_time=cycle_data.start_time,
            end_time=end_time,
            owner=supposed_user_address
    )

    stored_cycles_storage.write(cycle_id, new_cycle_data)
    return ()
end