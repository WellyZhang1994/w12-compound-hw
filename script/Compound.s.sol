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

        // baseRatePerBlock: 年基準利率 5%
        // multiplierPerBlock: 年利率乘数 
        // blocksPerYear = 2102400 按照 Ethereum 每15秒出一塊所計算
        // 參考 compound v2 WhitePaperInterestRateModel 合約 https://etherscan.io/address/0xd928c8ead620bb316d2cefe3caf81dc2dec6ff63#readContract
        // 若需要若需要轉換成以區塊為利息計算單位，並以 0.05% 作為年基準利率的話，baseRate = 5e16
        // multiplier 為 15e16
        uint baseRatePerYear = 5e16; 
        uint multiplierPerYear = 15e16; 

        // new underlying token 
        ERC20 underLyingToken = new ERC20("WELLYTK","WET");

        Comptroller comptroller = new Comptroller();
        // set the proxy contract for Comptroller
        Unitroller unitroller = new Unitroller();
        Comptroller unitrollerProxy = Comptroller(address(unitroller));
        unitroller._setPendingImplementation(address(comptroller));
        
        //Check caller is pendingImplementation and pendingImplementation ≠ address(0)
        //因此 _acceptImplementation 必須由 comptroller (Implementation) 合約進行呼叫
        //vm.prank(address(comptroller)); 無法在廣播裡使用 prank
        //unitroller._acceptImplementation();
        //使用 become 即可成功
        comptroller._become(unitroller);

        SimplePriceOracle simplePriceOracle = new SimplePriceOracle();
        unitrollerProxy._setPriceOracle(simplePriceOracle);
        unitrollerProxy._setCloseFactor(500000000000000000);
        unitrollerProxy._setLiquidationIncentive(1080000000000000000);

        WhitePaperInterestRateModel interestRateModel_ = new WhitePaperInterestRateModel(baseRatePerYear, multiplierPerYear);

        // new the implementation contract for the CErc20Delegator
        CErc20Delegate implementationContract = new CErc20Delegate();

        //The initial exchange rate, scaled by 1e18，1:1的話，應該是設定成 1e18
        new CErc20Delegator(
            address(underLyingToken),
            unitrollerProxy,
            interestRateModel_,
            1e18,
            "cWELLYTK",
            "cWET",
            18,
            payable(msg.sender),
            address(implementationContract),
            ""
        );
        
        vm.stopBroadcast();
    }
}