// SPDX-License-Identifier: MIT
pragma solidity >=0.8.6;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { WERC20 } from "./WERC20.sol";
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

contract CompoundSetup is Test {

    uint baseRatePerYear = 5e16; 
    uint multiplierPerYear = 12e16;

    WERC20 underLyingToken;

    Comptroller comptroller;
    Unitroller unitroller;
    Comptroller unitrollerProxy;
    SimplePriceOracle priceOracle;
    WhitePaperInterestRateModel interestRateModel;

    CErc20Delegate cWETDelegate;
    CErc20Delegator cWET;

    address admin = makeAddr("admin");

    function setUp() public virtual {
        vm.startPrank(admin);

        priceOracle = new SimplePriceOracle();
        interestRateModel = new WhitePaperInterestRateModel(baseRatePerYear,multiplierPerYear);
        unitroller = new Unitroller();
        comptroller = new Comptroller();                                        
        unitrollerProxy = Comptroller(address(unitroller));

        unitroller._setPendingImplementation(address(comptroller));
        comptroller._become(unitroller);

        unitrollerProxy._setPriceOracle(priceOracle);
        unitrollerProxy._setCloseFactor(500000000000000000);
        unitrollerProxy._setLiquidationIncentive(1080000000000000000);

        underLyingToken = new WERC20("WELLYTK","WET",18);

        cWETDelegate = new CErc20Delegate();
        bytes memory data = new bytes(0x00);
        cWET = new CErc20Delegator(
            address(underLyingToken), 
            ComptrollerInterface(address(unitroller)), 
            InterestRateModel(address(interestRateModel)),
            1e18,
            "cWELLYTK",
            "cWET",
            18,
            payable(address(admin)),
            address(cWETDelegate),
            data
        );
        cWET._setImplementation(address(cWETDelegate), false, data);
        cWET._setReserveFactor(250000000000000000);

        unitrollerProxy._supportMarket(CToken(address(cWET)));
        // 60%
        unitrollerProxy._setCollateralFactor(CToken(address(cWET)), 6e17);   

        vm.stopPrank();
    }
}