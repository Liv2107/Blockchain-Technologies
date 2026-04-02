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

    // event to emit when coordination is complete
    event CoordinationComplete(uint256 totalMatchedEnergy);

    constructor(address _recorder) payable {
        recorder = _recorder; // Assign the address passed during deployment
        energyPrice = 1 ether; // Set the base price as per the brief
    }
    
    modifier _isRegistered(address _address) {
        require(prosumers[_address].isMember, "Not registered.");
        _;
    }

    modifier _isRecorder() {
        require(msg.sender == getRecorder(), "Only the recorder is valid.");
        _;
    }
    
    address[] public prosumerAddresses; 

    function registerProsumer() external {
        require(!prosumers[msg.sender].isMember, "Already registered.");

        prosumers[msg.sender] = Prosumer({
            prosumerAddress: msg.sender, 
            prosumerEnergyStat: 0, 
            prosumerBalance: 0, 
            isMember: true
        });
        
        prosumerAddresses.push(msg.sender); // req for coordination
    }
    function deposit() external payable {
        require(prosumers[msg.sender].isMember, "Not registered.");
        // deposit the balance with the ether sent (msg.value)
        prosumers[msg.sender].prosumerBalance += msg.value;
    }

    function withdraw(uint256 _value) external {
        // check if registration
        require(prosumers[msg.sender].isMember, "Not registered.");
        
        // check since "can only withdraw if they have no energy deficit")
        require(prosumers[msg.sender].prosumerEnergyStat >= 0, "Cannot withdraw while in energy deficit.");
        
        // check if they actually have enough balance
        require(prosumers[msg.sender].prosumerBalance >= _value, "Insufficient balance.");

        // update balance beofre the transfer
        prosumers[msg.sender].prosumerBalance -= _value;

        // send the Ether back to the prosumer
        //using transfer since it will revert back if there is an error
        payable(msg.sender).transfer(_value);
    }

    int256 public totalCommunityStatus; // Global tracker

    function updateEnergyStatus(address _prosumer, int256 deltaEnergy) external {
        require(msg.sender == getRecorder(), "Only the recorder is valid.");
        require(prosumers[_prosumer].isMember, "Target prosumer not registered.");

        // update global status: Subtract old value, add new value
        totalCommunityStatus = totalCommunityStatus - prosumers[_prosumer].prosumerEnergyStat + deltaEnergy;
        
        // update individual status
        prosumers[_prosumer].prosumerEnergyStat = deltaEnergy;
    }

    function updateEnergyPrice() public {
        // Base: 1e18 (1 Ether), Step: 1e15 (0.001 Ether)
        int256 calculatedPrice = 1e18 - (totalCommunityStatus * 1e15);

        // Apply the 0.1 Ether min and 5 Ether max caps
        if (calculatedPrice < 1e17) {
            energyPrice = 1e17;
        } else if (calculatedPrice > 5e18) {
            energyPrice = 5e18;
        } else {
            energyPrice = uint256(calculatedPrice);
        }
    }

    function buyEnergyFrom(address _seller, uint _requestedEnergy) external {
        // template-safe registration checks
        require(prosumers[msg.sender].isMember, "Buyer not registered.");
        require(prosumers[_seller].isMember, "Seller not registered.");
        require(_requestedEnergy > 0, "Requested energy must be positive.");
        
        // energy Status Logic
        // buyer must be in deficit (negative)
        require(prosumers[msg.sender].prosumerEnergyStat < 0, "The buyer must have an energy deficit.");
        // buyer cannot buy more than their absolute deficit
        require(-prosumers[msg.sender].prosumerEnergyStat >= int256(_requestedEnergy), "The buyer cannot request more energy than they currently need.");
        
        // seller must be in surplus
        require(prosumers[_seller].prosumerEnergyStat > 0, "The seller must have a surplus.");
        // seller cannot sell more than they actually have
        require(prosumers[_seller].prosumerEnergyStat >= int256(_requestedEnergy), "The seller must have the same or more energy than they are selling.");

        // financial Logic
        uint256 cost = _requestedEnergy * getEnergyPrice();
        require(prosumers[msg.sender].prosumerBalance >= cost, "The buyer must have enough balance to pay for the energy.");

        // update State
        // Energy
        prosumers[msg.sender].prosumerEnergyStat += int256(_requestedEnergy);
        prosumers[_seller].prosumerEnergyStat -= int256(_requestedEnergy);
        
        // Balance
        prosumers[msg.sender].prosumerBalance -= cost;
        prosumers[_seller].prosumerBalance += cost;
    }

    function sellEnergyTo(address _buyer, uint _offeredEnergy) external {
        require(prosumers[msg.sender].isMember, "Seller not registered.");
        require(prosumers[_buyer].isMember, "Buyer not registered.");
        require(_offeredEnergy > 0, "Offered energy must be positive.");

        // logic Checks
        require(prosumers[msg.sender].prosumerEnergyStat > 0, "The seller must have a surplus of energy.");
        require(prosumers[msg.sender].prosumerEnergyStat >= int256(_offeredEnergy), "The seller must have the same or more energy than they are selling.");

        
        require(prosumers[_buyer].prosumerEnergyStat < 0, "The buyer must have an energy deficit.");
        require(-prosumers[_buyer].prosumerEnergyStat >= int256(_offeredEnergy), "The buyer cannot request more energy than they currently need.");

        uint256 cost = _offeredEnergy * getEnergyPrice();
        require(prosumers[_buyer].prosumerBalance >= cost, "The buyer must have enough balance to pay for the energy.");

        // Energy
        prosumers[msg.sender].prosumerEnergyStat -= int256(_offeredEnergy);
        prosumers[_buyer].prosumerEnergyStat += int256(_offeredEnergy);
        
        // Balance
        prosumers[_buyer].prosumerBalance -= cost;
        prosumers[msg.sender].prosumerBalance += cost;
    }

    //few added dfunction for 8th point
    function isSeller(address _prosumer) internal view returns (bool) {
        return prosumers[_prosumer].prosumerEnergyStat > 0;
    }

    function isBuyer(address _prosumer) internal view returns (bool) {
        return prosumers[_prosumer].prosumerEnergyStat < 0;
    }
 
    function getAbsStatus(int256 _val) internal pure returns (uint256) {
        return uint256(_val < 0 ? -_val : _val);
    }

    function coordinateTrading() public {
        uint256 totalMatched = 0;
        uint256 currentPrice = getEnergyPrice();

        // loop through all prosumers to find buyers (those in deficit)
        for (uint256 i = 0; i < prosumerAddresses.length; i++) {
            address buyer = prosumerAddresses[i];
            
            if (isBuyer(buyer)) {
                // for every buyer, look for sellers (those in surplus)
                for (uint256 j = 0; j < prosumerAddresses.length; j++) {
                    address seller = prosumerAddresses[j];
                    
                    if (isSeller(seller)) {
                        // determine how much can be traded
                        uint256 buyerNeeds = getAbsStatus(prosumers[buyer].prosumerEnergyStat);
                        uint256 sellerHas = uint256(prosumers[seller].prosumerEnergyStat);
                        
                        uint256 amountToTrade = buyerNeeds < sellerHas ? buyerNeeds : sellerHas;

                        if (amountToTrade > 0) {
                            uint256 cost = amountToTrade * currentPrice;

                            // Update Energy Statuses
                            prosumers[buyer].prosumerEnergyStat += int256(amountToTrade);
                            prosumers[seller].prosumerEnergyStat -= int256(amountToTrade);

                            // Update Balances
                            prosumers[buyer].prosumerBalance -= cost;
                            prosumers[seller].prosumerBalance += cost;

                            totalMatched += amountToTrade;
                        }
                    }
                    // If this buyer is fully satisfied (status is 0), move to the next buyer
                    if (prosumers[buyer].prosumerEnergyStat == 0) {
                        break;
                    }
                }
            }
        }

        // 4. Emit the event as required by the brief
        emit CoordinationComplete(totalMatched);
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
