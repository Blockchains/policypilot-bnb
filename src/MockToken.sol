// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
/// @notice Test-only token. No real value.
contract MockToken is ERC20 {
    constructor() ERC20("Mock USD", "mUSD") {}
    function mint(address to, uint256 amt) external { _mint(to, amt); }
}
