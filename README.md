# RevenueDistributionToken

![Foundry CI](https://github.com/maple-labs/revenue-distribution-token/actions/workflows/push-to-main.yml/badge.svg) [![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

**DISCLAIMER: This code has NOT been externally audited and is actively being developed. Please do not use in production without taking the appropriate steps to ensure maximum security.**

RevenueDistributionToken (RDT) is a token implementing the [ERC4626 Tokenized Vault standard](https://eips.ethereum.org/EIPS/eip-4626) featuring a linear revenue issuance mechanism, intended to distribute protocol revenue to staked users.

Each new revenue distribution updates the issuance rate, issuing the unvested revenue along with the new revenue over the newly specified vesting schedule. The diagram below visualizes the vesting mechanism across revenue deposits:

![RDT issuance mechanism](https://user-images.githubusercontent.com/44272939/156643098-fb7cf6e4-91c3-477f-a59c-a1a6c5cf6dc8.svg)

The first revenue deposit is performed at `t0`, scheduled to vest until `t2` (Period 1, or P1), depicted by the green arrow. On this deposit, the balance change of the contract is depicted by the purple arrow, and the issuance rate (`IR1` in the diagram) is set to `depositAmount / (t2 - t0)`.

The second revenue deposit is performed at `t1`, scheduled to vest until `t3` (Period 2, or P2), depicted by the orange arrow. On this deposit, the balance change of the contract is depicted by the purple arrow. Note that this deposit was made during P1. The projected amount that would have been vested in P1 is shown by the dotted green arrow. In order to calculate the new issuance formula, the `totalAssets` are calculated at `t1`, which function as the y-intercept of the issuance function. The issuance rate (`IR2` in the diagram) is set to `(depositAmount2 + unvestedAmount) / (t3 - t1)`.

The linear revenue issuance mechanism solves the issue of stakers entering and exiting at favorable times when large discrete revenue distributions are expected, getting an unfair portion of the revenue earned. This issuance mechanism accrues value every block, so that this exploit vector is not possible.

The ERC4626 standard helps RDT conform to a new set of tokens that are used to represent shares of an underlying asset, commonly seen in yield optimization vaults and in our case, interest/revenue bearing tokens. Implementing the standard will improve RDT's composability within DeFi and make it easier for projects and developers familiar with the standard to integrate with RDT.

RDT implements ERC2612 permit approvals for improved contract UX and gas savings.

## Testing and Development
#### Setup
```sh
git clone git@github.com:maple-labs/revenue-distribution-token.git
cd revenue-distribution-token
forge update
```
#### Running Tests
- To run all tests: `make test` (runs `./test.sh`)
- To run a specific test function: `./test.sh -t <test_name>` (e.g., `./test.sh -t test_deposit`)
- To run tests with a specified number of fuzz runs: `./test.sh -r <runs>` (e.g., `./test.sh -t test_deposit -r 10000`)

This project was built using [Foundry](https://github.com/gakonst/Foundry).

## Acknowledgements
Authors of the [EIP-4626 standard](https://eips.ethereum.org/EIPS/eip-4626), who worked towards standardizing the common tokenized vault use case in DeFi and therefore shaped the interface of the Revenue Distribution Token.

## About Maple
[Maple Finance](https://maple.finance) is a decentralized corporate credit market. Maple provides capital to institutional borrowers through globally accessible fixed-income yield opportunities.

For all technical documentation related to the currently deployed Maple protocol, please refer to the maple-core GitHub [wiki](https://github.com/maple-labs/maple-core/wiki).

---

<p align="center">
  <img src="https://user-images.githubusercontent.com/44272939/116272804-33e78d00-a74f-11eb-97ab-77b7e13dc663.png" height="100" />
</p>
