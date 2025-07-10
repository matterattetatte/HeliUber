// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract HeliAccessControl is AccessControl {
    bytes32 public constant PILOT_ROLE = keccak256("PILOT_ROLE");
    bytes32 public constant PASSENGER_ROLE = keccak256("PASSENGER_ROLE");

    function registerPilot(address pilot) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(PILOT_ROLE, pilot);
    }

    function registerPassenger(address passenger) external {
        _grantRole(PASSENGER_ROLE, passenger);
    }
}
