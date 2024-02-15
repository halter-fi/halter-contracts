// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TRewardToken is ERC20 {
    constructor(uint256 supply) ERC20("Reward Token", "RT") {
        _mint(msg.sender, supply);
    }
}