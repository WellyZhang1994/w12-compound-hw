// SPDX-License-Identifier: MIT
pragma solidity >=0.8.6;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { WERC20 } from "./helper/WERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { CErc20Delegator } from "compound-protocol/contracts/CErc20Delegator.sol";
import { CErc20Delegate } from "compound-protocol/contracts/CErc20Delegate.sol";
import { CErc20 } from "compound-protocol/contracts/CErc20.sol";
import { CToken } from "compound-protocol/contracts/CToken.sol";
import { CTokenInterface } from "compound-protocol/contracts/CTokenInterfaces.sol";
import { ComptrollerInterface } from "compound-protocol/contracts/ComptrollerInterface.sol";
import { InterestRateModel } from "compound-protocol/contracts/InterestRateModel.sol";
import { Comptroller } from "compound-protocol/contracts/Comptroller.sol";
import { WhitePaperInterestRateModel } from "compound-protocol/contracts/WhitePaperInterestRateModel.sol";
import { Unitroller } from "compound-protocol/contracts/Unitroller.sol";
import { SimplePriceOracle } from "compound-protocol/contracts/SimplePriceOracle.sol";
import { PriceOracle } from "compound-protocol/contracts/PriceOracle.sol";
import { CompoundSetup } from "./helper/CompoundSetup.t.sol";

