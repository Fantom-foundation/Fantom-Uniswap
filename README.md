# Fantom Uniswap Deployment

Uniswap is an *automated liquidity protocol* powered by a constant product formula and implemented in a system of non-upgradeable smart contracts on a block chain. It obviates the need for trusted intermediaries, prioritizing decentralization, censorship resistance, and security. Uniswap is open-source software licensed under the GPL.

We've deployed the Uniswap protocol, originally developed on the Ethereum network, on our unique Fantom Opera block chain technology. This brings the benefits of having decentralized and secure environment for liquidity pool based trading into the Fantom ecosystem and its growing user base.

## Modules and Tools Deployed

Here is the list of references to Uniswap ecosystem projects we utilize to get the protocol live on Fantom Opera block chain network. We would like to express our appreciation to the great work these projects did to create such an excellent set of secure trading tools.

- [Uniswap V2 Core](https://github.com/Uniswap/uniswap-v2-core)
- [Uniswap V2 Periphery](https://github.com/Uniswap/uniswap-v2-periphery/tree/master/contracts)
- [MakerDao Multicall Aggregator](https://github.com/makerdao/multicall)
- [Uniswap Web Interface](https://github.com/Uniswap/uniswap-interface)

We deployed following contracts from the Uniswap protocol ecosystem:

- Uniswap Core V2 contract
- Uniswap V2 Pair
- Uniswap Periphery updated to use WFTM tokens instead of original WETH.

We also use our own implementations of following modules:

- Wrapped Fantom native tokens to ERC20
