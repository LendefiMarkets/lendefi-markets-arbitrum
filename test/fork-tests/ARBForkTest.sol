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

contract ARBForkTest is BasicDeploy {
    // Arbitrum mainnet addresses
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f; // WBTC on Arbitrum
    address constant ARB = 0x912CE59144191C1204E64559FE8253a0e49E6548; // ARB token on Arbitrum
    address constant USDC_ARB = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    // Pools - Arbitrum mainnet (from networks.json)
    address constant WETH_USDC_POOL = 0xC6962004f452bE9203591991D15f6b388e09E8D0; // WETH/USDC pool
    address constant WETH_ARB_POOL = 0xC6F780497A95e246EB9449f5e4770916DCd6396A; // WETH/ARB pool
    address constant WBTC_WETH_POOL = 0x2f5e87C9312fa29aed5c179E456625D79015299c; // WBTC/WETH pool

    // Arbitrum mainnet Chainlink oracle addresses
    address constant WETH_CHAINLINK_ORACLE = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address constant WBTC_CHAINLINK_ORACLE = 0x6ce185860a4963106506C203335A2910413708e9;
    address constant ARB_CHAINLINK_ORACLE = 0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6; // ARB/USD oracle

    uint256 mainnetFork;
    address testUser;

    function setUp() public {
        // Fork Arbitrum mainnet at latest block
        mainnetFork = vm.createFork("arbitrum", 353117308); // Latest Arbitrum mainnet block
        vm.selectFork(mainnetFork);

        // Deploy protocol normally
        // First warp to a reasonable time for treasury deployment
        vm.warp(365 days);

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

        // Deploy ARB market
        _deployMarket(ARB, "Lendefi Yield Token", "LYTARB");

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

        // Configure assets - only WETH and ARB since we have pools for them
        _configureWETH();
        _configureARB();
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
                poolConfig: IASSETS.UniswapPoolConfig({pool: WETH_USDC_POOL, twapPeriod: 600, active: 1})
            })
        );

        vm.stopPrank();
    }

    function _configureARB() internal {
        vm.startPrank(address(timelockInstance));

        // Configure ARB with updated struct format
        assetsInstance.updateAssetConfig(
            ARB,
            IASSETS.Asset({
                active: 1,
                decimals: 18, // ARB has 18 decimals
                borrowThreshold: 650,
                liquidationThreshold: 700,
                maxSupplyThreshold: 50_000 * 1e18,
                isolationDebtCap: 0,
                assetMinimumOracles: 1,
                porFeed: address(0),
                primaryOracleType: IASSETS.OracleType.CHAINLINK,
                tier: IASSETS.CollateralTier.CROSS_A,
                chainlinkConfig: IASSETS.ChainlinkOracleConfig({oracleUSD: ARB_CHAINLINK_ORACLE, active: 1}),
                poolConfig: IASSETS.UniswapPoolConfig({pool: WETH_ARB_POOL, twapPeriod: 300, active: 1})
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

    function test_ChainlinkOracleARB() public view {
        (uint80 roundId, int256 answer,, uint256 updatedAt,) =
            AggregatorV3Interface(ARB_CHAINLINK_ORACLE).latestRoundData();
        console2.log("Direct ARB/USD oracle call:");
        console2.log("  RoundId:", roundId);
        console2.log("  Raw answer (8 decimals):", uint256(answer));
        console2.log("  Updated at:", updatedAt);
    }

    function test_ARBOracleProcessing() public view {
        console2.log("Testing ARB oracle processing...");

        uint256 chainlinkPrice = assetsInstance.getAssetPriceByType(ARB, IASSETS.OracleType.CHAINLINK);
        console2.log("ARB Chainlink price processed:", chainlinkPrice);

        uint256 uniswapPrice = assetsInstance.getAssetPriceByType(ARB, IASSETS.OracleType.UNISWAP_V3_TWAP);
        console2.log("ARB Uniswap price:", uniswapPrice);

        uint256 medianPrice = assetsInstance.getAssetPrice(ARB);
        console2.log("ARB median price:", medianPrice);
    }
}