contract CompoundTest is CompoundSetup {

    address user = makeAddr("user");
    address liquidator = makeAddr("liquidator");

    WERC20 underLyingTokenB;
    WhitePaperInterestRateModel interestRateModelB;
    CErc20Delegate cTokenBDelegate;
    CErc20Delegator cTokenB;
        
    function setUp() public override {
        //init cWET (cERC20) token
        super.setUp();

        //deploy new cERC20 token "tokenB"
        vm.startPrank(admin);
        uint baseRatePerYearTokenB = 5e16; 
        uint multiplierPerYearTokenB = 12e16;
        interestRateModelB = new WhitePaperInterestRateModel(baseRatePerYearTokenB,multiplierPerYearTokenB);
        underLyingTokenB = new WERC20("TOKENB","TOKENB",18);
        cTokenBDelegate = new CErc20Delegate();
        bytes memory data2 = new bytes(0x00);
        cTokenB = new CErc20Delegator(
            address(underLyingTokenB), 
            ComptrollerInterface(address(unitroller)), 
            InterestRateModel(address(interestRateModelB)),
            1e18,
            "TOKENB",
            "TOKENB",
            18,
            payable(address(admin)),
            address(cTokenBDelegate),
            data2
        );
        cTokenB._setImplementation(address(cTokenBDelegate), false, data2);
        cTokenB._setReserveFactor(250000000000000000);

        //在 Oracle 中設定一顆 token A 的價格為 $1，一顆 token B 的價格為 $100
        //必須要先設定 oraclePrice 才能 call _setCollateralFactor (controller 會判斷 oracle price 是否為0)
        priceOracle.setDirectPrice(address(underLyingToken), 1e18);
        priceOracle.setDirectPrice(address(underLyingTokenB), 100e18);

        //set tokenB to the market and give CollateralFactor for 50%
        unitrollerProxy._supportMarket(CToken(address(cTokenB)));
        unitrollerProxy._setCollateralFactor(CToken(address(cTokenB)), 5e17);   

        //先給 user 一些 tokenA and tokenB
        underLyingToken.mint(address(user), 1e18);
        underLyingTokenB.mint(address(user), 1e18);

        // 讓 admin 製造一下 cWET token，供給市場讓 user 可以去借錢
        underLyingToken.mint(admin, 100e18);
        address[] memory cTokenAddrForAdmin = new address[](1);
        cTokenAddrForAdmin[0] = address(cWET);
        unitrollerProxy.enterMarkets(cTokenAddrForAdmin);
        underLyingToken.approve(address(cWET), 100e18);
        cWET.mint(100e18);
        vm.stopPrank();
        
    }

    function test_init() public {
        assertEq(underLyingToken.balanceOf(user),1e18);
        assertEq(underLyingTokenB.balanceOf(user),1e18);
    }

    function test_mint_and_redeem() public {

        vm.startPrank(user);
        address[] memory cTokenAddr = new address[](1);
        cTokenAddr[0] = address(cWET);
        unitrollerProxy.enterMarkets(cTokenAddr);

        underLyingToken.approve(address(cWET),1e18);

        cWET.mint(1e18);
        cWET.redeem(1e18);

        assertEq(underLyingToken.balanceOf(user),1e18);
    }

    function test_borrow_and_repay() public {

        vm.startPrank(user);
        address[] memory cTokenAddr = new address[](2);
        cTokenAddr[0] = address(cTokenB);
        cTokenAddr[1] = address(cWET);
        unitrollerProxy.enterMarkets(cTokenAddr);
        underLyingTokenB.approve(address(cTokenB), 1e18);
        // mint 1 顆 tokenA(CWET)
        cTokenB.mint(1e18);
        cWET.borrow(50e18);
        // 確認原始的 1顆 tokenA (underLyingToken) + 借來的 50顆，共51顆是否正確
        assertEq(underLyingToken.balanceOf(user),50e18 + 1e18);

        // 還錢之前要先 approve
        underLyingToken.approve(address(cWET), 50e18);
        cWET.repayBorrow(50e18);
        // 確認是否只剩下原先的 1顆
        assertEq(underLyingToken.balanceOf(user), 1e18); 
        vm.stopPrank();


    }

    //延續 (3.) 的借貸場景，調整 token B 的 collateral factor，讓 User1 被 User2 清算
    function test_liquidator_liquidate_user1_by_collateral_factor() public {

        vm.startPrank(user);
        address[] memory cTokenAddr = new address[](2);
        cTokenAddr[0] = address(cTokenB);
        cTokenAddr[1] = address(cWET);
        unitrollerProxy.enterMarkets(cTokenAddr);
        underLyingTokenB.approve(address(cTokenB), 1e18);
        // mint 1 顆 tokenA(CWET)
        cTokenB.mint(1e18);
        // 可以正常借，但是會到清算邊緣，把所有可 borrow 額度借滿
        cWET.borrow(50e18);
        vm.stopPrank();
        
        //此時因為 cTokenB 的 CollateralFactor 為 50%，所以可以正常借款，以下會調整為 40% 讓 User Account Liquidation 不足，使 liquidator 可以清算 User
        vm.startPrank(admin);
        unitrollerProxy._setCollateralFactor(CToken(address(cTokenB)), 4e17);
        //給 Liquidator 一些 underlying tokenA 讓 Liquidator 有一些 cTokenA
        underLyingToken.mint(address(liquidator), 100e18);
        vm.stopPrank();

        vm.startPrank(liquidator);
        underLyingToken.approve(address(cWET), 100e18);
        (uint error, uint liquidity, uint shortfall) = unitrollerProxy.getAccountLiquidity(address(user));
        //可被清算
        if (liquidity == 0 && shortfall>0)
        {
            CTokenInterface cTokenB = CTokenInterface(address(cTokenB));
            uint repayAmount = 1e18;
            cWET.liquidateBorrow(user, repayAmount, cTokenB);

        }
    }

    //延續 (3.) 的借貸場景，調整 oracle 中 token B 的價格，讓 User 被 Liquidator 清算
    function test_liquidator_liquidate_user1_by_oracleprice_for_tokenB() public {

        vm.startPrank(user);
        address[] memory cTokenAddr = new address[](2);
        cTokenAddr[0] = address(cTokenB);
        cTokenAddr[1] = address(cWET);
        unitrollerProxy.enterMarkets(cTokenAddr);
        underLyingTokenB.approve(address(cTokenB), 1e18);
        // mint 1 顆 tokenA(CWET)
        cTokenB.mint(1e18);
        // 可以正常借，但是會到清算邊緣，把所有可 borrow 額度借滿
        cWET.borrow(50e18);
        vm.stopPrank();
        
        //調整 oracle price，讓 token B 價格掉價，從 100 元 變成 10 元
        vm.startPrank(admin);
        priceOracle.setDirectPrice(address(underLyingTokenB), 10e18);
        //給 Liquidator 一些 underlying tokenA 讓 Liquidator 有一些 cTokenA
        underLyingToken.mint(address(liquidator), 100e18);
        vm.stopPrank();

        vm.startPrank(liquidator);
        underLyingToken.approve(address(cWET), 100e18);
        (uint error, uint liquidity, uint shortfall) = unitrollerProxy.getAccountLiquidity(address(user));
        //可被清算
        if (error == 0 && liquidity == 0 && shortfall>0)
        {
            CTokenInterface cTokenB = CTokenInterface(address(cTokenB));
            uint repayAmount = 1e18;
            cWET.liquidateBorrow(user, repayAmount, cTokenB);

        }
    }
}