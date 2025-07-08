// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IHeliUber {
    event RideBooked(uint256 indexed rideId, address passenger, address pilot, uint256 price);
    event RideConfirmed(uint256 indexed rideId, address confirmer);
    event RideCompleted(uint256 indexed rideId, uint256 pilotAmount, uint256 creatorFee);

    function bookRide(address pilot, uint256 price, bytes32 destination) external;
    function confirmRide(uint256 rideId) external;
}
