// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../Interfaces/IAnyTokenActivePool.sol";
import "../Interfaces/IAnyTokenVaultOperations.sol";
import "../Interfaces/IAnyTokenVaultManager.sol";
import "../Interfaces/ILUSDToken.sol";
import "../Dependencies/LiquityBase.sol";
import "../Dependencies/Ownable.sol";
import "../Dependencies/CheckContract.sol";
import "../Dependencies/console.sol";

contract AnyTokenVaultOperations is LiquityBase, Ownable, CheckContract, IAnyTokenVaultOperations {
    string constant public NAME = "AnyTokenVaultOperations";

    // --- Connected contract declarations ---

    IAnyTokenVaultManager public anyTokenVaultManager;

    address public borrowingFeeTreasury;

    ILUSDToken public LUSDToken;
    IERC20 public collToken;
    bool addressesSet = false;
    uint private collDecimalDiff;

    enum Functions { SET_TREASURY_ADDRESS }  
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

    /* --- Variable container structs  ---

    Used to hold, return and assign variables inside a function, in order to avoid the error:
    "CompilerError: Stack too deep". */

     struct LocalVariables_adjustVault {
        uint collChange;
        uint netDebtChange;
        bool isCollIncrease;
        uint debt;
        uint coll;
        uint newICR;
        uint LUSDFee;
        uint newDebt;
        uint newColl;
        uint debtCeiling;
    }

    struct LocalVariables_openVault {
        uint LUSDFee;
        uint collAmount;
        uint netDebt;
        uint arrayIndex;
        uint debtCeiling;
    }

    struct ContractsCache {
        IAnyTokenVaultManager anyTokenVaultManager;
        IAnyTokenActivePool anyTokenActivePool;
        ILUSDToken LUSDToken;
    }

    enum BorrowerOperation {
        openVault,
        closeVault,
        adjustVault
    }

    event AnyTokenVaultManagerAddressChanged(address _newAnyTokenVaultManagerAddress);
    event AnyTokenActivePoolAddressChanged(address _anyTokenActivePoolAddress);
    event CollTokenAddressChanged(address _collTokenAddress);
    event BorrowingFeeTreasuryChanged(address _borrowingFeeTreasury);

    event VaultCreated(address indexed _borrower, uint arrayIndex);
    event VaultUpdated(address indexed _borrower, uint _debt, uint _coll, BorrowerOperation operation);
    event LUSDBorrowingFeePaid(address indexed _borrower, uint _LUSDFee);
    
    // --- Dependency setters ---

    function setAddresses(
        address _anyTokenVaultManagerAddress,
        address _anyTokenActivePoolAddress,
        address _LUSDTokenAddress,
        address _collTokenAddress,
        uint _collDecimalDiff
    )
        external
        override
        onlyOwner
    {
        require(!addressesSet, "AnyTokenVaultOperations: Addresses are already set!");
        addressesSet = true;

        // This makes impossible to open a vault with zero withdrawn LUSD
        assert(MIN_NET_DEBT > 0);

        checkContract(_anyTokenVaultManagerAddress);
        checkContract(_anyTokenActivePoolAddress);
        checkContract(_LUSDTokenAddress);
        checkContract(_collTokenAddress);

        anyTokenVaultManager = IAnyTokenVaultManager(_anyTokenVaultManagerAddress);
        anyTokenActivePool = IAnyTokenActivePool(_anyTokenActivePoolAddress);
        LUSDToken = ILUSDToken(_LUSDTokenAddress);
        collToken = IERC20(_collTokenAddress);

        emit AnyTokenVaultManagerAddressChanged(_anyTokenVaultManagerAddress);
        emit AnyTokenActivePoolAddressChanged(_anyTokenActivePoolAddress);
        emit CollTokenAddressChanged(_collTokenAddress);

        collDecimalDiff = _collDecimalDiff;
    }

    function setBorrowingFeeTreasury(address _borrowingFeeTreasury) external onlyOwner notLocked(Functions.SET_TREASURY_ADDRESS) {
        borrowingFeeTreasury = _borrowingFeeTreasury;

        emit BorrowingFeeTreasuryChanged(_borrowingFeeTreasury);

        timelock[Functions.SET_TREASURY_ADDRESS] = 1;
    }

    // --- Borrower Vault Operations ---

    function openVault(uint _LUSDAmount) external override {
        _LUSDAmount = _LUSDAmount.div(collDecimalDiff).mul(collDecimalDiff);

        ContractsCache memory contractsCache = ContractsCache(anyTokenVaultManager, anyTokenActivePool, LUSDToken);
        LocalVariables_openVault memory vars;
        vars.collAmount = _getcollAmount(_LUSDAmount);
        require(collToken.transferFrom(msg.sender, address(this), vars.collAmount), "AnyTokenVaultOperations: Collateral transfer failed on openVault");  

        _requireVaultisNotActive(contractsCache.anyTokenVaultManager, msg.sender);

        vars.LUSDFee = _triggerBorrowingFee(contractsCache.anyTokenVaultManager, contractsCache.LUSDToken, _LUSDAmount);
        vars.netDebt = _LUSDAmount.add(vars.LUSDFee);
        vars.debtCeiling = contractsCache.anyTokenVaultManager.getDebtCeiling();

        _requireAtLeastMinNetDebt(vars.netDebt);
        _requireActivePoolDebtBelowDebtCeiling(vars.netDebt, getEntireSystemStableDebt(), vars.debtCeiling);   

        // Set the vault struct's properties
        contractsCache.anyTokenVaultManager.setVaultStatus(msg.sender, 1);
        contractsCache.anyTokenVaultManager.increaseVaultColl(msg.sender, vars.collAmount);
        contractsCache.anyTokenVaultManager.increaseVaultDebt(msg.sender, vars.netDebt);

        vars.arrayIndex = contractsCache.anyTokenVaultManager.addVaultOwnerToArray(msg.sender);
        emit VaultCreated(msg.sender, vars.arrayIndex);

        // Move the anyToken to the Active Pool, and mint the LUSDAmount to the borrower
        _activePoolAddColl(contractsCache.anyTokenActivePool, vars.collAmount);
        _withdrawLUSD(contractsCache.anyTokenActivePool, contractsCache.LUSDToken, msg.sender, _LUSDAmount, vars.netDebt);

        emit VaultUpdated(msg.sender, vars.netDebt, vars.collAmount, BorrowerOperation.openVault);
        emit LUSDBorrowingFeePaid(msg.sender, vars.LUSDFee);
    }

    // Send AnyToken as collateral to a vault
    function addColl(uint _collAmount) external override {
        // Replace payable with an explicit token transfer.
       
        require(collToken.transferFrom(msg.sender, address(this), _collAmount), 
                "AnyTokenVaultOperations: Collateral transfer failed on adjustVault");
        _adjustVault(msg.sender, _collAmount.mul(collDecimalDiff).div(ANYTOKEN_COLLATERAL_RARIO), true);
    }

    // Withdraw anyToken collateral from a vault
    function withdrawColl(uint _collAmount) external override {
        _adjustVault(msg.sender, _collAmount, false);
    }

    // Withdraw LUSD tokens from a vault: mint new LUSD tokens to the owner, and increase the vault's debt accordingly
    function withdrawLUSD(uint _LUSDAmount) external override {              
        require(collToken.transferFrom(msg.sender, address(this), _getcollAmount(_LUSDAmount)), 
                "AnyTokenVaultOperations: Collateral transfer failed on adjustVault");        
        _adjustVault(msg.sender, _LUSDAmount, true);
    }

    // Repay LUSD tokens to a Vault: Burn the repaid LUSD tokens, and reduce the vault's debt accordingly
    function repayLUSD(uint _LUSDAmount) external override {
        _adjustVault(msg.sender, _LUSDAmount, false);
    }

    function adjustVault(uint _LUSDChange, bool _isDebtIncrease) external override {
        if (_isDebtIncrease) {
            require(collToken.transferFrom(msg.sender, address(this), _getcollAmount(_LUSDChange)), 
                    "AnyTokenVaultOperations: Collateral transfer failed on adjustVault");
        }
        _adjustVault(msg.sender, _LUSDChange, _isDebtIncrease);
    }

    /*
    * _adjustVault(): Alongside a debt change, this function can perform either a collateral top-up or a collateral withdrawal. 
    *
    * It therefore expects either a positive _collAmount, or a positive _collWithdrawal argument.
    *
    * If both are positive, it will revert.
    */
    function _adjustVault(address _borrower, uint _LUSDChange, bool _isDebtIncrease) internal {
        ContractsCache memory contractsCache = ContractsCache(anyTokenVaultManager, anyTokenActivePool, LUSDToken);
        LocalVariables_adjustVault memory vars;

        _requireNonZeroDebtChange(_LUSDChange);

        if (_isDebtIncrease) {
            vars.collChange = _getcollAmount(_LUSDChange);
            vars.isCollIncrease =  true;
        } else {
            vars.collChange = _LUSDChange.div(collDecimalDiff);
            vars.isCollIncrease =  false;
        }

        _requireVaultisActive(contractsCache.anyTokenVaultManager, _borrower);

        // Confirm the operation is a borrower adjusting their own vault.
        assert(msg.sender == _borrower);

        vars.debtCeiling = contractsCache.anyTokenVaultManager.getDebtCeiling();

        vars.netDebtChange = _LUSDChange;

        // If the adjustment incorporates a debt increase and system is in Normal Mode, then trigger a borrowing fee
        if (_isDebtIncrease) { 
            vars.LUSDFee = _triggerBorrowingFee(contractsCache.anyTokenVaultManager, contractsCache.LUSDToken, _LUSDChange);
            vars.netDebtChange = vars.netDebtChange.add(vars.LUSDFee); // The raw debt change includes the fee
            _requireActivePoolDebtBelowDebtCeiling(vars.netDebtChange, getEntireSystemStableDebt(), vars.debtCeiling);
        }

        vars.debt = contractsCache.anyTokenVaultManager.getVaultDebt(_borrower);
        vars.coll = contractsCache.anyTokenVaultManager.getVaultColl(_borrower);

        if (!_isDebtIncrease) {
            assert(vars.collChange <= vars.coll); 
        }

        // Get the vault's old ICR before the adjustment, and what its new ICR will be after the adjustment
        (vars.newColl, vars.newDebt, vars.newICR) = _getNewICRFromVaultChange(vars.coll, vars.debt, vars.collChange, vars.isCollIncrease, vars.netDebtChange, _isDebtIncrease, 1e18 /* price */);

        // Check the adjustment satisfies all conditions
        _requireValidAdjustment(_isDebtIncrease, vars);
            
        // When the adjustment is a debt repayment, check it's a valid amount and that the caller has enough LUSD
        if (!_isDebtIncrease) {
            _requireValidLUSDRepayment(vars.debt, vars.netDebtChange);
            _requireAtLeastMinNetDebt(vars.debt.sub(vars.netDebtChange));
            _requireSufficientLUSDBalance(contractsCache.LUSDToken, _borrower, vars.netDebtChange);
        }

        (vars.newColl, vars.newDebt) = _updateVaultFromAdjustment(contractsCache.anyTokenVaultManager, _borrower, vars.collChange, vars.isCollIncrease, vars.netDebtChange, _isDebtIncrease);

        emit VaultUpdated(_borrower, vars.newDebt, vars.newColl, BorrowerOperation.adjustVault);
        emit LUSDBorrowingFeePaid(msg.sender,  vars.LUSDFee);

        // Use the unmodified _LUSDChange here, as we don't send the fee to the user
        _moveTokensAndETHfromAdjustment(
            contractsCache.anyTokenActivePool,
            contractsCache.LUSDToken,
            msg.sender,
            vars.collChange,
            vars.isCollIncrease,
            _LUSDChange,
            _isDebtIncrease,
            vars.netDebtChange
        );
    }

    function closeVault() external override {
        IanyTokenVaultManager anyTokenVaultManagerCached = anyTokenVaultManager;
        IanyTokenActivePool anyTokenActivePoolCached = anyTokenActivePool;
        ILUSDToken LUSDTokenCached = LUSDToken;

        _requireVaultisActive(anyTokenVaultManagerCached, msg.sender);

        uint coll = anyTokenVaultManagerCached.getVaultColl(msg.sender);
        uint debt = anyTokenVaultManagerCached.getVaultDebt(msg.sender);

        _requireSufficientLUSDBalance(LUSDTokenCached, msg.sender, debt);

        (uint totalColl, uint totalDebt, uint newTCR) = _getNewTCRFromVaultChange(coll, false, debt, false, 1e18 /* price */);
        _requireNewTCREqualsToMSCR(totalColl, totalDebt, newTCR);

        anyTokenVaultManagerCached.closeVault(msg.sender);

        emit VaultUpdated(msg.sender, 0, 0, BorrowerOperation.closeVault);

        // Burn the repaid LUSD from the user's balance and the gas compensation from the Gas Pool
        _repayLUSD(anyTokenActivePoolCached, LUSDTokenCached, msg.sender, debt);

        // Send the collateral back to the user
        anyTokenActivePoolCached.sendColl(msg.sender, coll);
    }

    // --- Helper functions ---

    function _triggerBorrowingFee(IanyTokenVaultManager _anyTokenVaultManager, ILUSDToken _LUSDToken, uint _LUSDAmount) internal returns (uint) {
        uint LUSDFee = _anyTokenVaultManager.getBorrowingFee(_LUSDAmount);
        _LUSDToken.mint(borrowingFeeTreasury, LUSDFee);

        return LUSDFee;
    }

    // Update vault's coll and debt based on whether they increase or decrease
    function _updateVaultFromAdjustment
    (
        IanyTokenVaultManager _vaultManager,
        address _borrower,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease
    )
        internal
        returns (uint, uint)
    {
        uint newColl = (_isCollIncrease) ? _vaultManager.increaseVaultColl(_borrower, _collChange)
                                        : _vaultManager.decreaseVaultColl(_borrower, _collChange);
        uint newDebt = (_isDebtIncrease) ? _vaultManager.increaseVaultDebt(_borrower, _debtChange)
                                        : _vaultManager.decreaseVaultDebt(_borrower, _debtChange);

        return (newColl, newDebt);
    }

    function _moveTokensAndCollfromAdjustment
    (
        IanyTokenActivePool _activePool,
        ILUSDToken _LUSDToken,
        address _borrower,
        uint _collChange,
        bool _isCollIncrease,
        uint _LUSDChange,
        bool _isDebtIncrease,
        uint _netDebtChange
    )
        internal
    {
        if (_isDebtIncrease) {
            _withdrawLUSD(_activePool, _LUSDToken, _borrower, _LUSDChange, _netDebtChange);
        } else {
            _repayLUSD(_activePool, _LUSDToken, _borrower, _LUSDChange);
        }

        if (_isCollIncrease) {
            _activePoolAddColl(_activePool, _collChange);
        } else {
            _activePool.sendColl(_borrower, _collChange);
        }
    }

    // Send AnyToken to Active Pool and increase its recorded Collateral balance
    function _activePoolAddColl(IanyTokenActivePool _activePool, uint _amount) internal {
        uint256 allowance = collToken.allowance(address(this), address(_activePool));
        if (allowance < _amount) {
            bool success = collToken.approve(address(_activePool), type(uint256).max);
            require(success, "AnyTokenVaultOperations: Cannot approve ActivePool to spend collateral");
        }
        _activePool.depositColl(_amount);
    }

    // Issue the specified amount of LUSD to _account and increases the total active debt (_netDebtIncrease potentially includes a LUSDFee)
    function _withdrawLUSD(IanyTokenActivePool _activePool, ILUSDToken _LUSDToken, address _account, uint _LUSDAmount, uint _netDebtIncrease) internal {
        _activePool.increaseLUSDDebt(_netDebtIncrease);
        _LUSDToken.mint(_account, _LUSDAmount);
    }

    // Burn the specified amount of LUSD from _account and decreases the total active debt
    function _repayLUSD(IanyTokenActivePool _activePool, ILUSDToken _LUSDToken, address _account, uint _LUSD) internal {
        _activePool.decreaseLUSDDebt(_LUSD);
        _LUSDToken.burn(_account, _LUSD);
    }

    // --- 'Require' wrapper functions ---
    function _requireVaultisActive(IanyTokenVaultManager _vaultManager, address _borrower) internal view {
        uint status = _vaultManager.getVaultStatus(_borrower);
        require(status == 1, "AnyTokenVaultOperations: Vault does not exist or is closed");
    }

    function _requireVaultisNotActive(IanyTokenVaultManager _vaultManager, address _borrower) internal view {
        uint status = _vaultManager.getVaultStatus(_borrower);
        require(status != 1, "AnyTokenVaultOperations: Vault is active");
    }

    function _requireNonZeroDebtChange(uint _LUSDChange) internal pure {
        require(_LUSDChange > 0, "AnyTokenVaultOperations: Debt increase requires non-zero debtChange");
    }

    function _requireValidAdjustment
    (
        bool _isDebtIncrease, 
        LocalVariables_adjustVault memory _vars
    ) 
        internal 
        view 
    {
        /* 
        * Ensure:
        *
        * - The new ICR is above MCR
        * - The adjustment won't pull the TCR below CCR
        */
        _requireICREqualsToMSCR(_vars.newColl, _vars.newDebt, _vars.newICR);
        (uint totalColl, uint totalDebt, uint newTCR) = _getNewTCRFromVaultChange(_vars.collChange, _vars.isCollIncrease, _vars.netDebtChange, _isDebtIncrease, 1e18 /* price */);
        _requireNewTCREqualsToMSCR(totalColl, totalDebt, newTCR);  
    }

    function _requireICREqualsToMSCR(uint _newColl, uint _newDebt, uint _newICR) internal pure {
        require((_newColl == 0 && _newDebt == 0) || _newICR == MSCR, "AnyTokenVaultOperations: An operation that would result in ICR != MSCR is not permitted");
    }

    function _requireNewTCREqualsToMSCR(uint _totalColl, uint _totalDebt, uint _newTCR) internal pure {
        require((_totalColl == 0 && _totalDebt == 0) || _newTCR == MSCR, "AnyTokenVaultOperations: An operation that would result in TCR != MSCR is not permitted");
    }

    function _requireAtLeastMinNetDebt(uint _netDebt) internal pure {
        require (_netDebt >= MIN_SWAP_NET_DEBT, "AnyTokenVaultOperations: Vault's net debt must be greater than minimum");
    }

    function _requireActivePoolDebtBelowDebtCeiling(uint _netDebt, uint _activePoolLUSDDebt, uint _debtCeiling) internal pure {
        require (_netDebt.add( _activePoolLUSDDebt) <= _debtCeiling, "AnyTokenVaultOperations: Vault's net debt must be less than debt ceiling");
    }

    function _requireValidLUSDRepayment(uint _currentDebt, uint _debtRepayment) internal pure {
        require(_debtRepayment <= _currentDebt, "AnyTokenVaultOperations: Amount repaid must not be larger than the Vault's debt");
    }

     function _requireSufficientLUSDBalance(ILUSDToken _LUSDToken, address _borrower, uint _debtRepayment) internal view {
        require(_LUSDToken.balanceOf(_borrower) >= _debtRepayment, "AnyTokenVaultOperations: Caller doesnt have enough LUSD to make repayment");
    }

    // --- ICR and TCR getters ---

    // Compute the new collateral ratio, considering the change in coll and debt. Assumes 0 pending rewards.
    function _getNewICRFromVaultChange
    (
        uint _coll,
        uint _debt,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease,
        uint _price
    )
        view
        internal
        returns (uint, uint, uint)
    {
        (uint newColl, uint newDebt) = _getNewVaultAmounts(_coll, _debt, _collChange, _isCollIncrease, _debtChange, _isDebtIncrease);

        uint newICR = LiquityMath._computeCR(newColl, newDebt, _price, collDecimalDiff);
        return (newColl, newDebt, newICR);
    }

    function _getNewVaultAmounts(
        uint _coll,
        uint _debt,
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease
    )
        internal
        pure
        returns (uint, uint)
    {
        uint newColl = _coll;
        uint newDebt = _debt;

        newColl = _isCollIncrease ? _coll.add(_collChange) :  _coll.sub(_collChange);
        newDebt = _isDebtIncrease ? _debt.add(_debtChange) : _debt.sub(_debtChange);

        return (newColl, newDebt);
    }

    function _getNewTCRFromVaultChange
    (
        uint _collChange,
        bool _isCollIncrease,
        uint _debtChange,
        bool _isDebtIncrease,
        uint _price
    )
        internal
        view
        returns (uint, uint, uint)
    {
        uint totalColl = getEntireSystemStableColl();
        uint totalDebt = getEntireSystemStableDebt();

        totalColl = _isCollIncrease ? totalColl.add(_collChange) : totalColl.sub(_collChange);
        totalDebt = _isDebtIncrease ? totalDebt.add(_debtChange) : totalDebt.sub(_debtChange);

        uint newTCR = LiquityMath._computeCR(totalColl, totalDebt, _price, collDecimalDiff);
        return (totalColl, totalDebt, newTCR);
    }

    function getCompositeDebt(uint _debt) external pure override returns (uint) {
        return _getCompositeDebt(_debt);
    }
    
    function _getcollAmount(uint _LUSDDebt) internal view returns (uint) {
        return _LUSDDebt.mul(ANYTOKEN_COLLATERAL_RARIO).div(DECIMAL_PRECISION).div(collDecimalDiff);
    }
}