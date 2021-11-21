// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import "../../Interfaces/IVEToken.sol";
import "../../Dependencies/SafeMath.sol";
import "../../Dependencies/Ownable.sol";


contract VEToken is IVEToken, Ownable {
    
    using SafeMath for uint256;

    mapping (address => uint256) private _balances;

    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    uint8  private _decimals;


    constructor (string memory name_, string memory symbol_) public {
        _name = name_;
        _symbol = symbol_;
        _decimals = 18;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function mint(address account, uint256 amount) external override onlyOwner {
        require(account != address(0), "VEToken: mint to the zero address");
        
        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    function burn(address account, uint256 amount) external override onlyOwner {
        require(account != address(0), "VEToken: burn from the zero address");

        _balances[account] = _balances[account].sub(amount, "VEToken: burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

}
