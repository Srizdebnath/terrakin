// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {OwnerIndexed} from "./OwnerIndexed.sol";

/// @title Terrakin Wayfinders
/// @notice Playable characters. Only the Terrakin game contract mints them;
/// they are ordinary NFTs afterwards and can be transferred or sold.
contract TerrakinCharacters is OwnerIndexed {
    address public immutable game;

    /// tokenId => character style (0 Rio, 1 Mira, 2 Kai, 3 Juno, 4 Sol, 5 Nova)
    mapping(uint256 => uint8) public styleOf;

    error OnlyGame();

    constructor(address game_) ERC721("Terrakin Wayfinders", "WAYF") {
        game = game_;
    }

    /// @dev Ids are derived per player, so concurrent mints by different
    /// players never touch a shared counter (keeps Monad's parallel lanes free).
    function mint(address to, uint8 style, uint256 nonce) external returns (uint256 id) {
        if (msg.sender != game) revert OnlyGame();
        id = uint256(keccak256(abi.encode(to, nonce)));
        styleOf[id] = style;
        _mint(to, id);
    }

    /// One call for the app: every character a wallet holds, with its style.
    function charactersOf(address owner) external view returns (uint256[] memory ids, uint8[] memory styles) {
        uint256 n = balanceOf(owner);
        ids = new uint256[](n);
        styles = new uint8[](n);
        for (uint256 i; i < n; ++i) {
            ids[i] = tokenOfOwnerByIndex(owner, i);
            styles[i] = styleOf[ids[i]];
        }
    }
}
