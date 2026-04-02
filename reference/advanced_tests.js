const { expect } = require("chai");
const { ethers } = require("hardhat");

const contractName = "EnergyTrading";

describe("EnergyTrading – negative-path and edge-case tests", function () {
    let contract, recorder, p1, p2, p3;

    beforeEach(async function () {
        [recorder, p1, p2, p3] = await ethers.getSigners();
        const Factory = await ethers.getContractFactory(contractName);
        contract = await Factory.deploy(recorder.address);
    });

    it("Should reject duplicate registration", async function () {
        await contract.connect(p1).registerProsumer();
        await expect(contract.connect(p1).registerProsumer()).to.be.reverted;
    });

    it("Should reject deposit from unregistered address", async function () {
        await expect(
            contract.connect(p1).deposit({ value: ethers.parseEther("1") })
        ).to.be.reverted;
    });

    it("Should allow multiple deposits and accumulate balance", async function () {
        await contract.connect(p1).registerProsumer();
        await contract.connect(p1).deposit({ value: ethers.parseEther("2") });
        await contract.connect(p1).deposit({ value: ethers.parseEther("3") });
        const data = await contract.prosumers(p1.address);
        expect(data.prosumerBalance).to.equal(ethers.parseEther("5"));
    });

    it("Should reject withdrawal from unregistered address", async function () {
        await expect(contract.connect(p1).withdraw(1)).to.be.reverted;
    });

    it("Should reject withdrawal when prosumer has energy deficit", async function () {
        await contract.connect(p1).registerProsumer();
        await contract.connect(p1).deposit({ value: ethers.parseEther("5") });
        await contract.connect(recorder).updateEnergyStatus(p1.address, -3);
        await expect(
            contract.connect(p1).withdraw(ethers.parseEther("1"))
        ).to.be.reverted;
    });

    it("Should reject withdrawal exceeding balance", async function () {
        await contract.connect(p1).registerProsumer();
        await contract.connect(p1).deposit({ value: ethers.parseEther("1") });
        await expect(
            contract.connect(p1).withdraw(ethers.parseEther("2"))
        ).to.be.reverted;
    });

    it("Should allow valid withdrawal and update balance", async function () {
        await contract.connect(p1).registerProsumer();
        await contract.connect(p1).deposit({ value: ethers.parseEther("5") });
        await contract.connect(p1).withdraw(ethers.parseEther("2"));
        const data = await contract.prosumers(p1.address);
        expect(data.prosumerBalance).to.equal(ethers.parseEther("3"));
    });

    it("Should reject energy status update from non-recorder", async function () {
        await contract.connect(p1).registerProsumer();
        await expect(
            contract.connect(p1).updateEnergyStatus(p1.address, 5)
        ).to.be.reverted;
    });

    it("Should reject energy status update for unregistered prosumer", async function () {
        await expect(
            contract.connect(recorder).updateEnergyStatus(p1.address, 5)
        ).to.be.reverted;
    });
});

describe("EnergyTrading – energy price tests", function () {
    let contract, recorder, p1, p2;

    beforeEach(async function () {
        [recorder, p1, p2] = await ethers.getSigners();
        const Factory = await ethers.getContractFactory(contractName);
        contract = await Factory.deploy(recorder.address);
        await contract.connect(p1).registerProsumer();
        await contract.connect(p2).registerProsumer();
    });

    it("Should start at base price of 1 ether", async function () {
        expect(await contract.getEnergyPrice()).to.equal(ethers.parseEther("1"));
    });

    it("Should decrease price when there is surplus", async function () {
        await contract.connect(recorder).updateEnergyStatus(p1.address, 100);
        await contract.updateEnergyPrice();
        expect(await contract.getEnergyPrice()).to.equal(ethers.parseEther("0.9"));
    });

    it("Should increase price when there is deficit", async function () {
        await contract.connect(recorder).updateEnergyStatus(p1.address, -200);
        await contract.updateEnergyPrice();
        expect(await contract.getEnergyPrice()).to.equal(ethers.parseEther("1.2"));
    });

    it("Should cap price at floor of 0.1 ether", async function () {
        await contract.connect(recorder).updateEnergyStatus(p1.address, 5000);
        await contract.updateEnergyPrice();
        expect(await contract.getEnergyPrice()).to.equal(ethers.parseEther("0.1"));
    });

    it("Should cap price at ceiling of 5 ether", async function () {
        await contract.connect(recorder).updateEnergyStatus(p1.address, -10000);
        await contract.updateEnergyPrice();
        expect(await contract.getEnergyPrice()).to.equal(ethers.parseEther("5"));
    });

    it("Should consider net of all prosumers for price", async function () {
        await contract.connect(recorder).updateEnergyStatus(p1.address, 500);
        await contract.connect(recorder).updateEnergyStatus(p2.address, -300);
        await contract.updateEnergyPrice();
        expect(await contract.getEnergyPrice()).to.equal(ethers.parseEther("0.8"));
    });
});

