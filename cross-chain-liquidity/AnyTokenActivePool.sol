// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import '../Interfaces/IAnyTokenActivePool.sol';
import "../Dependencies/IERC20.sol";
import "../Dependencies/SafeMath.sol";
import "../Dependencies/Ownable.sol";
import "../Dependencies/CheckContract.sol";
import "../Dependencies/console.sol";

/*
 * The Active Pool holds the AnyToken collateral and LUSD debt (but not LUSD tokens) for all active vaults.
 */
contract AnyTokenActivePool is Ownable, CheckContract, IAnyTokenActivePool {
    using SafeMath for uint256;

    string constant public NAME = "AnyTokenActivePool";

    address public anyTokenVaultOperationsAddress;
    address public anyTokenVaultManagerAddress;
    uint256 internal AnyToken;  // deposited anyToken tracker
    uint256 internal LUSDDebt;

    IERC20 public collToken;

    enum Functions { SET_ADDRESS }  
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

    // --- Events ---

    event AnyTokenVaultOperationsAddressChanged(address _newAnyTokenVaultOperationsAddress);
    event AnyTokenVaultManagerAddressChanged(address _newAnyTokenVaultManagerAddress);
    event AnyTokenActivePoolLUSDDebtUpdated(uint _LUSDDebt);
    event AnyTokenActivePoolAnyTokenBalanceUpdated(uint _anyToken);
    event CollTokenAddressChanged(address _collTokenAddress);

    // --- Contract setters ---

    function setAddresses(
        address _anyTokenVaultOperationsAddress,
        address _anyTokenVaultManagerAddress,
        address _collTokenAddress
    )
        external
        onlyOwner
        notLocked(Functions.SET_ADDRESS)
    {
        checkContract(_anyTokenVaultOperationsAddress);
        checkContract(_anyTokenVaultManagerAddress);
        checkContract(_collTokenAddress);

        anyTokenVaultOperationsAddress = _anyTokenVaultOperationsAddress;
        anyTokenVaultManagerAddress = _anyTokenVaultManagerAddress;
        collToken = IERC20(_collTokenAddress);

        emit AnyTokenVaultOperationsAddressChanged(_anyTokenVaultOperationsAddress);
        emit AnyTokenVaultManagerAddressChanged(_anyTokenVaultManagerAddress);
        emit CollAddressChanged(_collTokenAddress);

        _renounceOwnership();

        timelock[Functions.SET_ADDRESS] = 1;
    }

    // --- Getters for public variables. Required by IPool interface ---

    /*
    * Returns the AnyToken state variable.
    *
    * Not necessarily equal to the the contract's raw AnyToken balance - AnyTokener can be forcibly sent to contracts.
    */
    function getAnyToken() external view override returns (uint) {
        return AnyToken;
    }

    function getLUSDDebt() external view override returns (uint) {
        return LUSDDebt;
    }

    // --- Pool functionality ---

    function sendAnyToken(address _account, uint _amount) external override {
        _requireCallerIsVOorVaultM();
        AnyToken = AnyToken.sub(_amount);

        bool success = collToken.transfer(_account, _amount);
        require(success, "AnyTokenActivePool: sending AnyToken failed");

        emit AnyTokenActivePoolAnyTokenBalanceUpdated(AnyToken);
        emit AnyTokenerSent(_account, _amount);
    }

    function increaseLUSDDebt(uint _amount) external override {
        _requireCallerIsVOorVaultM();
        LUSDDebt = LUSDDebt.add(_amount);
        emit AnyTokenActivePoolLUSDDebtUpdated(LUSDDebt);
    }

    function decreaseLUSDDebt(uint _amount) external override {
        _requireCallerIsVOorVaultM();
        LUSDDebt = LUSDDebt.sub(_amount);
        emit AnyTokenActivePoolLUSDDebtUpdated(LUSDDebt);
    }

    // --- 'require' functions ---

    function _requireCallerIsVaultOperations() internal view {
        require(
            msg.sender == anyTokenVaultOperationsAddress,
            "AnyTokenActivePool: Caller is VO");
    }

    function _requireCallerIsVOorVaultM() internal view {
        require(
            msg.sender == anyTokenVaultOperationsAddress ||
            msg.sender == anyTokenVaultManagerAddress,
            "AnyTokenActivePool: Caller is neither VaultOperations nor VaultManager");
    }

    // This function is used to replace the removed fallback function to receive funds and apply
    // additional logics.
    function depositColl(uint _amount) external override {
        _requireCallerIsVaultOperations();
        bool success = collToken.transferFrom(msg.sender, address(this), _amount);
        require(success, "AnyTokenActivePool: depositColl failed");
        AnyToken = AnyToken.add(_amount);
        emit AnyTokenActivePoolAnyTokenBalanceUpdated(AnyToken);
    } 
}
