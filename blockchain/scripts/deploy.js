import hre from 'hardhat';
const { ethers } = hre;
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log('Deploying from:', deployer.address);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log('Balance:', ethers.formatEther(balance), 'MATIC');

  const Factory = await ethers.getContractFactory('CallRecord');
  const contract = await Factory.deploy();
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log('CallRecord deployed to:', address);
  console.log('IMPORTANT — copy above address to backend/.env as CONTRACT_ADDRESS');

  const artifactPath = path.join(__dirname, '../artifacts/contracts/CallRecord.sol/CallRecord.json');
  const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));
  const abiPath = path.join(__dirname, '../../backend/blockchain_abi.json');
  fs.writeFileSync(abiPath, JSON.stringify(artifact.abi, null, 2));
  console.log('ABI saved to backend/blockchain_abi.json');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});