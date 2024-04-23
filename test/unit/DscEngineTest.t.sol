    // SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test , console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {DeployDSC} from "../../script/DeployDsc.s.sol";
import { DSCEngine } from "../../src/DSCEngine.sol";
import { DecentralizedStablecoin } from "../../src/DecentralizedStablecoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DscEngineTest is StdCheats, Test {

    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount); // if

    DeployDSC public deployer;
   
    DSCEngine public dsce;
    DecentralizedStablecoin public dsc;
    HelperConfig public helperConfig;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;
    address public user = address(1);
    address public USER = makeAddr("user");

    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;


     function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();
        if (block.chainid == 31_337) {
            vm.deal(user, STARTING_USER_BALANCE);
        }
        ERC20Mock(weth).mint(user, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(user, STARTING_USER_BALANCE);
    }


    ///////////////////////
    // Price Feeds Tests //
    ///////////////////////

    
    function testgetUsdValue() public  view  {
        uint256 ethAmount = 15e18;
       
        uint256 expectedUsd = 30_000e18;
        uint256 usdValue = dsce.getUsdValue(weth, ethAmount);
        assertEq(usdValue, expectedUsd);

    }



    
    ///////////////////////////////////////
    // depositCollateral Tests //
    ///////////////////////////////////////


    function testRevertifCollateralisZero() public {
        vm.startPrank(USER);

        ERC20Mock(weth).approve(address(dsce),amountCollateral);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);

        dsce.depositCollateral(weth,0);
        vm.stopPrank(); 
    }


}