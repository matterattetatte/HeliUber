#!/bin/bash

# Setup script for HeliUber React frontend on Sonic Network with ethers.js
# Creates frontend directory, bootstraps React app, and configures for Sonic

PROJECT_DIR="heliuber"
FRONTEND_DIR="$PROJECT_DIR/frontend"
ARTIFACTS_DIR="$PROJECT_DIR/artifacts/contracts/core/HeliUber.sol"

# Check if project directory exists
if [ ! -d "$PROJECT_DIR" ]; then
  echo "Error: Project directory '$PROJECT_DIR' not found. Run setup_heliuber.sh first."
  exit 1
fi

# Check if artifacts exist
if [ ! -f "$ARTIFACTS_DIR/HeliUber.json" ]; then
  echo "Error: HeliUber.json artifact not found. Run 'npx hardhat compile' in '$PROJECT_DIR' first."
  exit 1
fi

# Create frontend directory
mkdir -p "$FRONTEND_DIR"
cd "$FRONTEND_DIR" || exit 1

# Initialize React app with create-react-app
if [ ! -d "node_modules" ]; then
  echo "Creating React app..."
  npx create-react-app . --template minimal
else
  echo "React app already initialized in $FRONTEND_DIR"
fi

# Install ethers.js and dotenv
echo "Installing ethers.js and dotenv..."
npm install ethers dotenv

# Create .env file
cat << EOF > .env
REACT_APP_CONTRACT_ADDRESS=0xYourHeliUberContractAddressHere
REACT_APP_STABLECOIN_ADDRESS=0xYourStablecoinAddressHere
REACT_APP_NETWORK_URL=https://rpc.soniclabs.com
REACT_APP_CHAIN_ID=641
EOF
echo "Created .env file. Update with Sonic Network RPC, chain ID, and contract addresses."

# Create .gitignore
cat << EOF > .gitignore
# Node.js dependencies
node_modules/
package-lock.json

# Build output
build/

# Environment files
.env

# MacOS
.DS_Store
EOF
echo "Created frontend .gitignore"

# Create src/contracts directory and copy ABI
mkdir -p src/contracts
cp "$ARTIFACTS_DIR/HeliUber.json" src/contracts/
echo "Copied HeliUber.json ABI to src/contracts/"

# Create Web3 context
cat << EOF > src/Web3Context.js
import { createContext, useContext, useEffect, useState } from 'react';
import { ethers } from 'ethers';
import HeliUberABI from './contracts/HeliUber.json';

const Web3Context = createContext();

export const Web3Provider = ({ children }) => {
  const [provider, setProvider] = useState(null);
  const [signer, setSigner] = useState(null);
  const [contract, setContract] = useState(null);
  const [account, setAccount] = useState(null);
  const [chainId, setChainId] = useState(null);

  useEffect(() => {
    const init = async () => {
      if (window.ethereum) {
        const provider = new ethers.providers.Web3Provider(window.ethereum);
        setProvider(provider);

        const network = await provider.getNetwork();
        setChainId(network.chainId);

        const expectedChainId = parseInt(process.env.REACT_APP_CHAIN_ID, 10);
        if (network.chainId !== expectedChainId) {
          alert('Please connect to the Sonic Network!');
          return;
        }

        const signer = provider.getSigner();
        setSigner(signer);

        const accounts = await provider.listAccounts();
        if (accounts.length > 0) {
          setAccount(accounts[0]);
        }

        const contractAddress = process.env.REACT_APP_CONTRACT_ADDRESS;
        const contract = new ethers.Contract(contractAddress, HeliUberABI.abi, signer);
        setContract(contract);

        window.ethereum.on('accountsChanged', (accounts) => {
          setAccount(accounts[0] || null);
        });

        window.ethereum.on('chainChanged', () => {
          window.location.reload();
        });
      } else {
        alert('Please install MetaMask or Sonic Wallet!');
      }
    };
    init();
  }, []);

  return (
    <Web3Context.Provider value={{ provider, signer, contract, account, chainId }}>
      {children}
    </Web3Context.Provider>
  );
};

