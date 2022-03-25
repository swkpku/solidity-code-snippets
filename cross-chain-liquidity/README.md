# Stablecoin cross chain liquidity design

## Problem settings
For a stablecoin protocol, if there is a native stablecoin on each deployed chain, meaning that users on each deployed chain can mint the stablecoin independently, how do you make sure one can always move any amount of the stablecoin at any time from one chain to another despite the liquidity on the destination chain.

## Background
Multichain (previously called AnySwap) provides liquidity-based cross-chain solution. When there is enough liqudity on the other side, users get the same amount of stablecoins on the destination chain, but if there is no enough liqudity, users get anyToken instead.

## Solution
We design a vault for anyTokens, users can deposit anyToken into the system and get the same amount of native stablecoins on the destination chain.

### AnyTokenVaultOperations.sol
This contract contains the basic operations by which borrowers interact with their Vault: Vault creation, AnyToken top-up / withdrawal, stablecoin issuance and repayment. It also sends issuance fees to the borrowing fee treasury contract. AnyTokenVaultOperations functions call in to AnyTokenVaultManager, telling it to update Vault state, where necessary. AnyTokenVaultOperations functions also call in to the AnyTokenActivePool, telling them to move AnyToken between Pool <> user.

### AnyTokenVaultManager.sol
This contract contains the state of each Vault - i.e. a record of the Vault’s collateral and debt. AnyTokenVaultManager does not hold anyToken. AnyTokenVaultManager functions call in to AnyTokenActivePool to tell them to move anyTokens.


### AnyTokenActivePool.sol
This contract holds the total anyToken balance and records the total stablecoin debt of the active Vaults.