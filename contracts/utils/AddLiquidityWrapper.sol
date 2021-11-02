// SPDX-License-Identifier: MIT

pragma solidity 0.6.11;

import "../Interfaces/IUniswapV2Router.sol";

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract AddLiquidityWrapper is Ownable {
    
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    address public uniswapV2RouterAddress;

    function setSwapRouter(
        address _uniswapV2RouterAddress
    ) external onlyOwner {
        uniswapV2RouterAddress = _uniswapV2RouterAddress;
    }
    
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity) {
        
        IERC20 TokenA = IERC20(tokenA);
        TokenA.safeTransferFrom(msg.sender, address(this), amountADesired);

        IERC20 TokenB = IERC20(tokenB);
        TokenB.safeTransferFrom(msg.sender, address(this), amountBDesired);
        
        TokenA.safeApprove(uniswapV2RouterAddress, 0);
        TokenA.safeApprove(uniswapV2RouterAddress, amountADesired);

        TokenB.safeApprove(uniswapV2RouterAddress, 0);
        TokenB.safeApprove(uniswapV2RouterAddress, amountBDesired);

        (amountA, amountB, liquidity) = IUniswapV2Router02(uniswapV2RouterAddress).addLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin,
            to,
            deadline
        );

        if (amountADesired.sub(amountA) > 0) {
            TokenA.safeTransfer(msg.sender, amountADesired.sub(amountA));
        }

        if (amountBDesired.sub(amountB) > 0) {
            TokenB.safeTransfer(msg.sender, amountBDesired.sub(amountB));
        }
    }
}