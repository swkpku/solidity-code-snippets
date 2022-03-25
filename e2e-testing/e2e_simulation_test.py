import pytest

import csv

from brownie import *
from accounts import *
from helpers import *
from simulation_helpers import *

class Contracts: pass


def setAddresses(contracts):
    contracts.sortedTroves.setParams(
        MAX_BYTES_32,
        contracts.troveManager.address,
        contracts.borrowerOperations.address,
        { 'from': accounts[0] }
    )

    contracts.troveManager.setAddresses(
        contracts.borrowerOperations.address,
        contracts.activePool.address,
        contracts.defaultPool.address,
        contracts.stabilityPool.address,
        contracts.gasPool.address,
        contracts.collSurplusPool.address,
        contracts.priceFeedTestnet.address,
        contracts.lusdToken.address,
        contracts.sortedTroves.address,
        contracts.lqtyToken.address,
        contracts.lqtyStaking.address,
        { 'from': accounts[0] }
    )

    contracts.borrowerOperations.setAddresses(
        contracts.troveManager.address,
        contracts.activePool.address,
        contracts.defaultPool.address,
        contracts.stabilityPool.address,
        contracts.gasPool.address,
        contracts.collSurplusPool.address,
        contracts.priceFeedTestnet.address,
        contracts.sortedTroves.address,
        contracts.lusdToken.address,
        contracts.lqtyStaking.address,
        { 'from': accounts[0] }
    )

    contracts.stabilityPool.setAddresses(
        contracts.borrowerOperations.address,
        contracts.troveManager.address,
        contracts.activePool.address,
        contracts.lusdToken.address,
        contracts.sortedTroves.address,
        contracts.priceFeedTestnet.address,
        contracts.communityIssuance.address,
        { 'from': accounts[0] }
    )

    contracts.activePool.setAddresses(
        contracts.borrowerOperations.address,
        contracts.troveManager.address,
        contracts.stabilityPool.address,
        contracts.defaultPool.address,
        { 'from': accounts[0] }
    )

    contracts.defaultPool.setAddresses(
        contracts.troveManager.address,
        contracts.activePool.address,
        { 'from': accounts[0] }
    )

    contracts.collSurplusPool.setAddresses(
        contracts.borrowerOperations.address,
        contracts.troveManager.address,
        contracts.activePool.address,
        { 'from': accounts[0] }
    )

    contracts.hintHelpers.setAddresses(
        contracts.sortedTroves.address,
        contracts.troveManager.address,
        { 'from': accounts[0] }
    )

    # LQTY
    contracts.lqtyStaking.setAddresses(
        contracts.lqtyToken.address,
        contracts.lusdToken.address,
        contracts.troveManager.address,
        contracts.borrowerOperations.address,
        contracts.activePool.address,
        { 'from': accounts[0] }
    )

    contracts.communityIssuance.setAddresses(
        contracts.lqtyToken.address,
        contracts.stabilityPool.address,
        { 'from': accounts[0] }
    )

