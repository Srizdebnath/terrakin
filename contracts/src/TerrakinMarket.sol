// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title Terrakin Market
/// @notice Peer-to-peer Kin market. Listings are escrow-free: the seller
/// keeps the Kin (it can still defend hexes) and approves this contract once;
/// a sale moves it straight from seller to buyer. A listing goes stale if the
/// Kin changes hands first, and simply can't be bought.
contract TerrakinMarket {
    struct Listing {
        address seller;
        uint128 price;
        uint40 listedAt;
    }

    IERC721 public immutable kin; // the game contract
    uint16 public immutable feeBps; // to the reward pool

    mapping(uint256 => Listing) public listings;
    uint256[] internal _ids;
    mapping(uint256 => uint256) internal _index;
    mapping(address => uint256) public proceeds; // sale money a push couldn't deliver

    event Listed(uint256 indexed kinId, address indexed seller, uint256 price);
    event Delisted(uint256 indexed kinId);
    event Sold(uint256 indexed kinId, address indexed seller, address indexed buyer, uint256 price);

    error NotYours();
    error NotApproved();
    error NoListing();
    error Stale();
    error WrongPayment();
    error TransferFailed();

    constructor(IERC721 kin_, uint16 feeBps_) {
        kin = kin_;
        feeBps = feeBps_;
    }

    function list(uint256 kinId, uint128 price) external {
        if (kin.ownerOf(kinId) != msg.sender) revert NotYours();
        if (price == 0) revert WrongPayment();
        if (!kin.isApprovedForAll(msg.sender, address(this)) && kin.getApproved(kinId) != address(this)) {
            revert NotApproved();
        }
        if (listings[kinId].seller == address(0)) {
            _index[kinId] = _ids.length;
            _ids.push(kinId);
        }
        listings[kinId] = Listing(msg.sender, price, uint40(block.timestamp));
        emit Listed(kinId, msg.sender, price);
    }

    function delist(uint256 kinId) external {
        Listing memory l = listings[kinId];
        // The seller, or anyone once the listing is stale.
        if (l.seller == address(0)) revert NoListing();
        if (l.seller != msg.sender && _ownerOrZero(kinId) == l.seller) revert NotYours();
        _remove(kinId);
        emit Delisted(kinId);
    }

    function buy(uint256 kinId) external payable {
        Listing memory l = listings[kinId];
        if (l.seller == address(0)) revert NoListing();
        if (msg.value != l.price) revert WrongPayment();
        if (_ownerOrZero(kinId) != l.seller) revert Stale();
        if (l.seller == msg.sender) revert NotYours();
        _remove(kinId);
        kin.transferFrom(l.seller, msg.sender, kinId);
        uint256 fee = uint256(l.price) * feeBps / 10000;
        (bool ok,) = address(kin).call{value: fee}("");
        if (!ok) revert TransferFailed();
        (ok,) = l.seller.call{value: l.price - fee, gas: 30000}("");
        if (!ok) proceeds[l.seller] += l.price - fee;
        emit Sold(kinId, l.seller, msg.sender, l.price);
    }

    function withdrawProceeds() external {
        uint256 amount = proceeds[msg.sender];
        proceeds[msg.sender] = 0;
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    /// Every listing, stale ones flagged.
    function all()
        external
        view
        returns (uint256[] memory ids, address[] memory sellers, uint256[] memory prices, bool[] memory live)
    {
        uint256 n = _ids.length;
        ids = new uint256[](n);
        sellers = new address[](n);
        prices = new uint256[](n);
        live = new bool[](n);
        for (uint256 i; i < n; ++i) {
            uint256 id = _ids[i];
            Listing memory l = listings[id];
            ids[i] = id;
            sellers[i] = l.seller;
            prices[i] = l.price;
            live[i] = _ownerOrZero(id) == l.seller;
        }
    }

    function _ownerOrZero(uint256 id) internal view returns (address) {
        try kin.ownerOf(id) returns (address o) {
            return o;
        } catch {
            return address(0);
        }
    }

    function _remove(uint256 kinId) internal {
        uint256 idx = _index[kinId];
        uint256 last = _ids[_ids.length - 1];
        _ids[idx] = last;
        _index[last] = idx;
        _ids.pop();
        delete _index[kinId];
        delete listings[kinId];
    }
}
