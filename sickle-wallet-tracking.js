const { ethers } = require("ethers");
const TelegramBot = require("node-telegram-bot-api");
const cron = require("node-cron");
const fs = require("fs").promises;

// User data with Telegram chat IDs
const userData = [
 {
 username: "mytest",
 chatId: "YOUR_TELEGRAM_CHAT_ID", // Replace with actual chat ID
 addresses: ["0x0000000000000000000000000000000000000000", "0x1111111111111111111111111111111111111111"],
 },
];

// Network configurations
const networks = [
 { name: "Polygon", rpc: "https://polygon-rpc.com", chainId: 137, protocol: "UniswapV3" },
 { name: "Base", rpc: "https://mainnet.base.org", chainId: 8453, protocol: "Aerodrome" },
 { name: "Sonic", rpc: "https://rpc.soniclabs.com", chainId: 64165, protocol: "Shadow" }, // Verify chainId
 { name: "Arbitrum", rpc: "https://arb1.arbitrum.io/rpc", chainId: 42161, protocol: "UniswapV3" },
];

// Contract addresses
const CONTRACT_ADDRESSES = {
 Polygon: {
 sickleFactory: "0x...replace_with_polygon_sickle_factory_address...",
 positionManager: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88", // Uniswap V3
 poolFactory: "0x1F98431c8aD98523631AE4a59f267346ea31F984", // Uniswap V3 Factory
 },
 Base: {
 sickleFactory: "0x...replace_with_base_sickle_factory_address...",
 positionManager: "0x...replace_with_aerodrome_position_manager_address...", // Aerodrome
 poolFactory: "0x...replace_with_aerodrome_pool_factory_address...", // Aerodrome
 },
 Sonic: {
 sickleFactory: "0x...replace_with_sonic_sickle_factory_address...",
 positionManager: "0x...replace_with_shadow_position_manager_address...", // Shadow
 poolFactory: "0x...replace_with_shadow_pool_factory_address...", // Shadow
 },
 Arbitrum: {
 sickleFactory: "0x...replace_with_arbitrum_sickle_factory_address...",
 positionManager: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88", // Uniswap V3
 poolFactory: "0x1F98431c8aD98523631AE4a59f267346ea31F984", // Uniswap V3 Factory
 },
};

// SickleFactory ABI
const SICKLE_FACTORY_ABI = [
 "function getSickleAddress(address user) external view returns (address sickle)",
];

// Position Manager ABI (Uniswap V3, Aerodrome, Shadow; assumed compatible)
const POSITION_MANAGER_ABI = [
 "function positions(uint256 tokenId) external view returns (uint96 nonce, address operator, address token0, address token1, uint24 fee, int24 tickLower, int24 tickUpper, uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, uint128 tokensOwed0, uint128 tokensOwed1)",
 "event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)",
 "function balanceOf(address owner) external view returns (uint256 balance)",
 "function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256 tokenId)",
];

// Pool ABI (Uniswap V3, Aerodrome, Shadow; assumed compatible)
const POOL_ABI = [
 "function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked)",
];

// Pool Factory ABI (for Aerodrome and Shadow)
const POOL_FACTORY_ABI = [
 "function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool)",
];

// Telegram bot token
const TELEGRAM_BOT_TOKEN = "YOUR_TELEGRAM_BOT_TOKEN"; // Replace with your bot token
const bot = new TelegramBot(TELEGRAM_BOT_TOKEN, { polling: false });

// Storage file
const STORAGE_FILE = "outOfRange.json";

// Initialize storage
async function initStorage() {
 try {
 await fs.access(STORAGE_FILE);
 } catch {
 await fs.writeFile(STORAGE_FILE, JSON.stringify({ outOfRangeLPs: [], lastNotified: {} }));
 }
}

