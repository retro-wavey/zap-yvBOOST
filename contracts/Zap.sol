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
    function claimable(address) external view returns(uint256);
    function supplyIndex(address) external view returns(uint256);
    function balanceOf(address) external view returns(uint256);
    function index() external view returns(uint256);
    function claim() external;
    function depositAll() external;
}

interface IyVault {
    function balanceOf(address) external view returns(uint256);
    function deposit() external;
    function pricePerShare() external view returns(uint256);
}

interface IWeth {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
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
    event BuyOrMint(bool shouldMint, uint256 projBuyAmount, uint256 projMintAmount);
    event DepositEth(bool toCrv, uint256 amountOut, uint256 );
    event DepositCrv(bool minted, uint256 amount);
    event DepositYveCrv(bool minted, uint256 amount);
    
    modifier onlyGovernance() {
        require(msg.sender == governance, "!notgov");
        _;
    }

    constructor() public {
        // You can set these parameters on deployment to whatever you want
        IERC20(yveCrv).safeApprove(yvBoost, type(uint256).max);
        IERC20(crv).safeApprove(yveCrv, type(uint256).max);
        IERC20(crv).safeApprove(sushiswap, type(uint256).max);
        IERC20(weth).safeApprove(sushiswap, type(uint256).max);
    }

    function depositYveCrv(uint256 _amount, address recipient) external {
        // Happy path where user already has the vault's want
        IERC20(yveCrv).transferFrom(msg.sender, address(this), _amount);
        IyVault(yvBoost).deposit();
    }

    function depositCrv(uint256 _amount, address recipient) external {
        // Check outputs for yvBOOST buy and backscratcher mint
        IERC20(crv).transferFrom(msg.sender, address(this), _amount);
        (bool shouldMint, uint256 fromSell) = shouldMint(_amount);
        //emit BuyOrMint(shouldMint, fromSell, _amount);
        if(shouldMint){
            mintDepositAndSend(recipient);
        }
        else{
            swap(crv, yvBoost, _amount);
            sendToUser(recipient);
            
        }
    }

    function depositEth(uint256 _amount, address recipient) public payable {
        // Check outputs for yvBOOST buy and backscratcher mint
        // Should swap to YVBOOST or CRV?
        // Check swap outputs for CRV and YVBOOST
        require(address(this).balance == _amount, "ETH sent doesn't match amount");
        uint256 estWantFromCrvSwap = quote(weth, crv, _amount).mul(DENOMINATOR.add(mintBuffer)).div(DENOMINATOR);
        uint256 estWantFromYvBoostSwap = convertToFromShares(quote(weth, yvBoost, _amount));
        IWeth(weth).deposit{value: _amount}();
        if(estWantFromCrvSwap > estWantFromYvBoostSwap){
            //convert to weth
            swap(weth, crv, _amount);
            mintDepositAndSend(recipient);
        }
        else{
            swap(weth, yvBoost, _amount);
            sendToUser(recipient);
        }
        //emit DepositEth(bool minted, uint256 amount);
    }

    function mintDepositAndSend(address recipient) internal {
        IyveCRV(yveCrv).depositAll();
        IyVault(yvBoost).deposit();
        sendToUser(recipient);
    }

    function sendToUser(address recipient) internal {
        IERC20(yvBoost).safeTransfer(recipient, IERC20(yvBoost).balanceOf(address(this)));
    }

    function convertToFromShares(uint256 _amount) internal returns (uint256) {
        return IyVault(yvBoost).pricePerShare().mul(_amount);
    }

    // Here we determine if better to market-buy yvBOOST or mint it via backscratcher
    function shouldMint(uint256 _amountIn) public view returns (bool mint, uint256 projectedYveCrv) {
        // Using reserve ratios of swap pairs will allow us to compare whether it's more efficient to:
        //  1) Buy yvBOOST (unwrapped for yveCRV)
        //  2) Buy CRV (and use to mint yveCRV 1:1)
        address[] memory path = new address[](3);
        path[0] = crv;
        path[1] = weth;
        path[2] = yvBoost;
        uint256[] memory amounts = ISwap(sushiswap).getAmountsOut(_amountIn, path);
        uint256 projectedYvBoost = amounts[2];
        // Convert yvBOOST to yveCRV
        projectedYveCrv = projectedYvBoost.mul(IyVault(yvBoost).pricePerShare()).div(1e18); // save some gas by hardcoding 1e18

        // Here we favor minting by a % value defined by "mintBuffer"
        mint = _amountIn.mul(DENOMINATOR.add(mintBuffer)).div(DENOMINATOR) > projectedYveCrv;
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

    receive() external payable {
        depositEth(address(this).balance, msg.sender);
    }
}
