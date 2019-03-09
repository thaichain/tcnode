// Copyright 2018 Parity Technologies Ltd.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// A validator set contract that relays calls to a relayed validator set
// contract, which allows upgrading the relayed validator set contract. It
// provides an `initiateChange` function that allows the relayed contract to
// trigger a change, since the engine will be listening for events emitted by
// the outer relay contract.

pragma solidity ^0.4.22;

contract Owned {
    event NewOwner(address indexed old, address indexed current);

    address public owner = msg.sender;

    modifier onlyOwner {
	require(msg.sender == owner);
	_;
    }

    function setOwner(address _new)
	external
	onlyOwner
    {
	emit NewOwner(owner, _new);
	owner = _new;
    }
}

interface ValidatorSet {
    event InitiateChange(bytes32 indexed _parentHash, address[] _newSet);

    function finalizeChange()
	external;

    function reportBenign(address validator, uint256 blockNumber)
	external;

    function reportMalicious(address validator, uint256 blockNumber, bytes proof)
	external;

    function getValidators()
	external
	view
	returns (address[]);
}

contract BaseOwnedSet is Owned {
    // EVENTS
    event ChangeFinalized(address[] currentSet);

    // STATE

    // Was the last validator change finalized. Implies validators == pending
    bool public finalized;

    // TYPES
    struct AddressStatus {
	bool isIn;
	uint index;
    }

    // EVENTS
    event Report(address indexed reporter, address indexed reported, bool indexed malicious);

    // STATE
    uint public recentBlocks = 20;

    // Current list of addresses entitled to participate in the consensus.
    address[] validators;
    address[] pending;
    mapping(address => AddressStatus) status;

    // MODIFIERS

    /// Asserts whether a given address is currently a validator. A validator
    /// that is pending to be added is not considered a validator, only when
    /// that change is finalized will this method return true. A validator that
    /// is pending to be removed is immediately not considered a validator
    /// (before the change is finalized).
    ///
    /// For the purposes of this contract one of the consequences is that you
    /// can't report on a validator that is currently active but pending to be
    /// removed. This is a compromise for simplicity since the reporting
    /// functions only emit events which can be tracked off-chain.
    modifier isValidator(address _someone) {
	bool isIn = status[_someone].isIn;
	uint index = status[_someone].index;

	require(isIn && index < validators.length && validators[index] == _someone);
	_;
    }

    modifier isNotValidator(address _someone) {
	require(!status[_someone].isIn);
	_;
    }

    modifier isRecent(uint _blockNumber) {
	require(block.number <= _blockNumber + recentBlocks && _blockNumber < block.number);
	_;
    }

    modifier whenFinalized() {
	require(finalized);
	_;
    }

    modifier whenNotFinalized() {
	require(!finalized);
	_;
    }

    constructor(address[] _initial)
	public
    {
	pending = _initial;
	for (uint i = 0; i < _initial.length; i++) {
	    status[_initial[i]].isIn = true;
	    status[_initial[i]].index = i;
	}
	validators = pending;
    }

    // OWNER FUNCTIONS

    // Add a validator.
    function addValidator(address _validator)
	external
	onlyOwner
	isNotValidator(_validator)
    {
	status[_validator].isIn = true;
	status[_validator].index = pending.length;
	pending.push(_validator);
	triggerChange();
    }

    // Remove a validator.
    function removeValidator(address _validator)
	external
	onlyOwner
	isValidator(_validator)
    {
	// Remove validator from pending by moving the
	// last element to its slot
	uint index = status[_validator].index;
	pending[index] = pending[pending.length - 1];
	status[pending[index]].index = index;
	delete pending[pending.length - 1];
	pending.length--;

	// Reset address status
	delete status[_validator];

	triggerChange();
    }

    function setRecentBlocks(uint _recentBlocks)
	external
	onlyOwner
    {
	recentBlocks = _recentBlocks;
    }

    // GETTERS

    // Called to determine the current set of validators.
    function getValidators()
	external
	view
	returns (address[])
    {
	return validators;
    }

    // Called to determine the pending set of validators.
    function getPending()
	external
	view
	returns (address[])
    {
	return pending;
    }

    // INTERNAL

    // Report that a validator has misbehaved in a benign way.
    function baseReportBenign(address _reporter, address _validator, uint _blockNumber)
	internal
	isValidator(_reporter)
	isValidator(_validator)
	isRecent(_blockNumber)
    {
	emit Report(_reporter, _validator, false);
    }

    // Report that a validator has misbehaved maliciously.
    function baseReportMalicious(
	address _reporter,
	address _validator,
	uint _blockNumber,
	bytes _proof
    )
	internal
	isValidator(_reporter)
	isValidator(_validator)
	isRecent(_blockNumber)
    {
	emit Report(_reporter, _validator, true);
    }

    // Called when an initiated change reaches finality and is activated.
    function baseFinalizeChange()
	internal
	whenNotFinalized
    {
	validators = pending;
	finalized = true;
	emit ChangeFinalized(validators);
    }

    // PRIVATE

    function triggerChange()
	private
	whenFinalized
    {
	finalized = false;
	initiateChange();
    }

    function initiateChange()
	private;
}


