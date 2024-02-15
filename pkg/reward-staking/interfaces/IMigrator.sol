// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMigrator {
    // Perform LP token migration from legacy LiquidityMining to newer version.
    // Take the current LP token address and return the new LP token address.
    // Migrator should have full access to the caller's LP token.
    // Return the new LP token address.
    //
    // XXX Migrator must have allowance access to LP tokens.
    // Must mint EXACTLY the same amount of LP tokens or
    // else something bad will happen.
    function migrate(IERC20 token) external returns (IERC20);
}
