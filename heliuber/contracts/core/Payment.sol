// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../libraries/SafeMath.sol";
import "../libraries/Stablecoin.sol";
import "../storage/HeliStorage.sol";

contract Payment is HeliStorage {
    using SafeMath for uint256;
    IERC20 private stablecoin;
    //address private creator;

    constructor(address _stablecoin, address _creator) {
        stablecoin = IERC20(_stablecoin);
        creator = _creator;
    }

    function processPayment(address passenger, uint256 amount, uint256 rideId) external {
        Ride storage ride = rides[rideId];
        require(ride.passenger == passenger, "Invalid passenger");
        require(ride.status == RideStatus.Pending, "Invalid status");
        Stablecoin.safeTransferFrom(stablecoin, passenger, address(this), amount);
        ride.status = RideStatus.Paid;
    }

    function releasePayment(uint256 rideId) external {
        Ride storage ride = rides[rideId];
        require(ride.status == RideStatus.BothConfirmed, "Not both confirmed");

        uint256 creatorFee = ride.price / 100;
        uint256 pilotAmount = ride.price - creatorFee;

        Stablecoin.safeTransfer(stablecoin, creator, creatorFee);
        Stablecoin.safeTransfer(stablecoin, ride.pilot, pilotAmount);

        ride.status = RideStatus.Completed;
    }
}
