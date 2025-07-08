// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IPayment {
    function processPayment(address passenger, uint256 amount, uint256 rideId) external;
    function releasePayment(uint256 rideId) external;
}