def oneCollSetAddresses(base_contracts, contracts, coll_address, decimal_adjustment):
    base_contracts.lqtyToken.unlockFunction(0, { 'from': accounts[0] })
    base_contracts.lqtyToken.addCommunityIssuanceAddress(contracts.communityIssuance, { 'from': accounts[0] })
    base_contracts.lqtyToken.unlockFunction(2, { 'from': accounts[0] })
    base_contracts.lqtyToken.transferToNewCommunityIssuanceContract(contracts.communityIssuance.address, Wei(100000e18), { 'from': accounts[0] })

    contracts.communityIssuance.setAddresses(
        base_contracts.lqtyToken.address,
        contracts.stabilityPool.address,
        { 'from': accounts[0] }
    )
    
    contracts.sortedTroves.setParams(
        MAX_BYTES_32,
        contracts.troveManager.address,
        contracts.borrowerOperations.address,
        { 'from': accounts[0] }
    )

    contracts.troveManager.setAddresses(
        contracts.borrowerOperations.address,
        contracts.activePool.address,
        contracts.defaultPool.address,
        contracts.stabilityPool.address,
        contracts.gasPool.address,
        contracts.collSurplusPool.address,
        contracts.priceFeedTestnet.address,
        base_contracts.lusdToken.address,
        contracts.sortedTroves.address,
        base_contracts.lqtyToken.address,
        coll_address,
        accounts[0], # _poolAdminAddress
        decimal_adjustment, # collDecimalAdjustment
        { 'from': accounts[0] }
    )

    contracts.troveManager.setAdminParams(
        Wei(1000000e24), # debt ceiling
        base_contracts.feeForwarder.address,
        { 'from': accounts[0] }
    )

    contracts.borrowerOperations.setAddresses(
        contracts.troveManager.address,
        contracts.activePool.address,
        contracts.defaultPool.address,
        contracts.stabilityPool.address,
        contracts.gasPool.address,
        contracts.collSurplusPool.address,
        contracts.priceFeedTestnet.address,
        contracts.sortedTroves.address,
        base_contracts.lusdToken.address,
        coll_address,
        accounts[0], # _poolAdminAddress
        decimal_adjustment, # collDecimalAdjustment
        { 'from': accounts[0] }
    )

    contracts.borrowerOperations.setBorrowingFeePoolAddress(
        accounts[0], # _poolAdminAddress
        { 'from': accounts[0] }
    )

    contracts.stabilityPool.setAddresses(
        contracts.borrowerOperations.address,
        contracts.troveManager.address,
        contracts.activePool.address,
        base_contracts.lusdToken.address,
        contracts.sortedTroves.address,
        contracts.priceFeedTestnet.address,
        contracts.communityIssuance.address,
        coll_address,
        decimal_adjustment,
        { 'from': accounts[0] }
    )

    contracts.activePool.setAddresses(
        contracts.borrowerOperations.address,
        contracts.troveManager.address,
        contracts.stabilityPool.address,
        contracts.defaultPool.address,
        contracts.collSurplusPool.address,
        coll_address,
        { 'from': accounts[0] }
    )

    contracts.defaultPool.setAddresses(
        contracts.troveManager.address,
        contracts.activePool.address,
        coll_address,
        { 'from': accounts[0] }
    )

    contracts.collSurplusPool.setAddresses(
        contracts.borrowerOperations.address,
        contracts.troveManager.address,
        contracts.activePool.address,
        coll_address,
        { 'from': accounts[0] }
    )

    contracts.hintHelpers.setAddresses(
        contracts.sortedTroves.address,
        contracts.troveManager.address,
        decimal_adjustment, # collDecimalAdjustment
        { 'from': accounts[0] }
    )

    base_contracts.lusdToken.unlockFunction(0, { 'from': accounts[0] })

    base_contracts.lusdToken.addAddressesForColl(
        contracts.troveManager.address,
        contracts.stabilityPool.address,
        contracts.borrowerOperations.address,
        { 'from': accounts[0] }
    )

@pytest.fixture
def add_accounts():
    if network.show_active() != 'development':
        print("Importing accounts...")
        import_accounts(accounts)


@pytest.fixture
def contracts():
    contracts = Contracts()

    contracts.priceFeedTestnet = PriceFeedTestnet.deploy({ 'from': accounts[0] })
    contracts.sortedTroves = SortedTroves.deploy({ 'from': accounts[0] })
    contracts.troveManager = TroveManager.deploy({ 'from': accounts[0] })
    contracts.activePool = ActivePool.deploy({ 'from': accounts[0] })
    contracts.stabilityPool = StabilityPool.deploy({ 'from': accounts[0] })
    contracts.gasPool = GasPool.deploy({ 'from': accounts[0] })
    contracts.defaultPool = DefaultPool.deploy({ 'from': accounts[0] })
    contracts.collSurplusPool = CollSurplusPool.deploy({ 'from': accounts[0] })
    contracts.borrowerOperations = BorrowerOperationsTester.deploy({ 'from': accounts[0] })
    contracts.hintHelpers = HintHelpers.deploy({ 'from': accounts[0] })
    contracts.lusdToken = LUSDToken.deploy(
        contracts.troveManager.address,
        contracts.stabilityPool.address,
        contracts.borrowerOperations.address,
        { 'from': accounts[0] }
    )
    # LQTY
    contracts.lqtyStaking = LQTYStaking.deploy({ 'from': accounts[0] })
    contracts.communityIssuance = CommunityIssuance.deploy({ 'from': accounts[0] })
    contracts.lockupContractFactory = LockupContractFactory.deploy({ 'from': accounts[0] })
    contracts.lqtyToken = LQTYToken.deploy(
        contracts.communityIssuance.address,
        contracts.lqtyStaking.address,
        contracts.lockupContractFactory.address,
        accounts[0], # bountyAddress
        accounts[0],  # lpRewardsAddress
        { 'from': accounts[0] }
    )

    setAddresses(contracts)

    return contracts

