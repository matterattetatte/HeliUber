// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library Stablecoin {
    function safeTransfer(IERC20 token, address to, uint256 amount) internal returns (bool) {
        bool success = token.transfer(to, amount);
        require(success, "Transfer failed");
        return success;
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 amount) internal returns (bool) {
        bool success = token.transferFrom(from, to, amount);
        require(success, "TransferFrom failed");
        return success;
    }
}
