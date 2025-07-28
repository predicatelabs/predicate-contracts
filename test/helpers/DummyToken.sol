// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DummyToken is ERC20 {
    constructor(
        uint256 initialSupply
    ) ERC20("MyToken", "MTK") {
        _mint(msg.sender, initialSupply);
    }
}
