// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

// import { OracleLib, AggregatorV3Interface } from "./libraries/OracleLib.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { DecentralizedStablecoin } from "./DecentralizedStableCoin.sol";
import {  AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/*
 * @title DSCEngine
 * @author Madhav Gupta
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */


contract DSCEngine is ReentrancyGuard {





    ///////////////////
    // Errors
    ///////////////////
    error DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenNotAllowed(address token);
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactorValue);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__BurnFailed();


    ////////////////////
    // Events
    ///////////////////
    event CollateralDeposited(address depositer , address collateral , uint256 amountOfCollateral);
    event CollateralReedeemed(address redeemer , address collateral , uint256 amountOfCollateral);





    /////////////////
    // State Variables
    /////////////////

    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant FEED_PRECISION = 1e8;

    DecentralizedStablecoin private immutable i_dsc;

    /// @dev Mapping of token address to  the price feed address of that token
    mapping(address collateralToken =>  address priceFeed)  private s_priceFeeds;

    ///  @dev Mapping of user to the amount of collateral deposited
    mapping(address user => mapping(address collateral => uint256 amount)) private s_collateralDeposited;

    /// @dev Amount of Stablecoin minted by user
    mapping(address user => uint256 amount) private s_DSCMinted;

    /// @dev list of tokens used as collaterals
    address[] private s_collateralTokens;


    //////////////////
    // Modifiers
    //////////////////

    modifier morethanZero(uint256 amount) {
        if(amount <= 0){
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }


    modifier isAllowedToken(address token) {
        if(s_priceFeeds[token] == address(0)){
            revert DSCEngine__TokenNotAllowed(token);
        }
        _;
    }


    ///////////////////////
    // Constructor
    ///////////////////////
    constructor(address[] memory tokenAddress , address[] memory priceFeedaddress , address dsc_stablecoin){

        if(tokenAddress.length != priceFeedaddress.length ){
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
        }

        for(uint8 i = 0 ; i < tokenAddress.length ; i++){
            s_priceFeeds[tokenAddress[i]] = priceFeedaddress[i];
            s_collateralTokens.push(tokenAddress[i]);

        }

        i_dsc = DecentralizedStablecoin(dsc_stablecoin);



    }

    ///////////////////////////
    // Functions
    //////////////////////////

    /**
    @param collateralAddress Address of the token user is depositing
    @param amountCollateral Amount of token user is depositing
    @param amountDscToMint Amount of Stablecoin that user want to mint
    @notice This  function will deposit collateral and mint DSC in one tx
     */
    function depositCollateralandMintDsc(address collateralAddress , uint256 amountCollateral , uint256 amountDscToMint) external {
        depositCollateral(collateralAddress,amountCollateral);
        mintDsc(amountDscToMint);

    }


    /**
    @param tokenCollateralAddress Address of the token user is depositing
    @param amountCollateral Amount of token user is depositing
     */
    function depositCollateral(address tokenCollateralAddress , uint256 amountCollateral) 
        public 
        nonReentrant 
        morethanZero(amountCollateral) 
        isAllowedToken(tokenCollateralAddress) {

            s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
            emit CollateralDeposited(msg.sender,tokenCollateralAddress,amountCollateral);
            
            bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);

            if(!success){
                revert DSCEngine__TransferFailed();
            }

    }

    function redeemCollateralForDsc(address tokenCollateralAddress , uint256 amountCollateral , uint256 dscAmountToBurn) external
        morethanZero(amountCollateral) morethanZero(dscAmountToBurn) isAllowedToken(tokenCollateralAddress) nonReentrant
        {
      
        _burnDSC(dscAmountToBurn,msg.sender,msg.sender);
        _redeemCollateral(tokenCollateralAddress,amountCollateral,msg.sender,msg.sender);
        _revertIfHealthFactorisBroken(msg.sender);

        }


    /*
    @param tokenCollateralAddress Address of the token user is redeeming
    @param amountofCollateraltoRedeem Amount of token user is redeeming
   */
    function redeemCollateral(
            address tokenCollateralAddress,
            uint256 amountofCollateraltoRedeem
        ) external morethanZero(amountofCollateraltoRedeem) isAllowedToken(tokenCollateralAddress) nonReentrant{

        _redeemCollateral(tokenCollateralAddress,amountofCollateraltoRedeem,msg.sender,msg.sender);
        _revertIfHealthFactorisBroken(msg.sender)   ;


    }


    /**
    @param amountDscToMint Amount of Stablecoin that user want to mint
    @notice They must have more collateral value than the minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) 
        public
        morethanZero(amountDscToMint)
        nonReentrant
        {
            s_DSCMinted[msg.sender] += amountDscToMint;

            _revertIfHealthFactorisBroken(msg.sender);

            bool minted = i_dsc.mint(msg.sender,amountDscToMint);

            if(minted !=  true){
                revert DSCEngine__MintFailed();
            }



    }


    /*
    @param amountToBurn Amount of Stablecoin that user want to burn
    @dev User might want to burn DSC to redeem collateral as well as in the fear of liquidation. so he/she can keep their position
    */
    function burnDsc(uint256 amountToBurn) external morethanZero(amountToBurn) {
        _burnDSC(amountToBurn,msg.sender,msg.sender);
        _revertIfHealthFactorisBroken(msg.sender);
    }


    /*
    @param tokenCollateralAddress Address of the token user is redeeming
    @param user Address of the user who is getting liquidated
    @param debtTocover Amount of debt user has to cover

    */
    function liquidate(address tokenCollateralAddress , address user  , uint256 debtTocover) 
        public  nonReentrant isAllowedToken(tokenCollateralAddress) morethanZero(debtTocover) {

        uint256 startingUserhealthFactor = _healthFactor(user);

        if(startingUserhealthFactor >= MIN_HEALTH_FACTOR){
            revert DSCEngine__HealthFactorOk();
        }

        uint256 tokenAmountFromdebtCovered = getTokenAmountFromUsd(tokenCollateralAddress,debtTocover);

        // Here We are calculating the 10% bonus we are going to give to the liquidator
        uint256 bonusCollateral  =( tokenAmountFromdebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        _redeemCollateral(tokenCollateralAddress,tokenAmountFromdebtCovered + bonusCollateral,user,msg.sender);
        _burnDSC(debtTocover,user,msg.sender);

        uint256 endingUserhealthFactor = _healthFactor(user);
        if(endingUserhealthFactor <= startingUserhealthFactor){
            revert DSCEngine__HealthFactorNotImproved();
        }

        _revertIfHealthFactorisBroken(msg.sender);



    }



    function gethealthfactor(address user) external view returns(uint256) {
        return _healthFactor(user);
    }



    /////////////////////
    // Helper Functions
    ////////////////////


    function getUsdValue(address token , uint256 amount) public  view returns(uint256){
        AggregatorV3Interface priceFeed =  AggregatorV3Interface(s_priceFeeds[token]);

        (,int256 price,,, ) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }   


    function getAccountCollateralValueinUSD(address user) public view returns(uint256 totalCollateralValueinUSD) {

        for(uint256 i = 0 ; i < s_collateralTokens.length ; i++){
           address token = s_collateralTokens[i];
           uint256 amount  =  s_collateralDeposited[user][token];
            totalCollateralValueinUSD +=  getUsdValue(token,amount);

        }   

        // returning the total value in usd of all collateral deposted by user
        return totalCollateralValueinUSD;

    }


    function _getAccountInformation(address user) private view returns(uint256 totalDscMinted ,uint256 collateralvalueinUSD){

        totalDscMinted = s_DSCMinted[user];
        collateralvalueinUSD = getAccountCollateralValueinUSD(user);
    }

    /**
    * How close the user is to liquidation
    * Is user is below 1. Then they can get liquidated
    */
    function _healthFactor(address user) internal view returns(uint256) {

        (uint256 totalDscMinted , uint256 collateralvalueinUSD) = _getAccountInformation(user);

        uint256 collateralAdjustedForThreshold =  (collateralvalueinUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;


    } 

    function _revertIfHealthFactorisBroken(address user) internal view  {

        uint256  userHealthFactor = _healthFactor(user);

        if(userHealthFactor < MIN_HEALTH_FACTOR){
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }


    }


    function _redeemCollateral(address tokenCollateralAddress , uint256 amountofCollateraltoRedeem , address from , address to) private {

        s_collateralDeposited[from][tokenCollateralAddress] -= amountofCollateraltoRedeem;

        emit CollateralReedeemed(from,tokenCollateralAddress,amountofCollateraltoRedeem);

        bool success = IERC20(tokenCollateralAddress).transfer(to,amountofCollateraltoRedeem);

        if(!success){
            revert DSCEngine__TransferFailed();
        }


    }
    

    function _burnDSC(uint256 amountToBurn , address onBehalfOf , address  dscFrom) private {

        s_DSCMinted[onBehalfOf] -= amountToBurn;

        bool success = i_dsc.transferFrom(dscFrom,address(this) ,  amountToBurn);

        if(!success){
            revert DSCEngine__TransferFailed();
        }

        i_dsc.burn(amountToBurn);


    }


    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }


    function getAccountInformation(address user) external view returns(uint256 totalDscMinted , uint256 collateralvalueinUSD) {
       return  _getAccountInformation(user);
    }

}