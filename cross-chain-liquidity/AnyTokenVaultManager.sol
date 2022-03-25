// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../Interfaces/IAnyTokenVaultManager.sol";
import "../Interfaces/ILUSDToken.sol";
import "../Interfaces/ILQTYToken.sol";
import "../Dependencies/LiquityBase.sol";
import "../Dependencies/Ownable.sol";
import "../Dependencies/CheckContract.sol";
import "../Dependencies/console.sol";
import "../Dependencies/BaseMath.sol";

contract AnyTokenVaultManager is LiquityBase, Ownable, CheckContract, IAnyTokenVaultManager {
    string constant public NAME = "AnyTokenVaultManager";

    // --- Connected contract declarations ---

    address public anyTokenVaultOperationsAddress;

    ILUSDToken public override lusdToken;

    ILQTYToken public override lqtyToken;

    address public collTokenAddress;

    bool addressesSet = false;
    uint public debtCeilingPlus;
    uint private collDecimalDiff;

    enum Functions { SET_DEBT_CEILING }  
    uint256 private constant _TIMELOCK = 1 days;
    mapping(Functions => uint256) public timelock;

    // --- Time lock
    modifier notLocked(Functions _fn) {
        require(
        timelock[_fn] != 1 && timelock[_fn] <= block.timestamp,
        "Function is timelocked"
        );
        _;
    }
    //unlock timelock
    function unlockFunction(Functions _fn) public onlyOwner {
        timelock[_fn] = block.timestamp + _TIMELOCK;
    }
    //lock timelock
    function lockFunction(Functions _fn) public onlyOwner {
        timelock[_fn] = 1;
    }

    // --- Data structures ---
    enum Status {
        nonExistent,
        active,
        closedByOwner
    }

    // Store the necessary data for a vault
    struct Vault {
        uint debt;
        uint coll;
        uint stake; /* To be removed */
        Status status;
        uint128 arrayIndex;
    }

    mapping (address => Vault) public Vaults;

    // Array of all active vault addresses - used to to compute an approximate hint off-chain, for the sorted list insertion
    address[] public VaultOwners;

    struct ContractsCache {
        IAnyTokenActivePool anyTokenActivePool;
        ILUSDToken lusdToken;
    }

    // --- Events ---
    event AnyTokenVaultOperationsAddressChanged(address _newAnyTokenVaultOperationsAddress);
    event LUSDTokenAddressChanged(address _newLUSDTokenAddress);
    event AnyTokenActivePoolAddressChanged(address _anyTokenActivePoolAddress);
    event DebtCeilingPlusChanged(uint _debtCeilingPlus);


    // --- Dependency setter ---

    function setAddresses(
        address _anyTokenVaultOperationsAddress,
        address _anyTokenActivePoolAddress,
        address _lusdTokenAddress,
        address _collTokenAddress,
        uint _collDecimalDiff
    )
        external
        override
        onlyOwner
    {
        require(!addressesSet, "AnyTokenVaultManager: Addresses are already set!");
        addressesSet = true;

        checkContract(_anyTokenVaultOperationsAddress);
        checkContract(_anyTokenActivePoolAddress);
        checkContract(_lusdTokenAddress);

        anyTokenVaultOperationsAddress = _anyTokenVaultOperationsAddress;
        anyTokenActivePool = IAnyTokenActivePool(_anyTokenActivePoolAddress);
        lusdToken = ILUSDToken(_lusdTokenAddress);
        collTokenAddress = _collTokenAddress;
        collDecimalDiff = _collDecimalDiff;

        emit AnyTokenVaultOperationsAddressChanged(_anyTokenVaultOperationsAddress);
        emit AnyTokenActivePoolAddressChanged(_anyTokenActivePoolAddress);
        emit LUSDTokenAddressChanged(_lusdTokenAddress);
    }

    function setDebtCeilingPlus(uint _debtCeilingPlus) external onlyOwner notLocked(Functions.SET_DEBT_CEILING) {
        debtCeilingPlus = _debtCeilingPlus;

        emit DebtCeilingPlusChanged(_debtCeilingPlus);

        timelock[Functions.SET_DEBT_CEILING] = 1;
    }

    // --- Getters ---

    function getVaultOwnersCount() external view override returns (uint) {
        return VaultOwners.length;
    }

    function getVaultFromVaultOwnersArray(uint _index) external view override returns (address) {
        return VaultOwners[_index];
    }


    // Return the Vaults entire debt and coll.
    function getEntireDebtAndColl(
        address _borrower
    )
        public
        view
        override
        returns (uint debt, uint coll)
    {
        debt = Vaults[_borrower].debt;
        coll = Vaults[_borrower].coll;
    }

    function closeVault(address _borrower) external override {
        _requireCallerIsVaultOperations();
        return _closeVault(_borrower, Status.closedByOwner);
    }

    function _closeVault(address _borrower, Status closedStatus) internal {
        assert(closedStatus != Status.nonExistent && closedStatus != Status.active);

        uint VaultOwnersArrayLength = VaultOwners.length;
        _requireMoreThanOneVaultInSystem(VaultOwnersArrayLength);

        Vaults[_borrower].status = closedStatus;
        Vaults[_borrower].coll = 0;
        Vaults[_borrower].debt = 0;

        _removeVaultOwner(_borrower, VaultOwnersArrayLength);
    }

    // Push the owner's address to the Vault owners list, and record the corresponding array index on the Vault struct
    function addVaultOwnerToArray(address _borrower) external override returns (uint index) {
        _requireCallerIsVaultOperations();
        return _addVaultOwnerToArray(_borrower);
    }

    function _addVaultOwnerToArray(address _borrower) internal returns (uint128 index) {
        /* Max array size is 2**128 - 1, i.e. ~3e30 vaults. No risk of overflow, since vaults have minimum LUSD
        debt of liquidation reserve plus MIN_NET_DEBT. 3e30 LUSD dwarfs the value of all wealth in the world ( which is < 1e15 USD). */

        // Push the Vaultowner to the array
        VaultOwners.push(_borrower);

        // Record the index of the new Vaultowner on their Vault struct
        index = uint128(VaultOwners.length.sub(1));
        Vaults[_borrower].arrayIndex = index;

        return index;
    }

    /*
    * Remove a vault owner from the VaultOwners array, not preserving array order. Removing owner 'B' does the following:
    * [A B C D E] => [A E C D], and updates E's Vault struct to point to its new array index.
    */
    function _removeVaultOwner(address _borrower, uint VaultOwnersArrayLength) internal {
        Status vaultStatus = Vaults[_borrower].status;
        // It’s set in caller function `_closeVault`
        assert(vaultStatus != Status.nonExistent && vaultStatus != Status.active);

        uint128 index = Vaults[_borrower].arrayIndex;
        uint length = VaultOwnersArrayLength;
        uint idxLast = length.sub(1);

        assert(index <= idxLast);

        address addressToMove = VaultOwners[idxLast];

        VaultOwners[index] = addressToMove;
        Vaults[addressToMove].arrayIndex = index;
        emit VaultIndexUpdated(addressToMove, index);

        VaultOwners.pop();
    }

    // --- Recovery Mode and TCR functions ---

    function getTCR(uint _price) external view override returns (uint) {
        return _getTCR(_price, collDecimalDiff);
    }

    // --- Borrowing fee functions ---

    function getBorrowingRate() public view override returns (uint) { /* mark */
        return 0;
    }

    function getBorrowingFee(uint _LUSDDebt) external view override returns (uint) { /* mark */
        return _calcBorrowingFee(getBorrowingRate(), _LUSDDebt);
    }

    function _calcBorrowingFee(uint _borrowingRate, uint _LUSDDebt) internal pure returns (uint) { /* mark */
        return _borrowingRate.mul(_LUSDDebt).div(DECIMAL_PRECISION);
    }

    function getDebtCeiling() public view override returns (uint) { /* mark */
        return ANYTOKEN_DEBT_CEILING.add(debtCeilingPlus);
    }

    function getAnyTokenAmount(uint _LUSDDebt) public view override returns (uint) { /* mark */
        return _LUSDDebt.mul(ANYTOKEN_COLLATERAL_RARIO).div(DECIMAL_PRECISION).div(collDecimalDiff);
    }

    // --- 'require' wrapper functions ---

    function _requireCallerIsVaultOperations() internal view {
        require(msg.sender == anyTokenVaultOperationsAddress, "AnyTokenVaultManager: Caller is not the BorrowerOperations contract");
    }

    function _requireVaultIsActive(address _borrower) internal view {
        require(Vaults[_borrower].status == Status.active, "AnyTokenVaultManager: Vault does not exist or is closed");
    }

    function _requireLUSDBalanceCoversRedemption(ILUSDToken _lusdToken, address _redeemer, uint _amount) internal view {
        require(_lusdToken.balanceOf(_redeemer) >= _amount, "AnyTokenVaultManager: Requested redemption amount must be <= user's LUSD token balance");
    }

    function _requireMoreThanOneVaultInSystem(uint VaultOwnersArrayLength) internal view {
        require (VaultOwnersArrayLength > 1, "AnyTokenVaultManager: Only one vault in the system");
    }

    function _requireAmountGreaterThanZero(uint _amount) internal pure {
        require(_amount > 0, "AnyTokenVaultManager: Amount must be greater than zero");
    }

    function _requireTCRoverMCR(uint _price) internal view {
        require(_getTCR(_price, collDecimalDiff) >= MCR, "AnyTokenVaultManager: Cannot redeem when TCR < MCR");
    }

    // --- Vault property getters ---

    function getVaultStatus(address _borrower) external view override returns (uint) { /* mark */
        return uint(Vaults[_borrower].status);
    }

    function getVaultDebt(address _borrower) external view override returns (uint) {
        return Vaults[_borrower].debt;
    }

    function getVaultColl(address _borrower) external view override returns (uint) {
        return Vaults[_borrower].coll;
    }

    // --- Vault property setters, called by BorrowerOperations ---

    function setVaultStatus(address _borrower, uint _num) external override {
        _requireCallerIsVaultOperations();
        Vaults[_borrower].status = Status(_num);
    }

    function increaseVaultColl(address _borrower, uint _collIncrease) external override returns (uint) {
        _requireCallerIsVaultOperations();
        uint newColl = Vaults[_borrower].coll.add(_collIncrease);
        Vaults[_borrower].coll = newColl;
        return newColl;
    }

    function decreaseVaultColl(address _borrower, uint _collDecrease) external override returns (uint) {
        _requireCallerIsVaultOperations();
        uint newColl = Vaults[_borrower].coll.sub(_collDecrease);
        Vaults[_borrower].coll = newColl;
        return newColl;
    }

    function increaseVaultDebt(address _borrower, uint _debtIncrease) external override returns (uint) {
        _requireCallerIsVaultOperations();
        uint newDebt = Vaults[_borrower].debt.add(_debtIncrease);
        Vaults[_borrower].debt = newDebt;
        return newDebt;
    }

    function decreaseVaultDebt(address _borrower, uint _debtDecrease) external override returns (uint) {
        _requireCallerIsVaultOperations();
        uint newDebt = Vaults[_borrower].debt.sub(_debtDecrease);
        Vaults[_borrower].debt = newDebt;
        return newDebt;
    }
}