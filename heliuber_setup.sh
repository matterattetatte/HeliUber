#!/bin/bash

# Setup script for HeliUber Solidity project
# Creates directory structure and all Solidity files with Solidity version 0.8.30

PROJECT_DIR="heliuber"
CONTRACTS_DIR="$PROJECT_DIR/contracts"
INTERFACES_DIR="$CONTRACTS_DIR/interfaces"
CORE_DIR="$CONTRACTS_DIR/core"
ACCESS_DIR="$CONTRACTS_DIR/access"
LIBRARIES_DIR="$CONTRACTS_DIR/libraries"
MOCKS_DIR="$CONTRACTS_DIR/mocks"
STORAGE_DIR="$CONTRACTS_DIR/storage"

# Create project directories
mkdir -p "$INTERFACES_DIR" "$CORE_DIR" "$ACCESS_DIR" "$LIBRARIES_DIR" "$MOCKS_DIR" "$STORAGE_DIR"

# Create Solidity files
cat << EOF > "$INTERFACES_DIR/IHeliUber.sol"
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IHeliUber {
    event RideBooked(uint256 indexed rideId, address passenger, address pilot, uint256 price);
    event RideConfirmed(uint256 indexed rideId, address confirmer);
    event RideCompleted(uint256 indexed rideId, uint256 pilotAmount, uint256 creatorFee);

    function bookRide(address pilot, uint256 price, bytes32 destination) external;
    function confirmRide(uint256 rideId) external;
}
EOF

cat << EOF > "$INTERFACES_DIR/IPayment.sol"
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IPayment {
    function processPayment(address passenger, uint256 amount, uint256 rideId) external;
    function releasePayment(uint256 rideId) external;
}
EOF

cat << EOF > "$INTERFACES_DIR/IBooking.sol"
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IBooking {
    function createBooking(address passenger, address pilot, uint256 price, bytes32 destination) external returns (uint256);
    function confirmBooking(uint256 rideId, address confirmer) external;
    function isBothConfirmed(uint256 rideId) external view returns (bool);
}
EOF

cat << EOF > "$INTERFACES_DIR/IAccessControl.sol"
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IAccessControl {
    function registerPilot(address pilot) external;
    function registerPassenger(address passenger) external;
}
EOF

cat << EOF > "$STORAGE_DIR/HeliStorage.sol"
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
EOF

cat << EOF > "$CORE_DIR/HeliUber.sol"
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
EOF

cat << EOF > "$CORE_DIR/Booking.sol"
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../storage/HeliStorage.sol";
import "../libraries/SafeMath.sol";

contract Booking is HeliStorage {
    using SafeMath for uint256;

    function createBooking(address passenger, address pilot, uint256 price, bytes32 destination) external returns (uint256) {
        uint256 rideId = rideCount++;
        rides[rideId] = Ride({
            passenger: passenger,
            pilot: pilot,
            price: price,
            destination: destination,
            status: RideStatus.Pending,
            passengerConfirmed: false,
            pilotConfirmed: false
        });
        return rideId;
    }

    function confirmBooking(uint256 rideId, address confirmer) external {
        Ride storage ride = rides[rideId];
        require(ride.status == RideStatus.Paid, "Ride not paid");
        require(confirmer == ride.passenger || confirmer == ride.pilot, "Invalid confirmer");

        if (confirmer == ride.passenger) {
            require(!ride.passengerConfirmed, "Passenger already confirmed");
            ride.passengerConfirmed = true;
            ride.status = RideStatus.PassengerConfirmed;
        } else if (confirmer == ride.pilot) {
            require(!ride.pilotConfirmed, "Pilot already confirmed");
            ride.pilotConfirmed = true;
            if (ride.passengerConfirmed) {
                ride.status = RideStatus.BothConfirmed;
            }
        }
    }

    function isBothConfirmed(uint256 rideId) external view returns (bool) {
        Ride storage ride = rides[rideId];
        return ride.passengerConfirmed && ride.pilotConfirmed;
    }
}
EOF

cat << EOF > "$CORE_DIR/Payment.sol"
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../libraries/SafeMath.sol";
import "../libraries/Stablecoin.sol";
import "../storage/HeliStorage.sol";

contract Payment is HeliStorage {
    using SafeMath for uint256;
    IERC20 private stablecoin;
    address private creator;

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
EOF

cat << EOF > "$ACCESS_DIR/AccessControl.sol"
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract AccessControl is AccessControl {
    bytes32 public constant PILOT_ROLE = keccak256("PILOT_ROLE");
    bytes32 public constant PASSENGER_ROLE = keccak256("PASSENGER_ROLE");

    function registerPilot(address pilot) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(PILOT_ROLE, pilot);
    }

    function registerPassenger(address passenger) external {
        _grantRole(PASSENGER_ROLE, passenger);
    }
}
EOF

cat << EOF > "$ACCESS_DIR/Ownable.sol"
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
EOF

cat << EOF > "$LIBRARIES_DIR/SafeMath.sol"
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        return a - b;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        return a / b;
    }
}
EOF

cat << EOF > "$LIBRARIES_DIR/Stablecoin.sol"
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
EOF

cat << EOF > "$MOCKS_DIR/MockStablecoin.sol"
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockStablecoin is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        _mint(msg.sender, 1000000 * 10**decimals());
    }
}
EOF

# Create Hardhat config
cat << EOF > "$PROJECT_DIR/hardhat.config.js"
require("@nomicfoundation/hardhat-toolbox");

module.exports = {
  solidity: "0.8.30",
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  }
};
EOF

# Create package.json
cat << EOF > "$PROJECT_DIR/package.json"
{
  "name": "heliuber",
  "version": "1.0.0",
  "description": "Uber for helicopter pilots and passengers",
  "scripts": {
    "compile": "hardhat compile",
    "test": "hardhat test"
  },
  "devDependencies": {
    "@nomicfoundation/hardhat-toolbox": "^5.0.0",
    "@openzeppelin/contracts": "^5.0.2",
    "hardhat": "^2.22.10"
  }
}
EOF

# Create README
cat << EOF > "$PROJECT_DIR/README.md"
# HeliUber

A decentralized Uber for helicopter pilots and passengers, using stablecoin payments.

## Setup

1. Install dependencies:
   \`\`\`bash
   npm install
   \`\`\`

2. Compile contracts:
   \`\`\`bash
   npx hardhat compile
   \`\`\`

3. Deploy contracts with Hardhat (update scripts as needed).

## Structure

- \`contracts/\`: Solidity smart contracts
  - \`interfaces/\`: Contract interfaces
  - \`core/\`: Main logic (HeliUber, Booking, Payment)
  - \`access/\`: Role-based access control
  - \`libraries/\`: Reusable utilities
  - \`mocks/\`: Mock contracts for testing
  - \`storage/\`: Shared storage
EOF

# Make script executable
chmod +x "$0"

echo "HeliUber project structure created in $PROJECT_DIR"
echo "Next steps:"
echo "1. cd $PROJECT_DIR"
echo "2. npm install"
echo "3. npx hardhat compile"
