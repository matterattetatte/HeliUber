// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IAccessControl {
    function registerPilot(address pilot) external;
    function registerPassenger(address passenger) external;
}
