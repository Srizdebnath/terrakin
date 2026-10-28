// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @notice Per-owner token lists, so the app can read a wallet's tokens in one
/// call. Unlike ERC721Enumerable there is no global token list: that shared
/// array costs two extra fresh storage writes per mint and makes every mint
/// touch the same slot, which serialises Monad's parallel execution.
abstract contract OwnerIndexed is ERC721 {
    mapping(address => mapping(uint256 => uint256)) private _owned;
    mapping(uint256 => uint256) private _ownedIndex;

    error IndexOutOfRange();

    function tokenOfOwnerByIndex(address owner, uint256 i) public view returns (uint256) {
        if (i >= balanceOf(owner)) revert IndexOutOfRange();
        return _owned[owner][i];
    }

    function _update(address to, uint256 id, address auth) internal virtual override returns (address from) {
        from = super._update(to, id, auth);
        if (from == to) return from;
        if (from != address(0)) {
            // Balance is already decremented, so it is the last index.
            uint256 last = balanceOf(from);
            uint256 idx = _ownedIndex[id];
            if (idx != last) {
                uint256 lastId = _owned[from][last];
                _owned[from][idx] = lastId;
                _ownedIndex[lastId] = idx;
            }
            delete _owned[from][last];
        }
        if (to != address(0)) {
            uint256 n = balanceOf(to) - 1;
            _owned[to][n] = id;
            _ownedIndex[id] = n;
        }
    }
}