// Read storage data
async function readStorageData() {
 try {
 const data = await fs.readFile(STORAGE_FILE, "utf8");
 return JSON.parse(data);
 } catch {
 return { outOfRangeLPs: [], lastNotified: {} };
 }
}

// Write storage data
async function writeStorageData(data) {
 await fs.writeFile(STORAGE_FILE, JSON.stringify(data, null, 2));
}

// Fetch tokenIds for a Sickle wallet
async function getTokenIds(sickleAddress, positionManagerAddress, provider) {
 const positionManager = new ethers.Contract(positionManagerAddress, POSITION_MANAGER_ABI, provider);
 try {
 const filter = positionManager.filters.Transfer(null, sickleAddress, null);
 const events = await positionManager.queryFilter(filter, 0, "latest");
 const tokenIds = events.map((event) => event.args.tokenId);
 return [...new Set(tokenIds)]; // Remove duplicates
 } catch (error) {
 console.error(`Error querying Transfer events: ${error.message}`);
 // Fallback: Use balanceOf and tokenOfOwnerByIndex
 const balance = await positionManager.balanceOf(sickleAddress);
 const tokenIds = [];
 for (let i = 0; i < balance; i++) {
 const tokenId = await positionManager.tokenOfOwnerByIndex(sickleAddress, i);
 tokenIds.push(tokenId);
 }
 return tokenIds;
 }
}

// Get pool address (Uniswap V3, Aerodrome, or Shadow)
async function getPoolAddress(token0, token1, fee, poolFactoryAddress, provider, protocol) {
 if (protocol === "UniswapV3") {
 return ethers.getCreateAddress({
 from: poolFactoryAddress,
 nonce: ethers.keccak256(
 ethers.AbiCoder.defaultAbiCoder().encode(
 ["address", "address", "uint24"],
 [token0, token1, fee]
 )
 ),
 });
 } else if (protocol === "Aerodrome" || protocol === "Shadow") {
 const poolFactory = new ethers.Contract(poolFactoryAddress, POOL_FACTORY_ABI, provider);
 const [tokenA, tokenB] = token0.toLowerCase() < token1.toLowerCase() ? [token0, token1] : [token1, token0];
 return await poolFactory.getPool(tokenA, tokenB, fee);
 }
}

