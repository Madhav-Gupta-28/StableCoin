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
    // Constructor Tests //
    ///////////////////////

    address[] public tokenAddresses;
    address[] public feedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        feedAddresses.push(ethUsdPriceFeed);
        feedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch.selector);
        new DSCEngine(tokenAddresses, feedAddresses, address(dsc));
    }


    ///////////////////////
    // Price Feeds Tests //
    ///////////////////////


    function testGetTokenAmountFromUsd() public {
        // If we want $100 of WETH @ $2000/WETH, that would be 0.05 WETH
        uint256 expectedWeth = 0.05 ether;
        uint256 amountWeth = dsce.getTokenAmountFromUsd(weth, 100 ether);
        assertEq(amountWeth, expectedWeth);
    }

    
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


    ///////////////////////////////////////
    // depositCollateral Tests //
    ///////////////////////////////////////

    function testRevertIfCollateralisZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce),amountCollateral);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth,0);
        vm.stopPrank();
    }


    function testRevertWithUnApprovedCollateral() public {

        ERC20Mock tryToken = new ERC20Mock("TRY", "TRY");
        tryToken.mint(user, amountCollateral);
        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, address(tryToken)));
        dsce.depositCollateral(address(tryToken), amountCollateral);
        vm.stopPrank();

    }

    

    function testRevertIfTransferFromFails() public {

        // Arrange Setup
    }


    modifier depositedCollateral() {
            vm.startPrank(user);
            ERC20Mock(weth).approve(address(dsce), amountCollateral);
            dsce.depositCollateral(weth, amountCollateral);
            vm.stopPrank();
             _;
    }

    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    function testCanDepositedCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);
        uint256 expectedDepositedAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, 0);
        assertEq(expectedDepositedAmount, amountCollateral);
    }


}