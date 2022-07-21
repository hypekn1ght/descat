import os

import pytest
from utils.utils import to_uint
from fixture.account import account_factory

TOKEN1 = to_uint(1)

# The path to the contract source code.
CONTRACT_FILE = os.path.join("contracts", "Cycle.cairo")
NUM_OF_ACCOUNTS = 4
# The testing library uses python's asyncio. So the following
# decorator and the ``async`` keyword are needed.
@pytest.mark.asyncio
@pytest.mark.parametrize('account_factory', [dict(num_signers=NUM_OF_ACCOUNTS)], indirect=True)
async def test_init_device(account_factory):
    
    (starknet, accounts, signers) = account_factory

    admin = accounts[0]
    cycle = await starknet.deploy(
        source=CONTRACT_FILE,
        constructor_calldata=[admin.contract_address]
    )

    print(f'Cycle address : {hex(cycle.contract_address)}')

    user1 = accounts[1]
    user1_signer = signers[1]

    watcher1 = accounts[2]
    watcher_signer = signers[2]

    user2 = accounts[3]
    user2_signer = signers[3]

    init_tx = await user1_signer.send_transaction(
        account=user1,
        to=cycle.contract_address,
        selector_name='init_device',
        calldata=[12342, user1.contract_address, watcher1.contract_address]
    )

    device_count_info = await cycle.device_count().call()

    assert device_count_info.result.device_count == 1

    # test cycle initiation

    # with pytest.raises(Exception) as e_info:
    #     await user2_signer.send_transaction(
    #         account=user2,
    #         to=cycle.contract_address,
    #         selector_name='init_cycle',
    #         calldata=[1]
    #     )
    # print(f'error message: {e_info}')

    await user1_signer.send_transaction(
            account=user1,
            to=cycle.contract_address,
            selector_name='init_cycle',
            calldata=[*TOKEN1]
        )
    
    cycle_count_info = await cycle.cycle_count().call()

    assert cycle_count_info.result.cycle_count == 1

    user_info = await cycle.user_cycle_count(user1.contract_address).call()

    assert user_info.result.user_cycle_count == 1

    

    




