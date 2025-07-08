// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../interfaces/IHeliUber.sol";
import "../core/Booking.sol";
import "../core/Payment.sol";
import "../access/AccessControl.sol";

contract HeliUber is IHeliUber, AccessControl {
    Booking private booking;
    Payment private payment;

    constructor(address _stablecoin) {
        booking = new Booking();
        payment = new Payment(_stablecoin, msg.sender);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function bookRide(address pilot, uint256 price, bytes32 destination) external onlyRole(PASSENGER_ROLE) {
        require(pilots[pilot], "Invalid pilot");
        uint256 rideId = booking.createBooking(msg.sender, pilot, price, destination);
        payment.processPayment(msg.sender, price, rideId);
        emit RideBooked(rideId, msg.sender, pilot, price);
    }

    function confirmRide(uint256 rideId) external {
        require(hasRole(PASSENGER_ROLE, msg.sender) || hasRole(PILOT_ROLE, msg.sender), "Invalid role");
        booking.confirmBooking(rideId, msg.sender);
        emit RideConfirmed(rideId, msg.sender);

        if (booking.isBothConfirmed(rideId)) {
            payment.releasePayment(rideId);
            emit RideCompleted(rideId, rides[rideId].price * 99 / 100, rides[rideId].price / 100);
        }
    }
}
