// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Terrakin Crews
/// @notice Guilds: a name, a 2-4 character tag, a captain, up to 30 members
/// and a shared MON treasury anyone in the crew can pay into. The captain
/// splits the treasury equally across members. On the map, members' hexes
/// show in their crew's colour.
contract TerrakinCrews {
    struct Crew {
        string name;
        string tag;
        address captain;
        uint128 treasury;
        uint40 founded;
    }

    uint256 public constant MAX_MEMBERS = 30;

    address payable public immutable pool; // the game contract: creation fees fund rewards
    uint256 public immutable createFee;

    Crew[] internal _crews; // crew id = index + 1
    mapping(address => uint256) public crewOf;
    mapping(uint256 => address[]) internal _members;
    mapping(address => uint256) internal _memberIndex;
    mapping(bytes32 => bool) public tagTaken;

    event CrewCreated(uint256 indexed id, address indexed captain, string name, string tag);
    event Joined(uint256 indexed id, address indexed member);
    event Left(uint256 indexed id, address indexed member);
    event CaptainChanged(uint256 indexed id, address indexed captain);
    event Deposited(uint256 indexed id, address indexed from, uint256 amount);
    event PaidOut(uint256 indexed id, uint256 each, uint256 members);

    error InCrew();
    error NoCrew();
    error Full();
    error BadName();
    error TagTaken();
    error NotCaptain();
    error WrongPayment();
    error TransferFailed();

    constructor(address payable pool_, uint256 createFee_) {
        pool = pool_;
        createFee = createFee_;
    }

    function create(string calldata name, string calldata tag) external payable returns (uint256 id) {
        if (crewOf[msg.sender] != 0) revert InCrew();
        if (msg.value != createFee) revert WrongPayment();
        uint256 nl = bytes(name).length;
        if (nl < 3 || nl > 20) revert BadName();
        string memory t = _tag(tag);
        bytes32 key = keccak256(bytes(t));
        if (tagTaken[key]) revert TagTaken();
        tagTaken[key] = true;
        _crews.push(Crew(name, t, msg.sender, 0, uint40(block.timestamp)));
        id = _crews.length;
        _add(id, msg.sender);
        (bool ok,) = pool.call{value: msg.value}("");
        if (!ok) revert TransferFailed();
        emit CrewCreated(id, msg.sender, name, t);
    }

    function join(uint256 id) external {
        if (crewOf[msg.sender] != 0) revert InCrew();
        if (id == 0 || id > _crews.length) revert NoCrew();
        if (_members[id].length >= MAX_MEMBERS) revert Full();
        _add(id, msg.sender);
    }

    /// Leaving hands the captaincy to the longest-serving member. The last
    /// member out takes whatever is left in the treasury.
    function leave() external {
        uint256 id = crewOf[msg.sender];
        if (id == 0) revert NoCrew();
        _remove(id, msg.sender);
        Crew storage c = _crews[id - 1];
        address[] storage m = _members[id];
        if (m.length == 0) {
            uint256 rest = c.treasury;
            c.treasury = 0;
            c.captain = address(0);
            _send(msg.sender, rest);
        } else if (c.captain == msg.sender) {
            c.captain = m[0];
            emit CaptainChanged(id, m[0]);
        }
    }

    function kick(address member) external {
        uint256 id = crewOf[msg.sender];
        if (id == 0 || _crews[id - 1].captain != msg.sender || member == msg.sender) revert NotCaptain();
        if (crewOf[member] != id) revert NoCrew();
        _remove(id, member);
    }

    function deposit() external payable {
        uint256 id = crewOf[msg.sender];
        if (id == 0) revert NoCrew();
        _crews[id - 1].treasury += uint128(msg.value);
        emit Deposited(id, msg.sender, msg.value);
    }

    /// Splits the whole treasury equally across current members.
    function payout() external {
        uint256 id = crewOf[msg.sender];
        if (id == 0 || _crews[id - 1].captain != msg.sender) revert NotCaptain();
        Crew storage c = _crews[id - 1];
        address[] storage m = _members[id];
        uint256 each = c.treasury / m.length;
        c.treasury -= uint128(each * m.length);
        for (uint256 i; i < m.length; ++i) {
            (bool ok,) = m[i].call{value: each, gas: 10000}("");
            if (!ok) c.treasury += uint128(each); // stays in the treasury
        }
        emit PaidOut(id, each, m.length);
    }

    // ------------------------------------------------------------------ views

    function crewCount() external view returns (uint256) {
        return _crews.length;
    }

    function crew(uint256 id) external view returns (Crew memory c, address[] memory members) {
        return (_crews[id - 1], _members[id]);
    }

    /// Crew id of each address (0 = none), for colouring the map.
    function crewsOf(address[] calldata who) external view returns (uint256[] memory ids) {
        ids = new uint256[](who.length);
        for (uint256 i; i < who.length; ++i) ids[i] = crewOf[who[i]];
    }

    /// Crews [offset, offset + limit) for the browse list.
    function crews(uint256 offset, uint256 limit)
        external
        view
        returns (string[] memory names, string[] memory tags, uint256[] memory treasuries, uint256[] memory sizes)
    {
        uint256 end = offset + limit > _crews.length ? _crews.length : offset + limit;
        uint256 n = end > offset ? end - offset : 0;
        names = new string[](n);
        tags = new string[](n);
        treasuries = new uint256[](n);
        sizes = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            Crew storage c = _crews[offset + i];
            names[i] = c.name;
            tags[i] = c.tag;
            treasuries[i] = c.treasury;
            sizes[i] = _members[offset + i + 1].length;
        }
    }

    // -------------------------------------------------------------- internals

    /// Upper-cased 2-4 character tag of A-Z / 0-9.
    function _tag(string calldata tag) internal pure returns (string memory) {
        bytes memory b = bytes(tag);
        if (b.length < 2 || b.length > 4) revert BadName();
        for (uint256 i; i < b.length; ++i) {
            bytes1 ch = b[i];
            if (ch >= "a" && ch <= "z") b[i] = bytes1(uint8(ch) - 32);
            else if (!((ch >= "A" && ch <= "Z") || (ch >= "0" && ch <= "9"))) revert BadName();
        }
        return string(b);
    }

    function _add(uint256 id, address p) internal {
        crewOf[p] = id;
        _memberIndex[p] = _members[id].length;
        _members[id].push(p);
        emit Joined(id, p);
    }

    function _remove(uint256 id, address p) internal {
        address[] storage m = _members[id];
        uint256 idx = _memberIndex[p];
        // Shift rather than swap so m[0] stays the longest-serving member.
        for (uint256 i = idx; i + 1 < m.length; ++i) {
            m[i] = m[i + 1];
            _memberIndex[m[i]] = i;
        }
        m.pop();
        delete crewOf[p];
        delete _memberIndex[p];
        emit Left(id, p);
    }

    function _send(address to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
