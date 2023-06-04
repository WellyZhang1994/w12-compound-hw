// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "forge-std/script.sol";
import "forge-std/console.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { CErc20Delegator } from "compound-protocol/contracts/CErc20Delegator.sol";
import { CErc20Delegate } from "compound-protocol/contracts/CErc20Delegate.sol";
import { CErc20 } from "compound-protocol/contracts/CErc20.sol";
import { CToken } from "compound-protocol/contracts/CToken.sol";
import { ComptrollerInterface } from "compound-protocol/contracts/ComptrollerInterface.sol";
import { InterestRateModel } from "compound-protocol/contracts/InterestRateModel.sol";
import { Comptroller } from "compound-protocol/contracts/Comptroller.sol";
import { WhitePaperInterestRateModel } from "compound-protocol/contracts/WhitePaperInterestRateModel.sol";
import { Unitroller } from "compound-protocol/contracts/Unitroller.sol";
import { SimplePriceOracle } from "compound-protocol/contracts/SimplePriceOracle.sol";
import { PriceOracle } from "compound-protocol/contracts/PriceOracle.sol";

contract MyScript is Script {
    function run() external {
        vm.startBroadcast();

        // baseRatePerBlock: 年基準利率
        // multiplierPerBlock: 年利率乘数
        // blocksPerYear = 2102400 按照 Ethereum 每15秒出一塊所計算
        // 若需要若需要轉換成以區塊為利息計算單位，並以 0.05% 作為年基準利率的話，baseRatePerYear 為 10513
        // 同上，須將年利率乘數轉換為區塊計算，帶入後要除以 blocksPerYear，因此這邊設定為 105 / 2102400 = 0.00005
        uint baseRatePerYear = 10513; 
        uint multiplierPerYear = 105; 

        // new underlying token 
        ERC20 underLyingToken = new ERC20("WELLYTK","WET");

        // the simple oracle is used to be a price feed from chainlink to Comptroller
        SimplePriceOracle simplePriceOracle = new SimplePriceOracle();
        PriceOracle oracle = PriceOracle(simplePriceOracle);

        Comptroller comptroller = new Comptroller();
        comptroller._setPriceOracle(oracle);

        ComptrollerInterface comptroller_ = ComptrollerInterface(address(comptroller));
        WhitePaperInterestRateModel whitePaperContract = new WhitePaperInterestRateModel(baseRatePerYear, multiplierPerYear);
        InterestRateModel interestRateModel_ = InterestRateModel(address(whitePaperContract));

        // new the implementation contract for the CErc20Delegator
        CErc20Delegate implementationContract = new CErc20Delegate();

        new CErc20Delegator(
            address(underLyingToken),
            comptroller_,
            interestRateModel_,
            1,
            "cWELLYTK",
            "cWET",
            18,
            payable(msg.sender),
            address(implementationContract),
            ""
        );
        
        // set the proxy contract for Comptroller
        Unitroller newUnit = new Unitroller();
        newUnit._setPendingImplementation(address(comptroller));
        newUnit._acceptImplementation();
        
        vm.stopBroadcast();
    }
}