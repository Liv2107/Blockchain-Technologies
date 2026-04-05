## Energy Trading Smart Contract

### Overview

This project demonstrates a basic Hardhat use case. It comes with a sample contract, a test for that contract, and a Hardhat Ignition module that deploys that contract.

Each prosumer can:
- Register
- Deposit and withdraw Ether
- Buy or sell energy
- Automated energy coordination

The system also includes a **recorder role**, responsible for updating the energy status of each prosumer.

### Data Structures

#### Prosumer Struct

Prosumer:
- `address prosumerAddress` - address
- `int256 prosumerEnergyStat` - energy surplus (+) or deficit (-)
- `uint256 prosumerBalance` - Ether balance in the contract
- `bool isMember` - registration status

A mapping is used to associate addresses with their corresponding prosumer data.

### Core Functions

#### Registration
- Users must register before interacting with the system, preventing duplicate registrations.

#### Deposit & Withdraw
- Registered users can deposit Ether into the contract.
- Withdrawals are only allowed when the prosumer has no energy deficit.

#### Energy Status Updates
- Only the recorder can update a prosumer's energy status.
- Positive values indicate surplus, negative values indicate deficit.

#### Pricing

Energy price is updated based on total community energy:
- Base price: **1 Ether**
- Increases by **0.001 Ether per unit deficit**
- Decreases by **0.001 Ether per unit surplus**
- Price bounds: **0.1 - 5 Ether**

### Trading Mechanisms

#### Direct Trading

Two functions enable peer-to-peer trading:
- `buyEnergyFrom()` - for prosumers with deficit.
- `sellEnergyTo()` - for prosumers with surplus.

Constraints:
- Buyers cannot buy more than their deficit.
- Sellers cannot sell more than their surplus.

### Coordination Mechanism

The `coordinateTrading()` function automatically matches buyers and sellers within the system.

1. Iterate through all registered prosumers.
2. Identify:
   - Sellers (positive energy)
   - Buyers (negative energy)
3. Match trades by transferring energy from sellers to buyers.
4. Continue until:
   - All possible energy is matched, or no valid trades remain.

### Testing
The contract's reliability was verified through 11 Hardhat/Chai test cases. My testing strategy focused on three main areas:

#### Functional Tests
- Registration and duplicate prevention.
- Deposits and balance updates.
- Recorder-only access control.

#### Security Tests
- Preventing invalid trades (over-buying / over-selling).
- Restricting unregistered users.

#### Integration Tests
- End-to-end trading scenarios.
- Coordination mechanism tests.

#### Try running some of the following tasks:

```shell
npx hardhat help
npx hardhat test
npx hardhat size-contracts
REPORT_GAS=true npx hardhat test
npx hardhat node
npx hardhat ignition deploy ./ignition/modules/Lock.js
```