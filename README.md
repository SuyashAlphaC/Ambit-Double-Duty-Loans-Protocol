***

# Ambit : Double Duty Yield : Auto-repaying loans, self-funding public goods 

![Ambit Logo](Image%20Gallery/Logo.png)

## 1. High-Level Concept: The "Buy-One-Get-One" for DAOs

![Home Screen](Image%20Gallery/Home.png)

This project implements the **"Auto-Repaying Public Goods Loan"** strategy, a sophisticated, dual-benefit system built for the Octant `YieldDonatingStrategy` framework.

It's designed for a DAO treasury (or any user) to deposit a base asset like DAI and achieve two goals simultaneously, creating a "buy-one-get-one" for public goods:

1.  **Fund Public Goods:** It generates yield from lending interest and donates 100% of it to the Octant public goods fund (the `dragonRouter`).
2.  **Provide a Community Service:** It uses a *separate, primary* yield source (Spark's sDAI) to automatically pay down the loan principals for a whitelist of community members.

The DAO's treasury itself remains 1:1 pegged to their deposit, as all generated yield is "donated" in one of these two ways.

---

## 2. Core Architecture: The "Winning Twist"

![Architecture Chart](Image%20Gallery/Chart.png)

The strategy's architecture, implemented in `src/strategies/yieldDonating/YieldDonatingStrategy.sol`, is a multi-step process that creates two distinct yield streams.


### `_deployFunds(uint256 _amount)`: Building the Engine

When a user (e.g., a DAO) deposits DAI, the `_deployFunds` function executes the following:

1.  **Earn Base Yield:** The strategy deposits 100% of the incoming `_amount` (DAI) into Spark Protocol to receive `sDAI`. This `sDAI` immediately starts earning the DSR (DAI Savings Rate), which becomes our **Primary Yield**.
2.  **Provide Collateral:** The strategy takes this `sDAI` and supplies it as collateral to an isolated Morpho Blue market.
3.  **Borrow (Create Liquidity):** It then borrows DAI against its own `sDAI` collateral, up to a safe `targetLTV` (defaulted to 50%).
4.  **Create Lending Pool:** Finally, it supplies this *borrowed* DAI back into the *same* Morpho market. This supplied DAI becomes the loanable liquidity for the community. The interest paid by community members on this liquidity becomes our **Secondary Yield**.

At this point, the strategy is in a stable state:
* It's earning **DSR (Yield 1)** on its `sDAI` collateral.
* It's earning **Morpho lending interest (Yield 2)** on its `DAI` supply.
* It's paying Morpho borrow interest on its `DAI` debt (which is offset by the lending interest).

---

## 3. The Dual-Yield Mechanism: `_harvestAndReport()`

This is the core logic of the entire project, where the two yield streams are separated and routed to their destinations.
![Second View](Image%20Gallery/Second.png)

### Primary Yield (DSR) -> Auto-Repayment

1.  **Calculate DSR Profit:** The strategy calculates the appreciation of its sDAI collateral by checking `sDAI.convertToAssets(vaultPos.collateral)` against its `lastCollateralValue`. This profit is the `dsrProfit`.
2.  **Withdraw Profit:** If `dsrProfit` is greater than zero and there are community members to repay, the strategy withdraws this profit by redeeming the equivalent amount of `sDAI` for `DAI`.
3.  **Distribute Repayments:** The strategy calculates the `totalCommunityDebt` by iterating through the `communityBorrowers` array and checking each member's debt position on Morpho.
4.  **Auto-Repay:** It then iterates a second time, calculating each borrower's pro-rata share of the DSR profit. The strategy calls `MORPHO_BLUE.repay(..., communityBorrowers[i])`, using the `onBehalf` parameter to directly pay down the principal of that community member's loan.

### Secondary Yield (Morpho Interest) -> Public Goods Donation

1.  **Calculate Interest Profit:** The strategy calculates the interest earned from its *supply* position in the Morpho market (the `lendingInterest`). This is the interest paid by the community borrowers.
2.  **Withdraw Profit:** It withdraws this `lendingInterest` (as DAI) from its Morpho supply position.
3.  **Donate to Public Goods:** The strategy then transfers 100% of this `withdrawn` DAI directly to the `dragonRouter` address, fulfilling its duty as a `YieldDonatingStrategy`.

### The 1:1 Peg

Crucially, the function returns `oldTotalAssets`. This reports **zero profit** to the Octant `TokenizedStrategy` layer. By doing this, the vault's share price remains perfectly stable at 1:1 with DAI. The DAO's treasury value doesn't grow; instead, the "profit" is redirected to the community and public goods, which is the entire point.

---

## 4. Withdrawal Logic & The 1200 Wei Tolerance

A critical piece of implementation is the withdrawal logic in `_freeFunds` and `_withdrawProportionally`. This is also the source of the ~1200 wei tolerance seen in the tests.

**This tolerance is not a bug; it is a feature of robust, safe design.**

### The "Dusty" Unwind Problem

When a user wants to withdraw 100% of their funds, the strategy must unwind its complex position:
1.  Withdraw supplied DAI from Morpho.
2.  Use that DAI to repay its Morpho debt.
3.  Withdraw its sDAI collateral from Morpho.
4.  Redeem that sDAI for DAI to return to the user.

The problem is that on-chain math creates "dust." Due to rounding or micro-second interest accrual, even after repaying what it *thinks* is 100% of its debt, the strategy might still owe `1 wei` of debt. If it then tries to withdraw 100% of its collateral, the Morpho protocol will revert the transaction because a position with debt cannot have zero collateral.

### The Solution: `_withdrawProportionally`

Our implementation (`_withdrawProportionally`) solves this elegantly:

1.  **Unwind Supply & Repay:** The strategy first withdraws its supplied DAI and repays its debt, *explicitly repaying by assets, not shares*, which is more robust against rounding.
2.  **Check for Dust:** It then *re-checks* its position *after* the repayment to see if any `remainingDebtAssets` (dust) still exist.
3.  **Leave Collateral Dust:** If it's a full unwind and `remainingDebtAssets > 0`, the strategy *intentionally leaves a tiny amount of collateral behind*. It calculates the exact `collateralDustShares` (e.g., 1200 wei) needed to safely cover the `remainingDebtAssets` (e.g., 10 wei) based on the market's LTV.
4.  **Succeed:** The withdrawal succeeds, returning the full amount *minus* the ~1200 wei of collateral dust, which is necessary for the transaction to complete.

### `assertApproxEqAbs` in Tests

This is why the tests in `YieldDonatingShutdown.t.sol` use `assertApproxEqAbs(finalBalance, expected, 1200, ...)`. This test confirms that the user receives their full expected amount, with an "acceptable error" of 1200 wei, which we know is the collateral dust *intentionally* left behind for safety.

---

## 5. Test Suite Verification

The project is validated by a comprehensive test suite in `src/test/yieldDonating/`.

* **`YieldDonatingSetup.sol` (The Environment):** This is the most important setup file. It **forks Ethereum mainnet** and uses the *real, live addresses* for DAI, sDAI, and Morpho Blue. To allow for large-scale fuzz testing, it uses cheatcodes to `deal` 50 million DAI to a test address and `supply` it to the Morpho market, ensuring our tests run against a realistic, liquid environment.

* **`YieldDonatingOperation.t.sol` (The "Happy Path"):**
    * `test_profitableReport`: This test is the core proof of the 1:1 peg. It deposits, skips time (allowing yield to accrue), calls `report()`, and then confirms the user can withdraw their *exact* original deposit. This proves that all yield was correctly skimmed off (to donations/repayments) and the user's principal is safe and not affected by yield.

* **`YieldDonatingShutdown.t.sol` (The "Exit Logic"):**
    * `test_shutdownCanWithdraw`: This test proves the strategy is safe even when shut down. It deposits, skips time, calls `strategy.shutdownStrategy()`, and confirms the user can still redeem their funds. This test correctly uses `assertApproxEqAbs`, verifying our "collateral dust" logic works.
    * `test_emergencyWithdraw_maxUint`: This confirms the `emergencyWithdraw` function (which also uses `_withdrawProportionally`) can handle `type(uint256).max` and that the user's funds are recoverable, again validating the dust-handling logic.

***