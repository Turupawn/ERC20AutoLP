// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Pair {
    function sync() external;
}

interface IUniswapV2Router01 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );
}

interface IUniswapV2Router02 is IUniswapV2Router01 {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountETH);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;
}

contract MyToken is ERC20, Ownable
{
    bool private inSwap;
    bool private inFee;
    uint256 internal _buyFeeCollected;
    uint256 internal _sellFeeCollected;

    uint256 public minTokensBeforeSwap;
    
    address public buyWallet;
    address public sellWallet;

    IUniswapV2Router02 public router;
    address public pair;

    uint256 public _feeDecimal = 2;
    // index 0 = buy fee, index 1 = sell fee, index 2 = p2p fee
    uint256[] public _buyFee;
    uint256[] public _sellFee;

    bool public swapEnabled = true;
    bool public isFeeActive = true;

    mapping(address => bool) public isTaxless;

    mapping(address => bool) public blacklist;

    uint256 public launchedAt;
    uint256 public launchedAtTimestamp;

    event Swap(uint256 swaped, uint256 sentToBuyWallet, uint256 sentToSellWallet);

    constructor () ERC20("My Token", "TKN")
    {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);
        pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());
        router = _uniswapV2Router;

        buyWallet = 0xb6F5414bAb8d5ad8F33E37591C02f7284E974FcB;
        sellWallet = 0xb6F5414bAb8d5ad8F33E37591C02f7284E974FcB;

        //minTokensBeforeSwap = 1_000_000e9;
        minTokensBeforeSwap = 0.1 ether;

        _buyFee.push(1000);
        _buyFee.push(0);
        _buyFee.push(0);

        _sellFee.push(0);
        _sellFee.push(1000);
        _sellFee.push(0);

        isTaxless[msg.sender] = true;
        isTaxless[buyWallet] = true;
        isTaxless[sellWallet] = true;
        isTaxless[address(this)] = true;
        isTaxless[address(0)] = true;

        _mint(msg.sender, 1000 ether);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20)
    {
        super._afterTokenTransfer(from, to, amount);

        if(!inFee)
        {
            require(!blacklist[from] && !blacklist[to], "sender or recipient is blacklisted!");

            if (swapEnabled && !inSwap && from != pair) {
                swap();
            }

            if(!launched() && from == pair) {
                blacklist[to] = true;
            }

            uint256 feesCollected;
            if (isFeeActive && !isTaxless[from] && !isTaxless[to] && !inSwap) {
                bool sell = to == pair;
                bool p2p = from != pair && to != pair;
                feesCollected = calculateFee(p2p ? 2 : sell ? 1 : 0, amount);
            }

            //amount -= feesCollected;
            //_balances[from] -= feesCollected;
            //_balances[address(this)] += feesCollected;
            if(feesCollected > 0)
            {
                inFee = true;
                _transfer(to, address(this), feesCollected);
                inFee = false;
            }
        }
    }

    modifier lockTheSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    function sendViaCall(address payable _to, uint amount) private {
        (bool sent, bytes memory data) = _to.call{value: amount}("");
        data;
        require(sent, "Failed to send Ether");
    }

    function swap() private lockTheSwap {
        // How much are we swaping?
        uint256 totalCollected = _buyFeeCollected + _sellFeeCollected;

        if(minTokensBeforeSwap > totalCollected) return;

        // Let's swap for eth now
        address[] memory sellPath = new address[](2);
        sellPath[0] = address(this);
        sellPath[1] = router.WETH();       

        uint256 balanceBefore = address(this).balance;

        _approve(address(this), address(router), totalCollected);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            totalCollected,
            0,
            sellPath,
            address(this),
            block.timestamp
        );

        uint256 amountFee = address(this).balance - balanceBefore;
        
        // Send to marketing
        uint256 amountBuy = (amountFee * _buyFeeCollected) / totalCollected;
        if(amountBuy > 0) sendViaCall(payable(buyWallet), amountBuy);

        // Send to team
        uint256 amountSell = address(this).balance;
        if(amountSell > 0) sendViaCall(payable(sellWallet), address(this).balance);
        
        _buyFeeCollected = 0;
        _sellFeeCollected = 0;

        emit Swap(totalCollected, amountBuy, amountSell);
    }

    function calculateFee(uint256 feeIndex, uint256 amount) internal returns(uint256) {
        uint256 buyFee = (amount * _buyFee[feeIndex]) / (10**(_feeDecimal + 2));
        uint256 sellFee = (amount * _sellFee[feeIndex]) / (10**(_feeDecimal + 2));
        
        _buyFeeCollected += buyFee;
        _sellFeeCollected += sellFee;
        return buyFee + sellFee;
    }

    function setMinTokensBeforeSwap(uint256 amount) external onlyOwner {
        minTokensBeforeSwap = amount;
    }

    function setBuyWallet(address wallet)  external onlyOwner {
        buyWallet = wallet;
    }

    function setSellWallet(address wallet)  external onlyOwner {
        sellWallet = wallet;
    }

    function setBuyFee(uint256 buy, uint256 sell, uint256 p2p) external onlyOwner {
        _buyFee[0] = buy;
        _buyFee[1] = sell;
        _buyFee[2] = p2p;
    }

    function setSellFee(uint256 buy, uint256 sell, uint256 p2p) external onlyOwner {
        _sellFee[0] = buy;
        _sellFee[1] = sell;
        _sellFee[2] = p2p;
    }

    function setSwapEnabled(bool enabled) external onlyOwner {
        swapEnabled = enabled;
    }

    function setFeeActive(bool value) external onlyOwner {
        isFeeActive = value;
    }

    function setBlacklist(address account, bool isBlacklisted) external onlyOwner {
        blacklist[account] = isBlacklisted;
    }

    function multiBlacklist(address[] memory addresses, bool _bool) external onlyOwner {
        for (uint256 i = 0;i < addresses.length; i++){
            blacklist[addresses[i]] = _bool;
        }
    }

    function launch() public onlyOwner {
        require(launchedAt == 0, "Already launched boi");
        launchedAt = block.number;
        launchedAtTimestamp = block.timestamp;
    }

    function launched() internal view returns (bool) {
        return launchedAt != 0;
    }

    fallback() external payable {}
    receive() external payable {}
}