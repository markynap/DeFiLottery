// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

contract RNG {
    uint256 private _salt = 1;
    uint256 private _saltModulo = 177;
    
    function salt(uint256 diff) public returns (uint256) {
        _salt += ( ( uint256(uint160(address(this))) % block.timestamp ) * block.number + _salt ) % ( ( diff % 1000) + 1);
        return _salt;
    }
    
    function fetchRandom(uint256 seedOne, uint256 seedTwo) external returns (uint256) {
        uint256 rng = ( (seedOne/_saltModulo) * (seedTwo/_saltModulo) ) % ( 1 + ( block.number * ( salt(uint256(msg.sender)) % _saltModulo)));
        _saltModulo++;
        return rng;
    }

    function mixSalt(uint256 mixup) external {
        salt += ( mixup % _saltModulo );
        _saltModulo++;
    }
}