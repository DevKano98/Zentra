import hre from 'hardhat';
const { ethers } = hre;
import { expect } from 'chai';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs.js';

describe('CallRecord', function () {
  let contract;
  let owner;
  let otherAccount;
  let testHash;

  beforeEach(async function () {
    [owner, otherAccount] = await ethers.getSigners();
    const Factory = await ethers.getContractFactory('CallRecord');
    contract = await Factory.deploy();
    await contract.waitForDeployment();
    testHash = ethers.keccak256(ethers.toUtf8Bytes('test-call-001'));
  });

  it('should deploy and set owner correctly', async function () {
    expect(await contract.getOwner()).to.equal(owner.address);
    expect(await contract.totalRecords()).to.equal(0);
  });

  it('should store a record successfully', async function () {
    await contract.storeRecord(testHash, 'user-001', 'DELIVERY', false);
    expect(await contract.totalRecords()).to.equal(1);
    expect(await contract.exists(testHash)).to.equal(true);
  });

  it('should return true for stored hash in verifyRecord', async function () {
    await contract.storeRecord(testHash, 'user-001', 'SCAM', true);
    expect(await contract.verifyRecord(testHash)).to.equal(true);
  });

  it('should return false for unstored hash in verifyRecord', async function () {
    const fakeHash = ethers.keccak256(ethers.toUtf8Bytes('fake-hash'));
    expect(await contract.verifyRecord(fakeHash)).to.equal(false);
  });

  it('should return correct CallData from getRecord', async function () {
    await contract.storeRecord(testHash, 'user-001', 'SCAM', true);
    const record = await contract.getRecord(testHash);
    expect(record.userId).to.equal('user-001');
    expect(record.category).to.equal('SCAM');
    expect(record.isScam).to.equal(true);
  });

  it('should revert on duplicate hash', async function () {
    await contract.storeRecord(testHash, 'user-001', 'SCAM', true);
    await expect(
      contract.storeRecord(testHash, 'user-002', 'SCAM', true)
    ).to.be.revertedWith('Record already exists');
  });

  it('should revert when called by non-owner', async function () {
    await expect(
      contract.connect(otherAccount).storeRecord(testHash, 'user-001', 'SCAM', true)
    ).to.be.revertedWith('Not owner');
  });

  it('should emit RecordStored event', async function () {
    await expect(contract.storeRecord(testHash, 'user-001', 'DELIVERY', false))
      .to.emit(contract, 'RecordStored')
      .withArgs(testHash, 'DELIVERY', false, anyValue);
  });

  it('should emit ScamFlagged event when isScam is true', async function () {
    await expect(contract.storeRecord(testHash, 'user-001', 'SCAM', true))
      .to.emit(contract, 'ScamFlagged')
      .withArgs(testHash, anyValue);
  });
});