def setupBaseContracts():
    contracts = Contracts()
    contracts.lusdToken = LUSDToken.deploy({ 'from': accounts[0] })
    contracts.unipool = Unipool.deploy({ 'from': accounts[0] }) # we use unipool as fake contract for lqtyToken constructor
    contracts.feeForwarder = FeeForwarder.deploy({ 'from': accounts[0] }) # TODO: Test fee forward logics
    contracts.lockupContractFactory = LockupContractFactory.deploy({ 'from': accounts[0] })
    contracts.lqtyToken = LQTYToken.deploy(
        contracts.unipool.address, # _intialSetupAddress
        contracts.unipool.address, # _lpRewardsAddress
        accounts[0], # _multisigAddress
        contracts.unipool.address, # _communityMultisigAddress
        contracts.unipool.address, # _teamVestingAddress
        contracts.unipool.address, # _ecosystemPartnerVestingAddress
        contracts.unipool.address, # _treasuryAddress
        contracts.unipool.address, # _investorMultisig
        { 'from': accounts[0] }
    )

    # Mint collateral tokens to accounts
    default_coll_balance = 10000000
    contracts.coll_1 = ERC20Mock.deploy("Coll1", "COLL1", 18, accounts[0],  floatToWei(default_coll_balance * len(accounts)), { 'from': accounts[0] })
    contracts.coll_2 = ERC20Mock.deploy("Coll2", "COLL2", 8, accounts[0],  floatToWei(default_coll_balance * len(accounts)), { 'from': accounts[0] })
    contracts.coll_3 = ERC20Mock.deploy("Coll3", "COLL3", 6, accounts[0],  floatToWei(default_coll_balance * len(accounts)), { 'from': accounts[0] })

    for idx, account in enumerate(accounts):
        if idx == 0:
            continue
        contracts.coll_1.transfer(account, floatToWei(default_coll_balance),  { 'from': accounts[0] })
        contracts.coll_2.transfer(account, floatToWei(default_coll_balance),  { 'from': accounts[0] })
        contracts.coll_3.transfer(account, floatToWei(default_coll_balance),  { 'from': accounts[0] })

    return contracts

def setupOneCollateralContracts(coll_contract, base_contracts, decimal_adjustment):
    contracts = Contracts()

    contracts.priceFeedTestnet = PriceFeedTestnet.deploy({ 'from': accounts[0] })
    contracts.sortedTroves = SortedTroves.deploy({ 'from': accounts[0] })
    contracts.troveManager = TroveManager.deploy({ 'from': accounts[0] })
    contracts.activePool = ActivePool.deploy({ 'from': accounts[0] })
    contracts.stabilityPool = StabilityPool.deploy({ 'from': accounts[0] })
    contracts.gasPool = GasPool.deploy({ 'from': accounts[0] })
    contracts.defaultPool = DefaultPool.deploy({ 'from': accounts[0] })
    contracts.collSurplusPool = CollSurplusPool.deploy({ 'from': accounts[0] })
    contracts.borrowerOperations = BorrowerOperationsTester.deploy({ 'from': accounts[0] })
    contracts.hintHelpers = HintHelpers.deploy({ 'from': accounts[0] })
    contracts.communityIssuance = CommunityIssuance.deploy({ 'from': accounts[0] })
    contracts.coll = coll_contract
    contracts.lusdToken = base_contracts.lusdToken
    contracts.lqtyToken = base_contracts.lqtyToken
    
    oneCollSetAddresses(base_contracts, contracts, coll_contract.address, decimal_adjustment)

    return contracts

@pytest.fixture
def multi_coll_contracts():
    base_contracts = setupBaseContracts()

    multi_coll_contracts = {}    
    multi_coll_contracts["coll_1"] = setupOneCollateralContracts(base_contracts.coll_1, base_contracts, 1)
    multi_coll_contracts["coll_2"] = setupOneCollateralContracts(base_contracts.coll_2, base_contracts, 1e10)
    multi_coll_contracts["coll_3"] = setupOneCollateralContracts(base_contracts.coll_3, base_contracts, 1e12)

    return multi_coll_contracts