export const useWeb3 = () => useContext(Web3Context);
EOF
echo "Created Web3Context.js for Sonic Network integration"

# Create main App component
cat << EOF > src/App.js
import { useState } from 'react';
import { ethers } from 'ethers';
import { Web3Provider, useWeb3 } from './Web3Context';
import './App.css';

function AppContent() {
  const { provider, signer, contract, account, chainId } = useWeb3();
  const [destination, setDestination] = useState('');
  const [price, setPrice] = useState('');
  const [pilotAddress, setPilotAddress] = useState('');
  const [rideId, setRideId] = useState('');
  const [status, setStatus] = useState('');

  const stablecoinAddress = process.env.REACT_APP_STABLECOIN_ADDRESS;

  const connectWallet = async () => {
    if (window.ethereum) {
      await window.ethereum.request({ method: 'eth_requestAccounts' });
    } else {
      alert('Please install MetaMask or Sonic Wallet!');
    }
  };

  const approveStablecoin = async () => {
    if (!contract || !account) return;
    try {
      const stablecoin = new ethers.Contract(
        stablecoinAddress,
        ['function approve(address spender, uint256 amount) public returns (bool)'],
        signer
      );
      const tx = await stablecoin.approve(contract.address, ethers.utils.parseUnits(price, 6));
      await tx.wait();
      setStatus('Stablecoin approved!');
    } catch (error) {
      setStatus('Error: ' + error.message);
    }
  };

  const bookRide = async () => {
    if (!contract || !account) return;
    try {
      const tx = await contract.bookRide(
        pilotAddress,
        ethers.utils.parseUnits(price, 6),
        ethers.utils.formatBytes32String(destination)
      );
      await tx.wait();
      setStatus('Ride booked!');
    } catch (error) {
      setStatus('Error: ' + error.message);
    }
  };

  const confirmRide = async () => {
    if (!contract || !account) return;
    try {
      const tx = await contract.confirmRide(rideId);
      await tx.wait();
      setStatus('Ride confirmed!');
    } catch (error) {
      setStatus('Error: ' + error.message);
    }
  };

  return (
    <div className="App">
      <h1>HeliUber on Sonic Network</h1>
      {!account ? (
        <button onClick={connectWallet}>Connect Wallet</button>
      ) : (
        <div>
          <p>Connected: {account}</p>
          <p>Network: Sonic (Chain ID: {chainId})</p>
          <h2>Book a Ride</h2>
          <input
            type="text"
            placeholder="Pilot Address"
            value={pilotAddress}
            onChange={(e) => setPilotAddress(e.target.value)}
          />
          <input
            type="text"
            placeholder="Destination"
            value={destination}
            onChange={(e) => setDestination(e.target.value)}
          />
          <input
            type="number"
            placeholder="Price (USDC)"
            value={price}
            onChange={(e) => setPrice(e.target.value)}
          />
          <button onClick={approveStablecoin}>Approve USDC</button>
          <button onClick={bookRide}>Book Ride</button>
          <h2>Confirm Ride</h2>
          <input
            type="number"
            placeholder="Ride ID"
            value={rideId}
            onChange={(e) => setRideId(e.target.value)}
          />
          <button onClick={confirmRide}>Confirm Ride</button>
          <p>Status: {status}</p>
        </div>
      )}
    </div>
  );
}

function App() {
  return (
    <Web3Provider>
      <AppContent />
    </Web3Provider>
  );
}

export default App;
EOF
echo "Created App.js with Sonic-specific UI"

# Update App.css
cat << EOF > src/App.css
.App {
  text-align: center;
  padding: 20px;
}

input {
  margin: 10px;
  padding: 5px;
}

button {
  margin: 10px;
  padding: 10px 20px;
  background-color: #007bff;
  color: white;
  border: none;
  cursor: pointer;
}

button:hover {
  background-color: #0056b3;
}
EOF
echo "Updated App.css"

