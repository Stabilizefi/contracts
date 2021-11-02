// SPDX-License-Identifier: MIT
pragma solidity 0.6.11;


import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


interface IERC20Decimals {
    function decimals() external view returns (uint8);
}


contract StableToken is ERC20, Ownable {

    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    mapping (address => bool) public hasPermissionToWrap;
    mapping (address => bool) public hasPermissionToUnwrap;
    mapping (address => uint) public underlyingTokenReserve;
    mapping (address => uint) public underlyingTokenDecimals;

    event AddUnderlyingToken(address token);
    event SetPermissionToWrap(address token, bool enable);
    event SetPermissionToUnwrap(address token, bool enable);
    event Wrap(address tokenAddress, uint wrapAmount, uint mintAmount, address receiver);
    event Unwrap(address tokenAddress, uint unwrapAmount, uint returnAmount, address receiver);


    constructor (
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) public {}
    
    function addUnderlyingToken(address token) external onlyOwner {
        hasPermissionToWrap[token] = true;
        hasPermissionToUnwrap[token] = true;
        underlyingTokenDecimals[token] = uint256(IERC20Decimals(token).decimals());
        
        emit AddUnderlyingToken(token);
    }

    function setPermissionToWrap(address token, bool enable) external onlyOwner {
        hasPermissionToWrap[token] = enable;
        emit SetPermissionToWrap(token, enable);
    }

    function setPermissionToUnwrap(address token, bool enable) external onlyOwner {
        hasPermissionToUnwrap[token] = enable;
        emit SetPermissionToUnwrap(token, enable);
    }

    function wrap(address tokenAddress, uint wrapAmount, address receiver) external {
        
        require(hasPermissionToWrap[tokenAddress], "it`s not allowed to wrap");
        require(wrapAmount > 0, "need non-zero amount");
        require(receiver != address(0), "need non-zero address");
        
        IERC20 token = IERC20(tokenAddress);
        
        token.safeTransferFrom(msg.sender, address(this), wrapAmount);
        underlyingTokenReserve[tokenAddress] = underlyingTokenReserve[tokenAddress].add(wrapAmount);

        uint256 mintAmount = wrapAmount.mul(uint256(10) ** decimals()).div(uint256(10) ** underlyingTokenDecimals[tokenAddress]);
        _mint(receiver, mintAmount);

        emit Wrap(tokenAddress, wrapAmount, mintAmount, receiver);
    }

    function unwrap(address tokenAddress, uint unwrapAmount, address receiver) external {
        require(hasPermissionToUnwrap[tokenAddress], "it`s not allowed to unwrap");
        require(unwrapAmount > 0, "need non-zero amount");
        require(receiver != address(0), "need non-zero address");
                
        uint returnAmount = unwrapAmount.mul(uint256(10) ** underlyingTokenDecimals[tokenAddress]).div(uint256(10) ** decimals());
        require(underlyingTokenReserve[tokenAddress] >= returnAmount, "Insufficient reserve token");

        _burn(msg.sender, unwrapAmount);
        IERC20(tokenAddress).safeTransfer(receiver, returnAmount);

        underlyingTokenReserve[tokenAddress] = underlyingTokenReserve[tokenAddress].sub(returnAmount);

        emit Unwrap(tokenAddress, unwrapAmount, returnAmount, receiver);
    }

}