// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

contract EnergyTrading {

    // Define the ProsumerData struct
    struct Prosumer {
        // ID (address) of the prosumer
        address prosumerAddress;
        // positive value means energy to sell, negative value means energy to buy
        int256 prosumerEnergyStat;
        // Store the deposited ethers, we don't expect negative
        uint256 prosumerBalance;
        // true if prosumer has been added to our system
        bool isMember;
    }

    // Hashmap to store prosumer data
    mapping (address => Prosumer) public prosumers;

    // Variable to store the latest energy price
    uint256 private energyPrice;

    // Variable to store the recorder address who can update the energy status of prosumers
    address private recorder;

    // Track all registered prosumer addresses for iteration during coordination
    address[] private prosumerAddresses;

    // event to emit when coordination is complete
    event CoordinationComplete(uint256 totalMatchedEnergy);

    constructor(address _recorder) payable {
        recorder = _recorder;
        energyPrice = 1 ether;
    }

    function registerProsumer() external {
        require(!prosumers[msg.sender].isMember, "Already registered");
        prosumers[msg.sender] = Prosumer({
            prosumerAddress: msg.sender,
            prosumerEnergyStat: 0,
            prosumerBalance: 0,
            isMember: true
        });
        prosumerAddresses.push(msg.sender);
    }

    function deposit() external payable {
        require(prosumers[msg.sender].isMember, "Not registered");
        prosumers[msg.sender].prosumerBalance += msg.value;
    }

    function withdraw(uint256 _value) external {
        Prosumer storage p = prosumers[msg.sender];
        require(p.isMember, "Not registered");
        require(p.prosumerEnergyStat >= 0, "Has energy deficit");
        require(p.prosumerBalance >= _value, "Insufficient balance");
        p.prosumerBalance -= _value;
        payable(msg.sender).transfer(_value);
    }

    function updateEnergyStatus(address _prosumer, int256 deltaEnergy) external {
        require(msg.sender == recorder, "Only recorder");
        require(prosumers[_prosumer].isMember, "Not registered");
        prosumers[_prosumer].prosumerEnergyStat = deltaEnergy;
    }

    function updateEnergyPrice() public {
        int256 totalNet = 0;
        for (uint256 i = 0; i < prosumerAddresses.length; i++) {
            totalNet += prosumers[prosumerAddresses[i]].prosumerEnergyStat;
        }
        // price = basePrice - netSurplus * 0.001 ether
        // Surplus lowers price, deficit raises price
        int256 newPrice = 1e18 - totalNet * 1e15;
        if (newPrice < 1e17) {
            newPrice = 1e17;
        }
        if (newPrice > 5e18) {
            newPrice = 5e18;
        }
        energyPrice = uint256(newPrice);
    }

    function buyEnergyFrom(address _seller, uint _requestedEnergy) external {
        Prosumer storage buyer = prosumers[msg.sender];
        Prosumer storage seller = prosumers[_seller];

        require(buyer.isMember, "Buyer not registered");
        require(seller.isMember, "Seller not registered");
        require(_requestedEnergy > 0, "Must request positive energy");
        require(buyer.prosumerEnergyStat < 0, "Buyer has no deficit");
        require(seller.prosumerEnergyStat > 0, "Seller has no surplus");
        require(int256(_requestedEnergy) <= -buyer.prosumerEnergyStat, "Exceeds buyer deficit");
        require(int256(_requestedEnergy) <= seller.prosumerEnergyStat, "Exceeds seller surplus");

        uint256 cost = _requestedEnergy * energyPrice;
        require(buyer.prosumerBalance >= cost, "Insufficient buyer balance");

        buyer.prosumerBalance -= cost;
        seller.prosumerBalance += cost;
        buyer.prosumerEnergyStat += int256(_requestedEnergy);
        seller.prosumerEnergyStat -= int256(_requestedEnergy);
    }

    function sellEnergyTo(address _buyer, uint _offeredEnergy) external {
        Prosumer storage seller = prosumers[msg.sender];
        Prosumer storage buyer = prosumers[_buyer];

        require(seller.isMember, "Seller not registered");
        require(buyer.isMember, "Buyer not registered");
        require(_offeredEnergy > 0, "Must offer positive energy");
        require(seller.prosumerEnergyStat > 0, "Seller has no surplus");
        require(buyer.prosumerEnergyStat < 0, "Buyer has no deficit");
        require(int256(_offeredEnergy) <= seller.prosumerEnergyStat, "Exceeds seller surplus");
        require(int256(_offeredEnergy) <= -buyer.prosumerEnergyStat, "Exceeds buyer deficit");

        uint256 cost = _offeredEnergy * energyPrice;
        require(buyer.prosumerBalance >= cost, "Insufficient buyer balance");

        buyer.prosumerBalance -= cost;
        seller.prosumerBalance += cost;
        seller.prosumerEnergyStat -= int256(_offeredEnergy);
        buyer.prosumerEnergyStat += int256(_offeredEnergy);
    }


    function coordinateTrading() public {
        uint256 n = prosumerAddresses.length;
        if (n == 0) {
            emit CoordinationComplete(0);
            return;
        }

        uint256 sellerCount = 0;
        uint256 buyerCount = 0;
        uint256 totalSurplus = 0;
        uint256 totalDeficit = 0;

        for (uint256 i = 0; i < n; i++) {
            int256 stat = prosumers[prosumerAddresses[i]].prosumerEnergyStat;
            if (stat > 0) {
                sellerCount++;
                totalSurplus += uint256(stat);
            } else if (stat < 0) {
                buyerCount++;
                totalDeficit += uint256(-stat);
            }
        }

        uint256 totalTradable = totalSurplus < totalDeficit ? totalSurplus : totalDeficit;
        if (totalTradable == 0) {
            emit CoordinationComplete(0);
            return;
        }

        // Build seller and buyer arrays in memory
        address[] memory sAddr = new address[](sellerCount);
        uint256[] memory sSurplus = new uint256[](sellerCount);
        address[] memory bAddr = new address[](buyerCount);
        uint256[] memory bDeficit = new uint256[](buyerCount);

        {
            uint256 si = 0;
            uint256 bi = 0;
            for (uint256 i = 0; i < n; i++) {
                int256 stat = prosumers[prosumerAddresses[i]].prosumerEnergyStat;
                if (stat > 0) {
                    sAddr[si] = prosumerAddresses[i];
                    sSurplus[si] = uint256(stat);
                    si++;
                } else if (stat < 0) {
                    bAddr[bi] = prosumerAddresses[i];
                    bDeficit[bi] = uint256(-stat);
                    bi++;
                }
            }
        }

        // Water-fill to determine how much each participant trades,
        // minimising remaining variance across all prosumers.
        uint256[] memory sellAmt = new uint256[](sellerCount);
        uint256[] memory buyAmt = new uint256[](buyerCount);

        if (totalSurplus >= totalDeficit) {
            // All buyers fully satisfied; distribute selling via water-fill
            for (uint256 i = 0; i < buyerCount; i++) {
                buyAmt[i] = bDeficit[i];
            }
            _waterFill(sSurplus, sellAmt, sellerCount, totalTradable);
        } else {
            // All sellers fully sell; distribute buying via water-fill
            for (uint256 i = 0; i < sellerCount; i++) {
                sellAmt[i] = sSurplus[i];
            }
            _waterFill(bDeficit, buyAmt, buyerCount, totalTradable);
        }

        // Apply trades: update energy status and balance for every participant
        uint256 price = energyPrice;
        for (uint256 i = 0; i < sellerCount; i++) {
            if (sellAmt[i] > 0) {
                prosumers[sAddr[i]].prosumerEnergyStat -= int256(sellAmt[i]);
                prosumers[sAddr[i]].prosumerBalance += sellAmt[i] * price;
            }
        }
        for (uint256 i = 0; i < buyerCount; i++) {
            if (buyAmt[i] > 0) {
                prosumers[bAddr[i]].prosumerEnergyStat += int256(buyAmt[i]);
                prosumers[bAddr[i]].prosumerBalance -= buyAmt[i] * price;
            }
        }

        emit CoordinationComplete(totalTradable);
    }

    /**
     * Water-fill allocation: given an array of capacities (surplus or deficit),
     * distribute totalToAllocate units so that the remaining values after
     * allocation have minimum variance.
     *
     * The algorithm finds a "water level" L such that each element gives
     * max(0, amount_i - L) and the total equals totalToAllocate. Integer
     * remainders are spread one-per-element starting from the largest entries.
     */
    function _waterFill(
        uint256[] memory amounts,
        uint256[] memory allocated,
        uint256 count,
        uint256 totalToAllocate
    ) internal pure {
        if (count == 0 || totalToAllocate == 0) return;

        // Build index array and sort descending by amount (selection sort)
        uint256[] memory idx = new uint256[](count);
        for (uint256 i = 0; i < count; i++) idx[i] = i;
        for (uint256 i = 0; i < count - 1; i++) {
            uint256 maxI = i;
            for (uint256 j = i + 1; j < count; j++) {
                if (amounts[idx[j]] > amounts[idx[maxI]]) maxI = j;
            }
            if (maxI != i) {
                (idx[i], idx[maxI]) = (idx[maxI], idx[i]);
            }
        }

        // Walk down sorted levels to find the correct water level
        uint256 cumSum = 0;
        for (uint256 k = 0; k < count; k++) {
            cumSum += amounts[idx[k]];
            uint256 groupSize = k + 1;
            uint256 minLevel = (k < count - 1) ? amounts[idx[k + 1]] : 0;

            if (cumSum >= totalToAllocate + minLevel * groupSize) {
                uint256 targetLevel = (cumSum - totalToAllocate) / groupSize;
                uint256 extra = (cumSum - totalToAllocate) % groupSize;

                for (uint256 j = 0; j < groupSize; j++) {
                    uint256 oi = idx[j];
                    if (j < extra) {
                        allocated[oi] = amounts[oi] - targetLevel - 1;
                    } else {
                        allocated[oi] = amounts[oi] - targetLevel;
                    }
                }
                return;
            }
        }

        // Fallback: allocate everything (totalToAllocate == sum of amounts)
        for (uint256 i = 0; i < count; i++) {
            allocated[i] = amounts[i];
        }
    }

    // -------------------------------------
    // Public view functions, do not modify
    // -------------------------------------

    function getRecorder() public view returns (address) {
        return recorder;
    }

    function getEnergyPrice() public view returns (uint256) {
        return energyPrice;
    }
}