contract RelayedOwnedSet is BaseOwnedSet {
    RelaySet public relaySet;

    modifier onlyRelay() {
	require(msg.sender == address(relaySet));
	_;
    }

    constructor(address _relaySet, address[] _initial) BaseOwnedSet(_initial)
	public
    {
	relaySet = RelaySet(_relaySet);
    }

    function relayReportBenign(address _reporter, address _validator, uint _blockNumber)
	external
	onlyRelay
    {
	baseReportBenign(_reporter, _validator, _blockNumber);
    }

    function relayReportMalicious(
	address _reporter,
	address _validator,
	uint _blockNumber,
	bytes _proof
    )
	external
	onlyRelay
    {
	baseReportMalicious(
	    _reporter,
	    _validator,
	    _blockNumber,
	    _proof
	);
    }

    function setRelay(address _relaySet)
	external
	onlyOwner
    {
	relaySet = RelaySet(_relaySet);
    }

    function finalizeChange()
	external
	onlyRelay
    {
	baseFinalizeChange();
    }

    function initiateChange()
	private
    {
	relaySet.initiateChange(blockhash(block.number - 1), pending);
    }
}


contract RelaySet is Owned, ValidatorSet {
    // EVENTS
    event NewRelayed(address indexed old, address indexed current);

    // STATE

    // System address, used by the block sealer.
    address public systemAddress;
    // Address of the inner validator set contract
    RelayedOwnedSet public relayedSet;

    // MODIFIERS
    modifier onlySystem() {
	require(msg.sender == systemAddress);
	_;
    }

    modifier onlyRelayed() {
	require(msg.sender == address(relayedSet));
	_;
    }

    constructor()
	public
    {
	systemAddress = 0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE;
    }

    // For innerSet
    function initiateChange(bytes32 _parentHash, address[] _newSet)
	external
	onlyRelayed
    {
	emit InitiateChange(_parentHash, _newSet);
    }

    // For sealer
    function finalizeChange()
	external
	onlySystem
    {
	relayedSet.finalizeChange();
    }

    function reportBenign(address _validator, uint256 _blockNumber)
	external
    {
	relayedSet.relayReportBenign(msg.sender, _validator, _blockNumber);
    }

    function reportMalicious(address _validator, uint256 _blockNumber, bytes _proof)
	external
    {
	relayedSet.relayReportMalicious(
	    msg.sender,
	    _validator,
	    _blockNumber,
	    _proof
	);
    }

    function setRelayed(address _relayedSet)
	external
	onlyOwner
    {
	emit NewRelayed(relayedSet, _relayedSet);
	relayedSet = RelayedOwnedSet(_relayedSet);
    }

    function getValidators()
	external
	view
	returns (address[])
    {
	return relayedSet.getValidators();
    }
}

