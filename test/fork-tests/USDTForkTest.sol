// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./BasicDeploy.sol";
import {console2} from "forge-std/console2.sol";
import {IASSETS} from "../../contracts/interfaces/IASSETS.sol";
import {IPROTOCOL} from "../../contracts/interfaces/IProtocol.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from
    "../../contracts/vendor/@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IUniswapV3Pool} from "../../contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract USDTForkTest is BasicDeploy {
    // Arbitrum mainnet addresses (from networks.json)
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address constant USDT_ARB = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant USDC_ARB = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    // Pools - Arbitrum mainnet (from networks.json)
    address constant USDT_WETH_POOL = 0x641C00A822e8b671738d32a431a4Fb6074E5c79d;
    address constant WBTC_USDT_POOL = 0x5969EFddE3cF5C0D9a88aE51E47d721096A97203;
    address constant WBTC_WETH_POOL = 0x2f5e87C9312fa29aed5c179E456625D79015299c;
    address constant USDC_USDT_POOL = 0xbE3aD6a5669Dc0B8b12FeBC03608860C31E2eef6;

    // Arbitrum mainnet Chainlink oracle addresses (from networks.json)
    address constant WETH_CHAINLINK_ORACLE = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612; // eth-usd
    address constant WBTC_CHAINLINK_ORACLE = 0x6ce185860a4963106506C203335A2910413708e9; // btc-usd
    address constant USDT_CHAINLINK_ORACLE = 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7; // usdt-usd

    uint256 mainnetFork;
    address testUser;

    function setUp() public {
        // Fork Arbitrum mainnet at latest block
        mainnetFork = vm.createFork("arbitrum", 353117308); // Latest Arbitrum mainnet block
        vm.selectFork(mainnetFork);

        // Deploy base contracts
        _deployTimelock();
        _deployToken();
        _deployEcosystem();
        _deployTreasury();
        _deployGovernor();
        _deployMarketFactory();

        // TGE setup - MUST be done before market creation
        vm.prank(guardian);
        tokenInstance.initializeTGE(address(ecoInstance), address(treasuryInstance));

        // Deploy USDT market
        _deployMarket(USDT_ARB, "Lendefi Yield Token", "LYTUSDT");

        // Now warp to current time to match oracle data (Jul-01-2025 12:01:47 PM +UTC)
        vm.warp(1751371307); // Exact block timestamp for block 353117308

        // Create test user
        testUser = makeAddr("testUser");
        vm.deal(testUser, 100 ether);

        // Setup roles
        vm.startPrank(guardian);
        timelockInstance.revokeRole(PROPOSER_ROLE, ethereum);
        timelockInstance.revokeRole(EXECUTOR_ROLE, ethereum);
        timelockInstance.revokeRole(CANCELLER_ROLE, ethereum);
        timelockInstance.grantRole(PROPOSER_ROLE, address(govInstance));
        timelockInstance.grantRole(EXECUTOR_ROLE, address(govInstance));
        timelockInstance.grantRole(CANCELLER_ROLE, address(govInstance));
        vm.stopPrank();

        // Configure assets
        console2.log("=== Starting asset configuration ===");
        console2.log("WETH address:", WETH);
        console2.log("USDT_WETH_POOL address:", USDT_WETH_POOL);
        console2.log("About to configure WETH...");
        _configureWETH();
        console2.log("WETH configured successfully");

        console2.log("WBTC address:", WBTC);
        console2.log("WBTC_WETH_POOL address:", WBTC_WETH_POOL);
        console2.log("About to configure CBBTC...");
        _configureWBTC();
        console2.log("CBBTC configured successfully");

        console2.log("USDT_ARB address:", USDT_ARB);
        console2.log("USDC_USDT_POOL address:", USDC_USDT_POOL);
        console2.log("About to configure USDT...");
        _configureUSDT();
        console2.log("USDT configured successfully");
    }

    function _configureWETH() internal {
        vm.startPrank(address(timelockInstance));

        // Configure WETH with updated struct format
        assetsInstance.updateAssetConfig(
            WETH,
            IASSETS.Asset({
                active: 1,
                decimals: 18,
                borrowThreshold: 800,
                liquidationThreshold: 850,
                maxSupplyThreshold: 1_000_000 ether,
                isolationDebtCap: 0,
                assetMinimumOracles: 1,
                porFeed: address(0),
                primaryOracleType: IASSETS.OracleType.CHAINLINK,
                tier: IASSETS.CollateralTier.CROSS_A,
                chainlinkConfig: IASSETS.ChainlinkOracleConfig({oracleUSD: WETH_CHAINLINK_ORACLE, active: 1}),
                poolConfig: IASSETS.UniswapPoolConfig({pool: USDT_WETH_POOL, twapPeriod: 300, active: 1})
            })
        );

        vm.stopPrank();
    }

    function _configureWBTC() internal {
        vm.startPrank(address(timelockInstance));

        // Configure WBTC with updated struct format
        assetsInstance.updateAssetConfig(
            WBTC,
            IASSETS.Asset({
                active: 1,
                decimals: 8, // WBTC has 8 decimals
                borrowThreshold: 700,
                liquidationThreshold: 750,
                maxSupplyThreshold: 500 * 1e8,
                isolationDebtCap: 0,
                assetMinimumOracles: 1,
                porFeed: address(0),
                primaryOracleType: IASSETS.OracleType.CHAINLINK,
                tier: IASSETS.CollateralTier.CROSS_A,
                chainlinkConfig: IASSETS.ChainlinkOracleConfig({oracleUSD: WBTC_CHAINLINK_ORACLE, active: 1}),
                poolConfig: IASSETS.UniswapPoolConfig({pool: WBTC_WETH_POOL, twapPeriod: 300, active: 1})
            })
        );

        vm.stopPrank();
    }

    function _configureUSDT() internal {
        vm.startPrank(address(timelockInstance));

        // Configure USDT with proper Chainlink oracle
        assetsInstance.updateAssetConfig(
            USDT_ARB,
            IASSETS.Asset({
                active: 1,
                decimals: 6,
                borrowThreshold: 950, // 95% - very safe for stablecoin
                liquidationThreshold: 980, // 98% - very safe for stablecoin
                maxSupplyThreshold: 1_000_000_000e6, // 1B USDT
                isolationDebtCap: 0,
                assetMinimumOracles: 1,
                porFeed: address(0),
                primaryOracleType: IASSETS.OracleType.CHAINLINK,
                tier: IASSETS.CollateralTier.STABLE,
                chainlinkConfig: IASSETS.ChainlinkOracleConfig({
                    oracleUSD: USDT_CHAINLINK_ORACLE, // Use actual USDT oracle
                    active: 1
                }),
                poolConfig: IASSETS.UniswapPoolConfig({pool: USDC_USDT_POOL, twapPeriod: 300, active: 1})
            })
        );

        vm.stopPrank();
    }

    function test_ChainlinkOracleETH() public view {
        (uint80 roundId, int256 answer,, uint256 updatedAt,) =
            AggregatorV3Interface(WETH_CHAINLINK_ORACLE).latestRoundData();

        console2.log("Direct ETH/USD oracle call:");
        console2.log("  RoundId:", roundId);
        console2.log("  Price:", uint256(answer) / 1e8);
        console2.log("  Updated at:", updatedAt);
    }

    function test_ChainLinkOracleBTC() public view {
        (uint80 roundId, int256 answer,, uint256 updatedAt,) =
            AggregatorV3Interface(WBTC_CHAINLINK_ORACLE).latestRoundData();
        console2.log("Direct BTC/USD oracle call:");
        console2.log("  RoundId:", roundId);
        console2.log("  Price:", uint256(answer) / 1e8);
        console2.log("  Updated at:", updatedAt);
    }

    function test_RealMedianPriceETH() public {
        // Get prices from both oracles
        uint256 chainlinkPrice = assetsInstance.getAssetPriceByType(WETH, IASSETS.OracleType.CHAINLINK);
        uint256 uniswapPrice = assetsInstance.getAssetPriceByType(WETH, IASSETS.OracleType.UNISWAP_V3_TWAP);

        console2.log("WETH Chainlink price:", chainlinkPrice);
        console2.log("WETH Uniswap price:", uniswapPrice);

        // Calculate expected median
        uint256 expectedMedian = (chainlinkPrice + uniswapPrice) / 2;

        // Get actual median
        uint256 actualPrice = assetsInstance.getAssetPrice(WETH);
        console2.log("WETH median price:", actualPrice);

        assertEq(actualPrice, expectedMedian, "Median calculation should be correct");
    }

    function test_RealMedianPriceBTC() public {
        // Get prices from both oracles
        uint256 chainlinkPrice = assetsInstance.getAssetPriceByType(WBTC, IASSETS.OracleType.CHAINLINK);
        uint256 uniswapPrice = assetsInstance.getAssetPriceByType(WBTC, IASSETS.OracleType.UNISWAP_V3_TWAP);

        console2.log("CBBTC Chainlink price:", chainlinkPrice);
        console2.log("CBBTC Uniswap price:", uniswapPrice);

        // Calculate expected median
        uint256 expectedMedian = (chainlinkPrice + uniswapPrice) / 2;

        // Get actual median
        uint256 actualPrice = assetsInstance.getAssetPrice(WBTC);
        console2.log("CBBTC median price:", actualPrice);

        assertEq(actualPrice, expectedMedian, "Median calculation should be correct");
    }

    function test_OracleTypeSwitch() public view {
        // Test oracle pricing for all assets with both Chainlink and Uniswap

        uint256 chainlinkPrice = assetsInstance.getAssetPriceByType(WETH, IASSETS.OracleType.CHAINLINK);
        console2.log("Chainlink ETH price:", chainlinkPrice);

        uint256 uniswapPrice = assetsInstance.getAssetPriceByType(WETH, IASSETS.OracleType.UNISWAP_V3_TWAP);
        console2.log("Uniswap ETH price:", uniswapPrice);

        uint256 chainlinkBTCPrice = assetsInstance.getAssetPriceByType(WBTC, IASSETS.OracleType.CHAINLINK);
        console2.log("Chainlink BTC price:", chainlinkBTCPrice);

        uint256 uniswapBTCPrice = assetsInstance.getAssetPriceByType(WBTC, IASSETS.OracleType.UNISWAP_V3_TWAP);
        console2.log("Uniswap BTC price:", uniswapBTCPrice);

        uint256 chainlinkUSDTPrice = assetsInstance.getAssetPriceByType(USDT_ARB, IASSETS.OracleType.CHAINLINK);
        console2.log("Chainlink USDT price:", chainlinkUSDTPrice);

        uint256 uniswapUSDTPrice = assetsInstance.getAssetPriceByType(USDT_ARB, IASSETS.OracleType.UNISWAP_V3_TWAP);
        console2.log("Uniswap USDT price:", uniswapUSDTPrice);
    }

    function testRevert_PoolLiquidityLimitReached() public {
        // Give test user more ETH
        vm.deal(testUser, 15000 ether); // Increase from 100 ETH to 15000 ETH

        // Create a user with WETH
        vm.startPrank(testUser);
        (bool success,) = WETH.call{value: 10000 ether}("");
        require(success, "ETH to WETH conversion failed");

        // Create a position
        uint256 positionId = marketCoreInstance.createPosition(WETH, false);
        console2.log("Created position ID:", positionId);
        vm.stopPrank();

        // Set maxSupplyThreshold high (100,000 ETH) to avoid hitting AssetCapacityReached
        vm.startPrank(address(timelockInstance));
        IASSETS.Asset memory wethConfig = assetsInstance.getAssetInfo(WETH);
        wethConfig.maxSupplyThreshold = 100_000 ether;
        assetsInstance.updateAssetConfig(WETH, wethConfig);
        vm.stopPrank();

        // Get actual WETH balance in the pool
        uint256 poolWethBalance = IERC20(WETH).balanceOf(USDT_WETH_POOL);
        console2.log("WETH balance in pool:", poolWethBalance / 1e18, "ETH");

        // Calculate 3% of pool balance
        uint256 threePercentOfPool = (poolWethBalance * 3) / 100;
        console2.log("3% of pool WETH:", threePercentOfPool / 1e18, "ETH");

        // Add a little extra to ensure we exceed the limit
        uint256 supplyAmount = threePercentOfPool + 1 ether;
        console2.log("Amount to supply:", supplyAmount / 1e18, "ETH");

        // Verify directly that this will trigger the limit
        bool willHitLimit = assetsInstance.poolLiquidityLimit(WETH, supplyAmount);
        console2.log("Will hit pool liquidity limit:", willHitLimit);
        assertTrue(willHitLimit, "Our calculated amount should trigger pool liquidity limit");

        // Supply amount exceeding 3% of pool balance
        vm.startPrank(testUser);
        IERC20(WETH).approve(address(marketCoreInstance), supplyAmount);
        vm.expectRevert(IPROTOCOL.PoolLiquidityLimitReached.selector);
        marketCoreInstance.supplyCollateral(WETH, supplyAmount, positionId);
        vm.stopPrank();

        console2.log("Successfully tested PoolLiquidityLimitReached error");
    }

    function testRevert_AssetLiquidityLimitReached() public {
        // Create a user with WETH
        vm.startPrank(testUser);
        (bool success,) = WETH.call{value: 50 ether}("");
        require(success, "ETH to WETH conversion failed");

        // Create a position
        marketCoreInstance.createPosition(WETH, false); // false = cross-collateral position
        uint256 positionId = marketCoreInstance.getUserPositionsCount(testUser) - 1;
        console2.log("Created position ID:", positionId);

        vm.stopPrank();

        // Update WETH config with a very small limit
        vm.startPrank(address(timelockInstance));
        IASSETS.Asset memory wethConfig = assetsInstance.getAssetInfo(WETH);
        wethConfig.maxSupplyThreshold = 1 ether; // Very small limit
        assetsInstance.updateAssetConfig(WETH, wethConfig);
        vm.stopPrank();

        // Supply within limit
        vm.startPrank(testUser);
        IERC20(WETH).approve(address(marketCoreInstance), 0.5 ether);
        marketCoreInstance.supplyCollateral(WETH, 0.5 ether, positionId);
        console2.log("Supplied 0.5 WETH");

        // Try to exceed the limit
        IERC20(WETH).approve(address(marketCoreInstance), 1 ether);
        vm.expectRevert(IPROTOCOL.AssetCapacityReached.selector);
        marketCoreInstance.supplyCollateral(WETH, 1 ether, positionId);
        vm.stopPrank();

        console2.log("Successfully tested PoolLiquidityLimitReached error");
    }

    function test_getAnyPoolTokenPriceInUSD_USDT() public {
        uint256 usdtPriceInUSD = assetsInstance.getAssetPrice(USDT_ARB);
        console2.log("USDT price in USD:", usdtPriceInUSD);

        // USDT should be close to $1.00
        assertTrue(usdtPriceInUSD > 0.98 * 1e6, "USDT price should be greater than $0.98");
        assertTrue(usdtPriceInUSD < 1.02 * 1e6, "USDT price should be less than $1.02");
    }

    function test_getAnyPoolTokenPriceInUSD_WBTC() public {
        uint256 wbtcPriceInUSD = assetsInstance.getAssetPrice(WBTC);
        console2.log("WBTC price in USD (median):", wbtcPriceInUSD);

        // WBTC uses median of Chainlink and Uniswap prices
        assertTrue(wbtcPriceInUSD > 90000 * 1e6, "WBTC price should be greater than $90,000");
        assertTrue(wbtcPriceInUSD < 120000 * 1e6, "WBTC price should be less than $120,000");
    }
}
