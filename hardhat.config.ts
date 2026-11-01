import "@nomicfoundation/hardhat-foundry";

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.28",
  paths: {
    sources: "./src/",
    cache: "./cache_hardhat",
  }
};
