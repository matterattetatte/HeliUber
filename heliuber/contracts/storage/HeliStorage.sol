// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract HeliStorage {
    enum RideStatus { Pending, Paid, PassengerConfirmed, BothConfirmed, Completed, Cancelled }

    struct Ride {
        address passenger;
        address pilot;
        uint256 price;
        bytes32 destination;
        RideStatus status;
        bool passengerConfirmed;
        bool pilotConfirmed;
    }

    mapping(uint256 => Ride) public rides;
    uint256 public rideCount;
    address public creator;

    mapping(address => bool) public pilots;
}
