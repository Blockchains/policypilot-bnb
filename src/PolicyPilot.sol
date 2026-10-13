// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title PolicyPilot - bounded transaction execution (non-upgradeable reference implementation)
/// @notice An executor can pay allowlisted recipients in a single ERC-20 asset, bounded by a
///         per-request limit and a cumulative budget, with requestId replay protection.
contract PolicyPilot {
    using SafeERC20 for IERC20;

    error NotAdmin();
    error NotExecutor();
    error Paused();
    error ZeroAddress();
    error ZeroAmount();
    error RecipientNotAllowed(address recipient);
    error PerRequestLimitExceeded(uint256 amount, uint256 limit);
    error BudgetExceeded(uint256 requested, uint256 remaining);
    error RequestAlreadyExecuted(bytes32 requestId);

    event Executed(bytes32 indexed requestId, address indexed recipient, uint256 amount, uint256 totalSpent);
    event RecipientSet(address indexed recipient, bool allowed);
    event ExecutorSet(address indexed executor);
    event AdminTransferred(address indexed previousAdmin, address indexed newAdmin);
    event PerRequestLimitSet(uint256 limit);
    event BudgetSet(uint256 budget);
    event PausedSet(bool paused);

    IERC20 public immutable asset;
    address public admin;
    address public executor;
    uint256 public perRequestLimit;
    uint256 public budget;
    uint256 public totalSpent;
    bool public paused;
    mapping(address => bool) public allowedRecipient;
    mapping(bytes32 => bool) public executed;

    modifier onlyAdmin() { if (msg.sender != admin) revert NotAdmin(); _; }

    constructor(IERC20 asset_, address admin_, address executor_, uint256 perRequestLimit_, uint256 budget_) {
        if (address(asset_) == address(0) || admin_ == address(0) || executor_ == address(0)) revert ZeroAddress();
        asset = asset_;
        admin = admin_;
        executor = executor_;
        perRequestLimit = perRequestLimit_;
        budget = budget_;
        emit AdminTransferred(address(0), admin_);
        emit ExecutorSet(executor_);
        emit PerRequestLimitSet(perRequestLimit_);
        emit BudgetSet(budget_);
    }

    function remainingBudget() public view returns (uint256) {
        return budget > totalSpent ? budget - totalSpent : 0;
    }

    /// @notice Execute a bounded payout. Checks -> effects -> interaction.
    function execute(bytes32 requestId, address recipient, uint256 amount) external {
        if (msg.sender != executor) revert NotExecutor();
        if (paused) revert Paused();
        if (executed[requestId]) revert RequestAlreadyExecuted(requestId);
        if (amount == 0) revert ZeroAmount();
        if (!allowedRecipient[recipient]) revert RecipientNotAllowed(recipient);
        if (amount > perRequestLimit) revert PerRequestLimitExceeded(amount, perRequestLimit);
        uint256 rem = remainingBudget();
        if (amount > rem) revert BudgetExceeded(amount, rem);

        executed[requestId] = true;
        totalSpent += amount;
        emit Executed(requestId, recipient, amount, totalSpent);

        asset.safeTransfer(recipient, amount);
    }

    function setRecipient(address r, bool allowed) external onlyAdmin {
        if (r == address(0)) revert ZeroAddress();
        allowedRecipient[r] = allowed;
        emit RecipientSet(r, allowed);
    }
    function setExecutor(address e) external onlyAdmin {
        if (e == address(0)) revert ZeroAddress();
        executor = e; emit ExecutorSet(e);
    }
    function transferAdmin(address a) external onlyAdmin {
        if (a == address(0)) revert ZeroAddress();
        emit AdminTransferred(admin, a); admin = a;
    }
    function setPerRequestLimit(uint256 l) external onlyAdmin { perRequestLimit = l; emit PerRequestLimitSet(l); }
    function setBudget(uint256 b) external onlyAdmin { budget = b; emit BudgetSet(b); }
    function setPaused(bool p) external onlyAdmin { paused = p; emit PausedSet(p); }
}