describe("EnergyTrading – buy and sell tests", function () {
    let contract, recorder, p1, p2;

    beforeEach(async function () {
        [recorder, p1, p2] = await ethers.getSigners();
        const Factory = await ethers.getContractFactory(contractName);
        contract = await Factory.deploy(recorder.address);
        await contract.connect(p1).registerProsumer();
        await contract.connect(p2).registerProsumer();
    });

    it("Should allow a buyer to buy energy from a seller", async function () {
        await contract.connect(recorder).updateEnergyStatus(p1.address, -5);
        await contract.connect(recorder).updateEnergyStatus(p2.address, 10);
        await contract.connect(p1).deposit({ value: ethers.parseEther("10") });

        await contract.connect(p1).buyEnergyFrom(p2.address, 3);

        const buyer = await contract.prosumers(p1.address);
        const seller = await contract.prosumers(p2.address);
        expect(buyer.prosumerEnergyStat).to.equal(-2);
        expect(seller.prosumerEnergyStat).to.equal(7);
        expect(buyer.prosumerBalance).to.equal(ethers.parseEther("7"));
        expect(seller.prosumerBalance).to.equal(ethers.parseEther("3"));
    });

    it("Should allow a seller to sell energy to a buyer", async function () {
        await contract.connect(recorder).updateEnergyStatus(p1.address, -5);
        await contract.connect(recorder).updateEnergyStatus(p2.address, 10);
        await contract.connect(p1).deposit({ value: ethers.parseEther("10") });

        await contract.connect(p2).sellEnergyTo(p1.address, 4);

        const buyer = await contract.prosumers(p1.address);
        const seller = await contract.prosumers(p2.address);
        expect(buyer.prosumerEnergyStat).to.equal(-1);
        expect(seller.prosumerEnergyStat).to.equal(6);
        expect(buyer.prosumerBalance).to.equal(ethers.parseEther("6"));
        expect(seller.prosumerBalance).to.equal(ethers.parseEther("4"));
    });

    it("Should reject buying more than buyer deficit", async function () {
        await contract.connect(recorder).updateEnergyStatus(p1.address, -2);
        await contract.connect(recorder).updateEnergyStatus(p2.address, 10);
        await contract.connect(p1).deposit({ value: ethers.parseEther("10") });
        await expect(contract.connect(p1).buyEnergyFrom(p2.address, 3)).to.be.reverted;
    });

    it("Should reject buying more than seller surplus", async function () {
        await contract.connect(recorder).updateEnergyStatus(p1.address, -10);
        await contract.connect(recorder).updateEnergyStatus(p2.address, 2);
        await contract.connect(p1).deposit({ value: ethers.parseEther("20") });
        await expect(contract.connect(p1).buyEnergyFrom(p2.address, 3)).to.be.reverted;
    });

    it("Should reject buying with insufficient balance", async function () {
        await contract.connect(recorder).updateEnergyStatus(p1.address, -5);
        await contract.connect(recorder).updateEnergyStatus(p2.address, 10);
        await expect(contract.connect(p1).buyEnergyFrom(p2.address, 3)).to.be.reverted;
    });

    it("Should reject buying when buyer has no deficit", async function () {
        await contract.connect(recorder).updateEnergyStatus(p1.address, 5);
        await contract.connect(recorder).updateEnergyStatus(p2.address, 10);
        await expect(contract.connect(p1).buyEnergyFrom(p2.address, 1)).to.be.reverted;
    });

    it("Should reject selling when seller has no surplus", async function () {
        await contract.connect(recorder).updateEnergyStatus(p1.address, -5);
        await contract.connect(recorder).updateEnergyStatus(p2.address, -3);
        await expect(contract.connect(p2).sellEnergyTo(p1.address, 1)).to.be.reverted;
    });
});