@pytest.fixture
def print_expectations():
    # ether_price_one_year = price_ether_initial * (1 + drift_ether)**8760
    # print("Expected ether price at the end of the year: $", ether_price_one_year)
    print("Expected LQTY price at the end of first month: $", price_LQTY_initial * (1 + drift_LQTY)**720)

    print("\n Open troves")
    print("E(Q_t^e)    = ", collateral_gamma_k * collateral_gamma_theta)
    print("SD(Q_t^e)   = ", collateral_gamma_k**(0.5) * collateral_gamma_theta)
    print("E(CR^*(i))  = ", (target_cr_a + target_cr_b * target_cr_chi_square_df) * 100, "%")
    print("SD(CR^*(i)) = ", target_cr_b * (2*target_cr_chi_square_df)**(1/2) * 100, "%")
    print("E(tau)      = ", rational_inattention_gamma_k * rational_inattention_gamma_theta * 100, "%")
    print("SD(tau)     = ", rational_inattention_gamma_k**(0.5) * rational_inattention_gamma_theta * 100, "%")
    print("\n")

def _test_test(contracts):
    print(len(accounts))
    contracts.borrowerOperations.openTrove(Wei(1e18), floatToWei(100), Wei(2000e18), ZERO_ADDRESS, ZERO_ADDRESS,
                                           { 'from': accounts[1] })

    #assert False

def test_liquidation_with_no_SP_deposit(add_accounts, multi_coll_contracts, print_expectations):
    contracts_eth = multi_coll_contracts["coll_1"]
    contracts_btc = multi_coll_contracts["coll_2"]
    LUSD_GAS_COMPENSATION_ETH = contracts_eth.troveManager.LUSD_GAS_COMPENSATION() / 1e18
    MIN_NET_DEBT_ETH = contracts_eth.troveManager.MIN_NET_DEBT() / 1e18
    LUSD_GAS_COMPENSATION_BTC = contracts_btc.troveManager.LUSD_GAS_COMPENSATION() / 1e18
    MIN_NET_DEBT_BTC = contracts_btc.troveManager.MIN_NET_DEBT() / 1e18

    contracts_eth.priceFeedTestnet.setPrice(floatToWei(price_ether[0]), { 'from': accounts[0] })
    print("set up the ETH price feed")
    contracts_btc.priceFeedTestnet.setPrice(floatToWei(50000), { 'from': accounts[0] })
    print("set up the BTC price feed")
    # eth whale
    whale_coll_eth = 30000.0
    contracts_eth.coll.approve(contracts_eth.borrowerOperations.address, floatToWei(whale_coll_eth), { 'from': accounts[0] })
    print("approved for the eth coll")
    contracts_eth.borrowerOperations.openTrove(MAX_FEE, Wei(10e24), floatToWei(whale_coll_eth), ZERO_ADDRESS, ZERO_ADDRESS, { 'from': accounts[0] })
    contracts_eth.stabilityPool.provideToSP(floatToWei(stability_initial), ZERO_ADDRESS, { 'from': accounts[0] })

    # btc whale
    whale_coll_btc = 1
    contracts_btc.coll.approve(contracts_btc.borrowerOperations.address, floatToWei(whale_coll_btc, 1e8), { 'from': accounts[0] })
    print("approved for the btc coll")
    contracts_btc.borrowerOperations.openTrove(MAX_FEE, Wei(30000e18), floatToWei(whale_coll_btc, 1e8), ZERO_ADDRESS, ZERO_ADDRESS, { 'from': accounts[0] })
    # contracts_btc.stabilityPool.provideToSP(floatToWei(stability_initial/10), ZERO_ADDRESS, { 'from': accounts[0] })

    # btc whale
    coll_btc_2 = 1
    contracts_btc.coll.approve(contracts_btc.borrowerOperations.address, floatToWei(coll_btc_2, 1e8), { 'from': accounts[1] })
    print("approved for the btc coll")
    contracts_btc.borrowerOperations.openTrove(MAX_FEE, Wei(20000e18), floatToWei(coll_btc_2, 1e8), ZERO_ADDRESS, ZERO_ADDRESS, { 'from': accounts[1] })
    # contracts_btc.stabilityPool.provideToSP(floatToWei(stability_initial/10), ZERO_ADDRESS, { 'from': accounts[1] })

    # btc whale
    coll_btc_3 = 1
    contracts_btc.coll.approve(contracts_btc.borrowerOperations.address, floatToWei(coll_btc_3, 1e8), { 'from': accounts[2] })
    print("approved for the btc coll")
    contracts_btc.borrowerOperations.openTrove(MAX_FEE, Wei(40000e18), floatToWei(coll_btc_3, 1e8), ZERO_ADDRESS, ZERO_ADDRESS, { 'from': accounts[2] })
    # contracts_btc.stabilityPool.provideToSP(floatToWei(stability_initial/10), ZERO_ADDRESS, { 'from': accounts[2] })

    logGlobalState(contracts_btc, 1e10)

    contracts_btc.priceFeedTestnet.setPrice(floatToWei(10000), { 'from': accounts[0] })

    logGlobalState(contracts_btc, 1e10)

    contracts_btc.troveManager.liquidateTroves(10, { 'from': accounts[0], 'allow_revert': True })

    print("after liquidation")
    logGlobalState(contracts_btc, 1e10)


