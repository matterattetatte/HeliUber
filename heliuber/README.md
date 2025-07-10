# HeliUber

A decentralized Uber for helicopter pilots and passengers, using stablecoin payments.

## Setup

1. Install dependencies:
   ```bash
   npm install
   ```

2. Compile contracts:
   ```bash
   npx hardhat compile
   ```

3. Deploy contracts with Hardhat (update scripts as needed).

## Structure

- `contracts/`: Solidity smart contracts
  - `interfaces/`: Contract interfaces
  - `core/`: Main logic (HeliUber, Booking, Payment)
  - `access/`: Role-based access control
  - `libraries/`: Reusable utilities
  - `mocks/`: Mock contracts for testing
  - `storage/`: Shared storage

## Testing

Run tests with:
```bash
npx hardhat test
```

The test suite in `test/HeliUber.test.js` covers:
- Ride booking with valid and invalid pilots.
- Passenger and pilot confirmation.
- Payment release with 1% creator fee.
- Edge cases for unauthorized actions and duplicate confirmations.

## Testing

Run tests with:
```bash
npx hardhat test
```

The test suite in `test/HeliUber.test.js` covers:
- Ride booking with valid and invalid pilots.
- Passenger and pilot confirmation.
- Payment release with 1% creator fee.
- Edge cases for unauthorized actions and duplicate confirmations.