describe("EnergyTrading – coordination tests", function () {
    let contract, recorder, signers;

    beforeEach(async function () {
        signers = await ethers.getSigners();
        recorder = signers[0];
        const Factory = await ethers.getContractFactory(contractName);
        contract = await Factory.deploy(recorder.address);
    });

    async function registerAndFund(signer, deposit) {
        await contract.connect(signer).registerProsumer();
        if (deposit > 0n) {
            await contract.connect(signer).deposit({ value: deposit });
        }
    }

    it("Should handle spec example [-1, 0, 0, 1, 4] -> [0, 0, 0, 1, 3]", async function () {
        const prosumers = signers.slice(1, 6);
        const statuses = [-1, 0, 0, 1, 4];
        const bigDeposit = ethers.parseEther("100");

        for (let i = 0; i < 5; i++) {
            await registerAndFund(prosumers[i], bigDeposit);
            if (statuses[i] !== 0) {
                await contract.connect(recorder).updateEnergyStatus(prosumers[i].address, statuses[i]);
            }
        }
        await contract.updateEnergyPrice();
        await contract.coordinateTrading();

        const expected = [0, 0, 0, 1, 3];
        for (let i = 0; i < 5; i++) {
            const data = await contract.prosumers(prosumers[i].address);
            expect(data.prosumerEnergyStat).to.equal(expected[i]);
        }
    });

    it("Should emit CoordinationComplete with correct total matched energy", async function () {
        const [, a, b] = signers;
        await registerAndFund(a, ethers.parseEther("100"));
        await registerAndFund(b, ethers.parseEther("100"));
        await contract.connect(recorder).updateEnergyStatus(a.address, -3);
        await contract.connect(recorder).updateEnergyStatus(b.address, 5);

        await expect(contract.coordinateTrading())
            .to.emit(contract, "CoordinationComplete")
            .withArgs(3);
    });

    it("Should balance remaining deficits across buyers (water-fill)", async function () {
        const [, seller, buyer1, buyer2] = signers;
        await registerAndFund(seller, ethers.parseEther("100"));
        await registerAndFund(buyer1, ethers.parseEther("100"));
        await registerAndFund(buyer2, ethers.parseEther("100"));

        await contract.connect(recorder).updateEnergyStatus(seller.address, 4);
        await contract.connect(recorder).updateEnergyStatus(buyer1.address, -5);
        await contract.connect(recorder).updateEnergyStatus(buyer2.address, -3);
        await contract.updateEnergyPrice();
        await contract.coordinateTrading();

        const d1 = await contract.prosumers(buyer1.address);
        const d2 = await contract.prosumers(buyer2.address);
        expect(d1.prosumerEnergyStat).to.equal(-2);
        expect(d2.prosumerEnergyStat).to.equal(-2);
    });

    it("Should balance remaining surpluses across sellers (water-fill)", async function () {
        const [, s1, s2, buyer] = signers;
        await registerAndFund(s1, ethers.parseEther("100"));
        await registerAndFund(s2, ethers.parseEther("100"));
        await registerAndFund(buyer, ethers.parseEther("100"));

        await contract.connect(recorder).updateEnergyStatus(s1.address, 6);
        await contract.connect(recorder).updateEnergyStatus(s2.address, 4);
        await contract.connect(recorder).updateEnergyStatus(buyer.address, -8);
        await contract.updateEnergyPrice();
        await contract.coordinateTrading();

        const ds1 = await contract.prosumers(s1.address);
        const ds2 = await contract.prosumers(s2.address);
        expect(ds1.prosumerEnergyStat).to.equal(1);
        expect(ds2.prosumerEnergyStat).to.equal(1);
    });

    it("Should handle larger community with many prosumers", async function () {
        const n = 10;
        const statuses = [100, -50, 200, -80, -30, 150, -100, 60, -40, -20];
        const prosumers = signers.slice(1, n + 1);
        const bigDeposit = ethers.parseEther("1000");

        for (let i = 0; i < n; i++) {
            await registerAndFund(prosumers[i], bigDeposit);
            if (statuses[i] !== 0) {
                await contract.connect(recorder).updateEnergyStatus(prosumers[i].address, statuses[i]);
            }
        }
        await contract.updateEnergyPrice();
        await contract.coordinateTrading();

        let totalRemainingSurplus = 0n;
        let totalRemainingDeficit = 0n;
        for (let i = 0; i < n; i++) {
            const data = await contract.prosumers(prosumers[i].address);
            const stat = data.prosumerEnergyStat;
            if (stat > 0n) totalRemainingSurplus += stat;
            if (stat < 0n) totalRemainingDeficit += -stat;
        }

        expect(totalRemainingDeficit).to.equal(0n);
        expect(totalRemainingSurplus).to.equal(190n);
    });
});