"""# Simulation Program
**Sequence of events**

> In each period, the following events occur sequentially


* exogenous ether price input
* trove liquidation
* return of the previous period's stability pool determined (liquidation gain & airdropped LQTY gain)
* trove closure
* trove adjustment
* open troves
* issuance fee
* trove pool formed
* LUSD supply determined
* LUSD stability pool demand determined
* LUSD liquidity pool demand determined
* LUSD price determined
* redemption & redemption fee
* LQTY pool return determined
"""
def test_run_simulation(add_accounts, multi_coll_contracts, print_expectations):
    contracts_eth = multi_coll_contracts["coll_1"]
    contracts_btc = multi_coll_contracts["coll_2"]
    LUSD_GAS_COMPENSATION_ETH = contracts_eth.troveManager.LUSD_GAS_COMPENSATION() / 1e18
    MIN_NET_DEBT_ETH = contracts_eth.troveManager.MIN_NET_DEBT() / 1e18
    LUSD_GAS_COMPENSATION_BTC = contracts_btc.troveManager.LUSD_GAS_COMPENSATION() / 1e18
    MIN_NET_DEBT_BTC = contracts_btc.troveManager.MIN_NET_DEBT() / 1e18

    contracts_eth.priceFeedTestnet.setPrice(floatToWei(price_ether[0]), { 'from': accounts[0] })
    print("set up the ETH price feed")
    contracts_btc.priceFeedTestnet.setPrice(floatToWei(price_bitcoin[0]), { 'from': accounts[0] })
    print("set up the BTC price feed")
    # eth whale
    whale_coll_eth = 30000.0
    contracts_eth.coll.approve(contracts_eth.borrowerOperations.address, floatToWei(whale_coll_eth), { 'from': accounts[0] })
    print("approved for the eth coll")
    contracts_eth.borrowerOperations.openTrove(MAX_FEE, Wei(10e24), floatToWei(whale_coll_eth), ZERO_ADDRESS, ZERO_ADDRESS, { 'from': accounts[0] })
    contracts_eth.stabilityPool.provideToSP(floatToWei(stability_initial), ZERO_ADDRESS, { 'from': accounts[0] })

    # btc whale
    whale_coll_btc = 3000.0
    contracts_btc.coll.approve(contracts_btc.borrowerOperations.address, floatToWei(whale_coll_btc, 1e8), { 'from': accounts[0] })
    print("approved for the btc coll")
    contracts_btc.borrowerOperations.openTrove(MAX_FEE, Wei(10e24), floatToWei(whale_coll_btc, 1e8), ZERO_ADDRESS, ZERO_ADDRESS, { 'from': accounts[0] })
    contracts_btc.stabilityPool.provideToSP(floatToWei(stability_initial/10), ZERO_ADDRESS, { 'from': accounts[0] })    

    active_accounts_eth = []
    inactive_accounts_eth = [*range(1, len(accounts))]
    active_accounts_btc = []
    inactive_accounts_btc = [*range(1, len(accounts))]

    price_LUSD = 1
    price_LQTY_current = price_LQTY_initial

    data = {"airdrop_gain_eth": [0] * n_sim, "liquidation_gain_eth": [0] * n_sim, "airdrop_gain_btc": [0] * n_sim, "liquidation_gain_btc": [0] * n_sim, "issuance_fee": [0] * n_sim, "redemption_fee": [0] * n_sim}
    total_lusd_redempted = 0
    total_coll_added_eth = whale_coll_eth
    total_coll_added_btc = whale_coll_btc
    total_coll_liquidated_eth = 0
    total_coll_liquidated_btc = 0

    print(f"Accounts: {len(accounts)}")
    print(f"Network: {network.show_active()}")

    logGlobalState(contracts_eth)
    logGlobalState(contracts_btc)

    with open('tests/simulation.csv', 'w', newline='') as csvfile:
        datawriter = csv.writer(csvfile, delimiter=',')
        datawriter.writerow(['iteration','ETH_price', 'BTC_price', 'price_LUSD', 'price_LQTY_current', 'num_troves_eth', 'num_troves_btc',
            'total_coll_eth', 'total_coll_btc', 'total_debt_eth', 'total_debt_btc', 'TCR_eth', 'TCR_btc', 'recovery_mode_eth', 'recovery_mode_btc', 
            'last_ICR_eth', 'last_ICR_btc', 'SP_LUSD_ETH', 'SP_LUSD_BTC', 'SP_ETH', 'SP_BTC', 'total_coll_added_eth', 'total_coll_added_btc',
            'total_coll_liquidated_eth', 'total_coll_liquidated_btc', 'total_lusd_redempted'])

        #Simulation Process
        for index in range(1, n_sim):
            if index % 24 != 0:
                continue
            print('\n  --> Iteration', index)
            print('  -------------------\n')
            #exogenous ether price input
            price_ether_current = price_ether[index]
            contracts_eth.priceFeedTestnet.setPrice(floatToWei(price_ether_current), { 'from': accounts[0] })
            price_bitcoin_current = price_bitcoin[index]
            contracts_btc.priceFeedTestnet.setPrice(floatToWei(price_bitcoin_current), { 'from': accounts[0] })

            #trove liquidation & return of stability pool
            result_liquidation_eth = liquidate_troves(accounts, contracts_eth, active_accounts_eth, inactive_accounts_eth, price_ether_current, price_LUSD, price_LQTY_current, data, index)
            result_liquidation_btc = liquidate_troves(accounts, contracts_btc, active_accounts_btc, inactive_accounts_btc, price_bitcoin_current, price_LUSD, price_LQTY_current, data, index)
            total_coll_liquidated_eth = total_coll_liquidated_eth + result_liquidation_eth[0] 
            total_coll_liquidated_btc = total_coll_liquidated_btc + result_liquidation_btc[0]
            
            # liquidation_gain = result_liquidation_eth[1] + result_liquidation_btc[1]
            # airdrop_gain = result_liquidation_eth[2] + result_liquidation_btc[2]
            data['liquidation_gain_eth'][index] = result_liquidation_eth[1]
            data['airdrop_gain_eth'][index] = result_liquidation_eth[2]
            data['liquidation_gain_btc'][index] = result_liquidation_btc[1]
            data['airdrop_gain_btc'][index] = result_liquidation_btc[2]            

            return_stability_eth = calculate_stability_return(contracts_eth, price_LUSD, data, 'liquidation_gain_eth', 'airdrop_gain_eth', index)
            return_stability_btc = calculate_stability_return(contracts_btc, price_LUSD, data, 'liquidation_gain_btc', 'airdrop_gain_btc',index)

            # return_stability_eth = result_liquidation_eth[1]
            # return_stability_btc = result_liquidation_btc[1]

            #close troves
            result_close_eth = close_troves(accounts, contracts_eth, active_accounts_eth, inactive_accounts_eth, price_ether_current, price_LUSD, index)
            result_close_btc = close_troves(accounts, contracts_btc, active_accounts_btc, inactive_accounts_btc, price_bitcoin_current, price_LUSD, index)

            #adjust troves
            [coll_added_adjust_eth, issuance_LUSD_adjust_eth] = adjust_troves(accounts, contracts_eth, active_accounts_eth, inactive_accounts_eth, price_ether_current, index)
            [coll_added_adjust_btc, issuance_LUSD_adjust_btc] = adjust_troves(accounts, contracts_btc, active_accounts_btc, inactive_accounts_btc, price_bitcoin_current, index, 1e8)            

            #open troves
            [coll_added_open_eth, issuance_LUSD_open_eth] = open_troves(accounts, contracts_eth, active_accounts_eth, inactive_accounts_eth, price_ether_current, price_LUSD, index)
            total_coll_added_eth = total_coll_added_eth + coll_added_adjust_eth + coll_added_open_eth
            [coll_added_open_btc, issuance_LUSD_open_btc] = open_troves(accounts, contracts_btc, active_accounts_btc, inactive_accounts_btc, price_bitcoin_current, price_LUSD, index, 1e8)
            total_coll_added_btc = total_coll_added_btc + coll_added_adjust_btc + coll_added_open_btc            
            #active_accounts.sort(key=lambda a : a.get('CR_initial'))

            #Stability Pool
            stability_update(accounts, contracts_eth, active_accounts_eth, return_stability_eth, index)
            stability_update(accounts, contracts_btc, active_accounts_btc, return_stability_btc, index)

            #Calculating Price, Liquidity Pool, and Redemption
            [price_LUSD, redemption_pool_eth, redemption_fee_eth, issuance_LUSD_stabilizer_eth] = price_stabilizer(accounts, contracts_eth, active_accounts_eth, inactive_accounts_eth, price_ether_current, price_LUSD, index)
            issuance_fee_eth = price_LUSD * (issuance_LUSD_adjust_eth + issuance_LUSD_open_eth + issuance_LUSD_stabilizer_eth)
            total_lusd_redempted = total_lusd_redempted + redemption_pool_eth
            print('LUSD price', price_LUSD)
            print('LQTY price', price_LQTY_current)

            [price_LUSD, redemption_pool_btc, redemption_fee_btc, issuance_LUSD_stabilizer_btc] = price_stabilizer(accounts, contracts_btc, active_accounts_btc, inactive_accounts_btc, price_bitcoin_current, price_LUSD, index)
            issuance_fee_btc = price_LUSD * (issuance_LUSD_adjust_btc + issuance_LUSD_open_btc + issuance_LUSD_stabilizer_btc)
            total_lusd_redempted = total_lusd_redempted + redemption_pool_btc
            print('LUSD price', price_LUSD)
            print('LQTY price', price_LQTY_current)

            # data['issuance_fee'][index] = issuance_fee_eth
            # data['redemption_fee'][index] = redemption_fee_eth 
            # data['issuance_fee'][index] = issuance_fee_btc
            # data['redemption_fee'][index] = redemption_fee_btc            
            data['issuance_fee'][index] = issuance_fee_eth + issuance_fee_btc
            data['redemption_fee'][index] = redemption_fee_eth + redemption_fee_btc

            #LQTY Market
            result_LQTY = LQTY_market(index, data)
            price_LQTY_current = result_LQTY[0]
            #annualized_earning = result_LQTY[1]
            #MC_LQTY_current = result_LQTY[2]

            [ETH_price, num_troves_eth, total_coll_eth, total_debt_eth, TCR_eth, recovery_mode_eth, last_ICR_eth, SP_LUSD_ETH, SP_ETH] = logGlobalState(contracts_eth)
            # print('Total redempted ', total_lusd_redempted)
            print('Total ETH added ', total_coll_added_eth)
            print('Total ETH liquid', total_coll_liquidated_eth)
            print(f'Ratio ETH liquid {100 * total_coll_liquidated_eth / total_coll_added_eth}%')
            print(' ----------------------\n')            
            [BTC_price, num_troves_btc, total_coll_btc, total_debt_btc, TCR_btc, recovery_mode_btc, last_ICR_btc, SP_LUSD_BTC, SP_BTC] = logGlobalState(contracts_btc)            
            # print('Total redempted ', total_lusd_redempted)
            print('Total BTC added ', total_coll_added_btc)
            print('Total BTC liquid', total_coll_liquidated_btc)
            print(f'Ratio BTC liquid {100 * total_coll_liquidated_btc / total_coll_added_btc}%')
            print('Total redempted ', total_lusd_redempted)
            print(' ----------------------\n')                        

            datawriter.writerow([index, ETH_price, BTC_price, price_LUSD, price_LQTY_current, num_troves_eth, num_troves_btc,
                total_coll_eth, total_coll_btc, total_debt_eth, total_debt_btc, TCR_eth, TCR_btc, recovery_mode_eth, recovery_mode_btc, 
                last_ICR_eth, last_ICR_btc, SP_LUSD_ETH, SP_LUSD_BTC, SP_ETH, SP_BTC, total_coll_added_eth, total_coll_added_btc,
                total_coll_liquidated_eth, total_coll_liquidated_btc, total_lusd_redempted])

            assert price_LUSD > 0
