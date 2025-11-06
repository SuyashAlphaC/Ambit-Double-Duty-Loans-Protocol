// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {YieldDonatingStrategy, MarketParams} from "../src/strategies/yieldDonating/YieldDonatingStrategy.sol";
import {YieldDonatingTokenizedStrategy} from "@octant-core/strategies/yieldDonating/YieldDonatingTokenizedStrategy.sol";

contract DeployAmbit is Script {

    // Mainnet addresses from your src/test/yieldDonating/YieldDonatingSetup.sol
    address internal constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant SDAI_ADDRESS = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    address internal constant MORPHO_BLUE_ADDRESS = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    
    // Morpho sDAI/DAI Market Params from your test setup
    address internal constant ORACLE_ADDRESS = 0x9d4eb56E054e4bFE961F861E351F606987784B65;
    address internal constant IRM_ADDRESS = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    uint256 internal constant LLTV = 980000000000000000; // 98%

    function run() external {
        // --- 1. Get Deployer Key ---
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        console.log("Using Deployer Address:", deployerAddress);

        // --- 2. Set Admin Addresses ---
        // For the demo, we make the deployer all admin roles.
        address managementAddress = deployerAddress;
        address keeperAddress = deployerAddress;
        address emergencyAdminAddress = deployerAddress;

        // --- !! IMPORTANT: DONATION ADDRESS !! ---
        // For production, get the real Octant dragonRouter address.
        // For this demo, we use the deployer's address so you can
        // confirm the donated yield is successfully transferred to your wallet.
        address donationAddress = deployerAddress; 
        console.log("Using deployer as Management, Keeper, and Donation address.");

        // --- 3. Start Broadcast & Check Balances ---
        vm.startBroadcast(deployerPrivateKey);

        console.log("Checking Balances...");
        console.log("  Deployer ETH Balance:", (deployerAddress.balance) / 1e18, "ETH");
        uint256 daiBalance = IERC20(DAI_ADDRESS).balanceOf(deployerAddress);
        console.log("  Deployer DAI Balance:", daiBalance / 1e18, "DAI");

        require(deployerAddress.balance > 0.1 ether, "Deployer has insufficient ETH for gas.");
        require(daiBalance > 0, "Deployer has no DAI. Please faucet from Tenderly.");

        // --- 4. Deploy the TokenizedStrategy (The Vault) ---
        // This is the ERC4626-style vault contract that users deposit into.
        console.log("Deploying YieldDonatingTokenizedStrategy (Vault)...");
        YieldDonatingTokenizedStrategy tokenizedStrategy = new YieldDonatingTokenizedStrategy();
        console.log("Vault Deployed at:", address(tokenizedStrategy));
        
        // --- 5. Define the Morpho Market ---
        MarketParams memory marketParams = MarketParams({
            loanToken: DAI_ADDRESS,
            collateralToken: SDAI_ADDRESS,
            oracle: ORACLE_ADDRESS,
            irm: IRM_ADDRESS,
            lltv: LLTV
        });

        // --- 6. Deploy the Strategy Logic ---
        // This is your main contract that holds all the logic.
        // It links to the TokenizedStrategy (Vault) deployed above.
        console.log("Deploying YieldDonatingStrategy (Logic) and linking to vault...");
        YieldDonatingStrategy strategyLogic = new YieldDonatingStrategy(
            DAI_ADDRESS,
            "Ambit: Auto-Repaying Community Loan",
            managementAddress,
            keeperAddress,
            emergencyAdminAddress,
            donationAddress,
            true, // enableBurning
            address(tokenizedStrategy), // Link to the vault
            SDAI_ADDRESS, // sparkPool (sDAI is the pool)
            SDAI_ADDRESS, // sDAI
            MORPHO_BLUE_ADDRESS,
            marketParams
        );
        console.log("Strategy Logic Deployed at:", address(strategyLogic));
        
        console.log("Deployment Complete!");
        
        // This is the main address for your frontend
        console.log("---");
        console.log("TOKENIZED_STRATEGY_ADDRESS (for frontend):", address(tokenizedStrategy));
        console.log("---");

        vm.stopBroadcast();
    }
}