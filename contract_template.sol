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
        // Your implementation here
    }

    function registerProsumer() external {
        // Your implementation here
    }

    function deposit() external payable {
        // Your implementation here
    }

    function withdraw(uint256 _value) external {
        // Your implementation here
    }

    function updateEnergyStatus(address _prosumer, int256 deltaEnergy) external {
        // Your implementation here
    }

    function updateEnergyPrice() public {
        // Your implementation here
    }

    function buyEnergyFrom(address _seller, uint _requestedEnergy) external {
        // Your implementation here
    }

    function sellEnergyTo(address _buyer, uint _offeredEnergy) external {
        // Your implementation here
    }


    function coordinateTrading() public {
        // Your implementation here
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