# Update package.json
cat << EOF > package.json
{
  "name": "heliuber-frontend",
  "version": "0.1.0",
  "private": true,
  "dependencies": {
    "@testing-library/jest-dom": "^5.17.0",
    "@testing-library/react": "^13.4.0",
    "@testing-library/user-event": "^13.5.0",
    "ethers": "^5.7.2",
    "dotenv": "^16.4.5",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-scripts": "5.0.1",
    "web-vitals": "^2.1.4"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "test": "react-scripts test",
    "eject": "react-scripts eject"
  },
  "eslintConfig": {
    "extends": [
      "react-app",
      "react-app/jest"
    ]
  },
  "browserslist": {
    "production": [
      ">0.2%",
      "not dead",
      "not op_mini all"
    ],
    "development": [
      "last 1 chrome version",
      "last 1 firefox version",
      "last 1 safari version"
    ]
  }
}
EOF
echo "Updated package.json"

# Update README
cat << EOF >> ../../README.md

## Frontend Setup (Sonic Network)

The frontend is located in \`frontend/\` and built with React and ethers.js for Sonic Network integration.

### Prerequisites
- Node.js and npm installed.
- MetaMask or Sonic Wallet configured for Sonic Network (add via RPC: \`https://rpc.soniclabs.com\`, chain ID: 641).
- Deployed \`HeliUber\` and stablecoin contracts on Sonic (update \`.env\` with addresses).
- S tokens for gas fees (acquire via exchange or testnet faucet).

### Setup
1. Navigate to frontend:
   \`\`\`bash
   cd frontend
   \`\`\`
2. Install dependencies:
   \`\`\`bash
   npm install
   \`\`\`
3. Update \`.env\`:
   - Set \`REACT_APP_CONTRACT_ADDRESS\` to your deployed \`HeliUber\` address.
   - Set \`REACT_APP_STABLECOIN_ADDRESS\` to native USDC or deployed \`MockStablecoin\`.
   - Verify \`REACT_APP_NETWORK_URL\` and \`REACT_APP_CHAIN_ID\` for Sonic mainnet or testnet.
4. Start the app:
   \`\`\`bash
   npm start
   \`\`\`
   - Opens at \`http://localhost:3000\`.

### Features
- Connect to MetaMask or Sonic Wallet.
- Book rides (pilot address, destination, USDC price).
- Approve USDC spending for payments.
- Confirm rides by ride ID.
- Display transaction status and account details.

### Deploying Contracts
1. Update Hardhat config (\`hardhat.config.js\`) with Sonic Network:
   \`\`\`javascript
   networks: {
     sonic: {
       url: "https://rpc.soniclabs.com",
       accounts: ["0xYourPrivateKey"]
     }
   }
   \`\`\`
2. Deploy contracts:
   \`\`\`bash
   npx hardhat run scripts/deploy.js --network sonic
   \`\`\`
3. Update \`.env\` with deployed addresses.
EOF
echo "Updated README.md with Sonic frontend instructions"

# Create sample deploy script
mkdir -p ../../scripts
cat << EOF > ../../scripts/deploy.js
const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);

  const MockStablecoin = await hre.ethers.getContractFactory("MockStablecoin");
  const stablecoin = await MockStablecoin.deploy();
  await stablecoin.deployed();
  console.log("MockStablecoin deployed to:", stablecoin.address);

  const HeliUber = await hre.ethers.getContractFactory("HeliUber");
  const heliUber = await HeliUber.deploy(stablecoin.address);
  await heliUber.deployed();
  console.log("HeliUber deployed to:", heliUber.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
EOF
echo "Created sample deploy script in scripts/deploy.js"

# Make script executable
chmod +x "$0"

echo "HeliUber frontend for Sonic Network created in $FRONTEND_DIR"
echo "Next steps:"
echo "1. Deploy contracts to Sonic Network (update hardhat.config.js and run 'npx hardhat run scripts/deploy.js --network sonic')."
echo "2. Update $FRONTEND_DIR/.env with contract addresses, Sonic RPC, and chain ID."
echo "3. cd $FRONTEND_DIR"
echo "4. npm install"
echo "5. npm start"
echo "6. Configure MetaMask or Sonic Wallet for Sonic Network."
