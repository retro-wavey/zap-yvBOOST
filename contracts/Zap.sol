// SPDX-License-Identifier: AGPL-3.0
// Feel free to change the license, but this is what we use

// Feel free to change this version of Solidity. We support >=0.6.0 <0.7.0;
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {
    SafeERC20,
    SafeMath,
    IERC20,
    Address
} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

interface ISwap {
    function swapExactTokensForTokens(
        uint256,
        uint256,
        address[] calldata,
        address,
        uint256
    ) external;
    function getAmountsOut(uint amountIn, address[] memory path) external view returns (uint[] memory amounts);
}

interface Pair {
    function getReserves() external view returns (
        uint112,
        uint112,
        uint32
    );
}

interface ICurveFi {
    function calc_withdraw_one_coin(uint256, int128) external view returns(uint256);
    function remove_liquidity_one_coin(uint256, int128, uint256) external;
}

interface IVoterProxy {
    function lock() external;
}

interface IyveCRV {
    function balanceOf(address) external view returns(uint256);
    function depositAll() external;
}

interface IyVault {
    function balanceOf(address) external view returns(uint256);
    function deposit() external;
    function pricePerShare() external view returns(uint256);
}

interface IWeth {
    function deposit() external payable;
}

library UniswapV2Library {
    using SafeMath for uint;
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }
}

contract Zap {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public constant yvBoost        = address(0x9d409a0A012CFbA9B15F6D4B36Ac57A46966Ab9a);
    address public constant yveCrv         = address(0xc5bDdf9843308380375a611c18B50Fb9341f502A);
    address public constant crv            = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address public constant weth           = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public constant sushiswap      = address(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    
    // Configurable preference for locking CRV in vault vs market-buying yvBOOST. 
    uint256 public mintBuffer           = 50;   // 5%
    uint256 public constant DENOMINATOR = 1000;

    address public governance = address(0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52);

    event UpdatedBuffer(uint256 newBuffer);
    event DepositEth(bool toCrv, uint256 adjustedCrvOut, uint256 adjustedYvBoostOut);
    event DepositCrv(bool minted, uint256 adjustedAmountFromMint, uint256 amountFromSwap);
    event DepositYveCrv(uint256 amount);
    
    modifier onlyGovernance() {
        require(msg.sender == governance, "!notgov");
        _;
    }

    constructor() public {
        IERC20(yveCrv).safeApprove(yvBoost, type(uint256).max);
        IERC20(crv).safeApprove(yveCrv, type(uint256).max);
        IERC20(crv).safeApprove(sushiswap, type(uint256).max);
        IERC20(weth).safeApprove(sushiswap, type(uint256).max);
    }

    function depositYveCrv(uint256 _amount, address recipient) external {
        IERC20(yveCrv).transferFrom(msg.sender, address(this), _amount);
        IyVault(yvBoost).deposit();
        sendToUser(recipient);
        emit DepositYveCrv(_amount);
    }

    function depositCrv(uint256 _amount, address recipient) external {
        // Check outputs for yvBOOST buy and backscratcher mint
        IERC20(crv).transferFrom(msg.sender, address(this), _amount);
        uint256 underlying = convertFromShares(quote(crv, yvBoost, _amount)); // convert to underlying
        uint256 adjustedAmountFromMint = _amount.mul(DENOMINATOR.add(mintBuffer)).div(DENOMINATOR);
        //emit BuyOrMint(shouldMint, fromSell, _amount);
        if(adjustedAmountFromMint >= underlying){
            mintDepositAndSend(recipient);
        }
        else{
            swap(crv, yvBoost, _amount);
            sendToUser(recipient);
        }
        emit DepositCrv(adjustedAmountFromMint >= underlying, adjustedAmountFromMint, underlying);
    }

    function depositEth(uint256 _amount, address recipient) public payable {
        require(msg.value == _amount, "ETH sent doesn't match amount");
        uint256 adjustedCrvOut = quote(weth, crv, _amount).mul(DENOMINATOR.add(mintBuffer)).div(DENOMINATOR);
        uint256 adjustedYvBoostOut = convertFromShares(quote(weth, yvBoost, _amount));
        IWeth(weth).deposit{value: _amount}();
        if(adjustedCrvOut > adjustedYvBoostOut){
            swap(weth, crv, _amount);
            mintDepositAndSend(recipient);
        }
        else{
            swap(weth, yvBoost, _amount);
            sendToUser(recipient);
        }
        emit DepositEth(adjustedCrvOut > adjustedYvBoostOut, adjustedCrvOut, adjustedYvBoostOut);
    }

    function mintDepositAndSend(address recipient) internal {
        IyveCRV(yveCrv).depositAll();
        IyVault(yvBoost).deposit();
        sendToUser(recipient);
    }

    function sendToUser(address recipient) internal {
        IERC20(yvBoost).safeTransfer(recipient, IERC20(yvBoost).balanceOf(address(this)));
    }

    function convertFromShares(uint256 _amount) internal returns (uint256) {
        return IyVault(yvBoost).pricePerShare().mul(_amount).div(1e18);
    }

    function quote(address token_in, address token_out, uint256 amount_in) internal view returns (uint256) {
        bool is_weth = token_in == weth || token_out == weth;
        address[] memory path = new address[](is_weth ? 2 : 3);
        path[0] = token_in;
        if (is_weth) {
            path[1] = token_out;
        } else {
            path[1] = weth;
            path[2] = token_out;
        }
        uint256[] memory amounts = ISwap(sushiswap).getAmountsOut(amount_in, path);
        return amounts[amounts.length - 1];
    }

    function swap(address token_in, address token_out, uint amount_in) internal {
        bool is_weth = token_in == weth || token_out == weth;
        address[] memory path = new address[](is_weth ? 2 : 3);
        path[0] = token_in;
        if (is_weth) {
            path[1] = token_out;
        } else {
            path[1] = weth;
            path[2] = token_out;
        }
        ISwap(sushiswap).swapExactTokensForTokens(
            amount_in,
            0,
            path,
            address(this),
            now
        );
    }

    function setBuffer(uint256 _newBuffer) external onlyGovernance {
        require(_newBuffer < DENOMINATOR, "!TooHigh");
        mintBuffer = _newBuffer;
        emit UpdatedBuffer(_newBuffer);
    }

    function setGovernance(address _governance) external onlyGovernance {
        governance = _governance;
    }

    function sweep(address _token) external onlyGovernance {
        IERC20(_token).safeTransfer(governance, IERC20(_token).balanceOf(address(this)));
    }

    receive() external payable {
        depositEth(msg.value, msg.sender);
    }
}