// Monitor LPs and send notifications
async function monitorAndNotify() {
 console.log(`Running LP monitor and notification at ${new Date().toISOString()}`);
 const storage = await readStorageData();
 let { outOfRangeLPs, lastNotified } = storage;
 const currentTime = Date.now();
 const oneDayMs = 24 * 60 * 60 * 1000;

 // Monitor LPs
 for (const user of userData) {
 for (const address of user.addresses) {
 for (const network of networks) {
 try {
 const provider = new ethers.JsonRpcProvider(network.rpc);
 const sickleFactory = new ethers.Contract(
 CONTRACT_ADDRESSES[network.name].sickleFactory,
 SICKLE_FACTORY_ABI,
 provider
 );
 const sickleAddress = await sickleFactory.getSickleAddress(address);

 if (sickleAddress === ethers.ZeroAddress) {
 console.log(`No Sickle wallet for ${address} on ${network.name}`);
 continue;
 }

 const tokenIds = await getTokenIds(
 sickleAddress,
 CONTRACT_ADDRESSES[network.name].positionManager,
 provider
 );
 if (tokenIds.length === 0) {
 console.log(`No LP positions for ${sickleAddress} on ${network.name}`);
 continue;
 }

 const positionManager = new ethers.Contract(
 CONTRACT_ADDRESSES[network.name].positionManager,
 POSITION_MANAGER_ABI,
 provider
 );

 for (const tokenId of tokenIds) {
 try {
 const position = await positionManager.positions(tokenId);
 if (position.liquidity === 0n) {
 console.log(`Position ${tokenId} has zero liquidity, skipping`);
 continue;
 }

 const poolAddress = await getPoolAddress(
 position.token0,
 position.token1,
 position.fee,
 CONTRACT_ADDRESSES[network.name].poolFactory,
 provider,
 network.protocol
 );

 const pool = new ethers.Contract(poolAddress, POOL_ABI, provider);
 const slot0 = await pool.slot0();
 const currentTick = slot0.tick;

 const isInRange =
 currentTick >= position.tickLower && currentTick <= position.tickUpper;

 const lpData = {
 username: user.username,
 chatId: user.chatId,
 address,
 network: network.name,
 protocol: network.protocol,
 sickleAddress,
 tokenId: tokenId.toString(),
 token0: position.token0,
 token1: position.token1,
 tickLower: position.tickLower,
 tickUpper: position.tickUpper,
 currentTick,
 timestamp: currentTime,
 };

 if (!isInRange) {
 console.log(
 `Out of range: ${user.username}, ${address}, ${network.name}, ${network.protocol}, TokenID ${tokenId}`
 );
 outOfRangeLPs = outOfRangeLPs.filter(
 (entry) =>
 !(
 entry.username === user.username &&
 entry.address === address &&
 entry.network === network.name &&
 entry.tokenId === tokenId.toString()
 )
 );
 outOfRangeLPs.push(lpData);
 } else {
 outOfRangeLPs = outOfRangeLPs.filter(
 (entry) =>
 !(
 entry.username === user.username &&
 entry.address === address &&
 entry.network === network.name &&
 entry.tokenId === tokenId.toString()
 )
 );
 }
 } catch (error) {
 console.error(
 `Error checking position ${tokenId} on ${network.name} for ${address}: ${error.message }`
 );
 }
 }
 } catch (error) {
 console.error(`Error on ${network.name} for ${address}: ${error.message}`);
 }
 }
 }
 }

 // Clean up old LP data (older than 24 hours)
 outOfRangeLPs = outOfRangeLPs.filter((entry) => currentTime - entry.timestamp <= oneDayMs);

 // Send notifications
 const userNotifications = {};
 for (const entry of outOfRangeLPs) {
 if (!userNotifications[entry.username]) {
 userNotifications[entry.username] = {
 chatId: entry.chatId,
 outOfRangeLPs: [],
 };
 }
 userNotifications[entry.username].outOfRangeLPs.push(entry);
 }

 for (const [username, { chatId, outOfRangeLPs }] of Object.entries(userNotifications)) {
 if (outOfRangeLPs.length === 0) continue;
 const lastNotifiedTime = lastNotified[username] || 0;
 if (currentTime - lastNotifiedTime < oneDayMs) {
 console.log(`Skipping notification for ${username}: Already notified within 24 hours`);
 continue;
 }

 let message = `Hello ${username},\nThe following liquidity pool positions are out of range:\n\n`;
 for (const lp of outOfRangeLPs) {
 message += `Network: ${lp.network}\n`;
 message += `Protocol: ${lp.protocol}\n`;
 message += `Address: ${lp.address}\n`;
 message += `Sickle Wallet: ${lp.sickleAddress}\n`;
 message += `TokenID: ${lp.tokenId}\n`;
 message += `Pool: ${lp.token0}/${lp.token1}\n`;
 message += `Tick Range: ${lp.tickLower} to ${lp.tickUpper}\n`;
 message += `Current Tick: ${lp.currentTick}\n\n`;
 }
 try {
 await bot.sendMessage(chatId, message);
 console.log(`Notification sent to ${username} (${chatId})`);
 lastNotified[username] = currentTime;
 } catch (error) {
 console.error(`Failed to send notification to ${username}: ${error.message}`);
 }
 }

 // Save updated storage
 await writeStorageData({ outOfRangeLPs, lastNotified });
}

// Run hourly cron job
async function main() {
 await initStorage();
 console.log("Starting hourly LP monitoring and notification cron job");
 cron.schedule("0 * * * *", monitorAndNotify); // Run every hour
}

main().catch(console.error);
