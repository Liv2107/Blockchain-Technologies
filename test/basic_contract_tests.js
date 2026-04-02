const { expect } = require("chai");
const { ethers } = require("hardhat");

const contractName = "EnergyTrading";

describe("EnergyTrading Comprehensive Tests", function () {
    let EnergyTrading, contract, recorder, prosumer1, prosumer2, prosumer3;

    beforeEach(async function () {
        [recorder, prosumer1, prosumer2, prosumer3] = await ethers.getSigners();
        EnergyTrading = await ethers.getContractFactory(contractName);
        contract = await EnergyTrading.deploy(recorder.address);
    });

    // basic template tests
    it("Should deploy with correct recorder address", async function () {
        expect(await contract.getRecorder()).to.equal(recorder.address);
    });

    it("Should allow prosumers to register and have correct initial state", async function () {
        await contract.connect(prosumer1).registerProsumer();
        const prosumerData = await contract.prosumers(prosumer1.address);
        expect(prosumerData.prosumerEnergyStat).to.equal(0);
        expect(prosumerData.prosumerBalance).to.equal(0);
        expect(prosumerData.isMember).to.equal(true);
    });

    it("Should allow a registered prosumer to deposit Ethers", async function () {
        await contract.connect(prosumer1).registerProsumer();
        await contract.connect(prosumer1).deposit({ value: ethers.parseEther("1") });
        const prosumerData = await contract.prosumers(prosumer1.address);
        expect(prosumerData.prosumerBalance).to.equal(ethers.parseEther("1"));
    });

    it("Should allow recorder to update energy status of prosumers", async function () {
        await contract.connect(prosumer1).registerProsumer();
        await contract.connect(prosumer2).registerProsumer();
        await contract.connect(recorder).updateEnergyStatus(prosumer1.address, -1);
        await contract.connect(recorder).updateEnergyStatus(prosumer2.address, 1);
        const prosumer1Data = await contract.prosumers(prosumer1.address);
        const prosumer2Data = await contract.prosumers(prosumer2.address);
        expect(prosumer1Data.prosumerEnergyStat).to.equal(-1);
        expect(prosumer2Data.prosumerEnergyStat).to.equal(1);
    });

    // extended security and logic tests
    it("Should not allow the same address to register twice", async function () {
        await contract.connect(prosumer1).registerProsumer();
        await expect(contract.connect(prosumer1).registerProsumer())
            .to.be.revertedWith("Already registered.");
    });

    it("Should not allow non-recorder to update energy status", async function () {
        await contract.connect(prosumer1).registerProsumer();
        await expect(contract.connect(prosumer1).updateEnergyStatus(prosumer1.address, 1))
            .to.be.revertedWith("Only the recorder is valid.");
    });

    it("Should not allow recorder to update an unregistered prosumer", async function () {
        await expect(contract.connect(recorder).updateEnergyStatus(prosumer1.address, 1))
            .to.be.revertedWith("Target prosumer not registered.");
    });

    it("Should not allow buyers to request more energy than their deficit", async function () {
        await contract.connect(prosumer1).registerProsumer();
        await contract.connect(prosumer2).registerProsumer();
        await contract.connect(recorder).updateEnergyStatus(prosumer1.address, -5);
        await contract.connect(recorder).updateEnergyStatus(prosumer2.address, 10);

        await expect(contract.connect(prosumer1).buyEnergyFrom(prosumer2.address, 7))
            .to.be.revertedWith("The buyer cannot request more energy than they currently need.");
    });

    it("Should not allow sellers to sell more than they have surplus", async function () {
        await contract.connect(prosumer1).registerProsumer();
        await contract.connect(prosumer2).registerProsumer();
        await contract.connect(recorder).updateEnergyStatus(prosumer1.address, -10);
        await contract.connect(recorder).updateEnergyStatus(prosumer2.address, 5);

        await expect(contract.connect(prosumer2).sellEnergyTo(prosumer1.address, 7))
            .to.be.revertedWith("The seller must have the same or more energy than they are selling.");
    });

    it("Should correctly coordinate trading and emit event", async function () {
        await contract.connect(prosumer1).registerProsumer();
        await contract.connect(prosumer2).registerProsumer();
        
        // Setup: P1 needs 5, P2 has 5. P1 needs balance to pay.
        await contract.connect(prosumer1).deposit({ value: ethers.parseEther("10") });
        await contract.connect(recorder).updateEnergyStatus(prosumer1.address, -5);
        await contract.connect(recorder).updateEnergyStatus(prosumer2.address, 5);
        
        // Execute coordination
        await expect(contract.coordinateTrading())
            .to.emit(contract, "CoordinationComplete")
            .withArgs(5);
        
        const p1Data = await contract.prosumers(prosumer1.address);
        const p2Data = await contract.prosumers(prosumer2.address);
        expect(p1Data.prosumerEnergyStat).to.equal(0);
        expect(p2Data.prosumerEnergyStat).to.equal(0);
    });

    it("Should adjust price based on community status", async function () {
        await contract.connect(prosumer1).registerProsumer();
        // Set a massive deficit
        await contract.connect(recorder).updateEnergyStatus(prosumer1.address, -5000); 
        await contract.updateEnergyPrice();
        
        const price = await contract.getEnergyPrice();
        // Price should be capped at 5 Ether
        expect(price).to.equal(ethers.parseEther("5"));
    });
});