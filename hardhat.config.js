// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      },
      viaIR: false
    }
  },
  networks: {
    hardhat: {
      forking: {
        url: "https://bsc-dataseed.binance.org/"
      }
    },
    bsc: {
      url: "https://bsc-dataseed.binance.org/",
      chainId: 56
    },
    bscTestnet: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545/",
      chainId: 97
    }
  }
};
