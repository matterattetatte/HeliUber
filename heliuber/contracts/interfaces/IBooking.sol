// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IBooking {
    function createBooking(address passenger, address pilot, uint256 price, bytes32 destination) external returns (uint256);
    function confirmBooking(uint256 rideId, address confirmer) external;
    function isBothConfirmed(uint256 rideId) external view returns (bool);
}
