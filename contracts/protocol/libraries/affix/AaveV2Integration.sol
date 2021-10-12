// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {DataTypes} from "../types/DataTypes.sol";

interface IAaveATokenV2 {
    /**
     * @notice returns the current total aToken balance of _user all interest collected included.
     * To obtain the user asset principal balance with interests excluded , ERC20 non-standard
     * method principalBalanceOf() can be used.
     */
    function balanceOf(address _user) external view returns (uint256);

    /**
     * @dev Returns the address of the incentives controller contract
     **/
    function getIncentivesController()
        external
        view
        returns (IAaveIncentivesController);
}

interface IAaveLendingPoolV2 {
    /**
     * @dev deposits The underlying asset into the reserve. A corresponding amount of the overlying asset (aTokens)
     * is minted.
     * @param reserve the address of the reserve
     * @param amount the amount to be deposited
     * @param referralCode integrators are assigned a referral code and can potentially receive rewards.
     **/
    function deposit(
        address reserve,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    /**
     * @dev withdraws the assets of user.
     * @param reserve the address of the reserve
     * @param amount the underlying amount to be redeemed
     * @param to address that will receive the underlying
     **/
    function withdraw(
        address reserve,
        uint256 amount,
        address to
    ) external;

    /**
     * @dev Returns the state and configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The state of the reserve
     **/
    function getReserveData(address asset)
        external
        view
        returns (DataTypes.ReserveData memory);
}

interface IAaveIncentivesController {
    /**
     * @dev Claims reward for an user, on all the assets of the lending pool, accumulating the pending rewards
     * @param amount Amount of rewards to claim
     * @param to Address that will be receiving the rewards
     * @return Rewards claimed
     **/
    function claimRewards(
        address[] calldata assets,
        uint256 amount,
        address to
    ) external returns (uint256);

    /**
     * @dev Returns the total of rewards of an user, already accrued + not yet accrued
     * @param user The address of the user
     * @return The rewards
     **/
    function getRewardsBalance(address[] calldata assets, address user)
        external
        view
        returns (uint256);

    /**
     * @dev returns the unclaimed rewards of the user
     * @param user the address of the user
     * @return the unclaimed user rewards
     */
    function getUserUnclaimedRewards(address user)
        external
        view
        returns (uint256);
}

library AaveV2Integration {
    using AaveV2Integration for AaveV2Integration.AaveV2;

    // ============ Structs ============

    struct AaveV2 {
        address poolAddress;
        uint16 code;
    }

    // ============ Events ============

    // ============ Functions ============

    function getAtoken(AaveV2Integration.AaveV2 storage aaveV2, address asset)
        internal
        view
        returns (IAaveATokenV2)
    {
        DataTypes.ReserveData memory reserveData =
            IAaveLendingPoolV2(aaveV2.poolAddress).getReserveData(asset);
        require(
            reserveData.aTokenAddress != address(0),
            "Invalid atoken address"
        );
        return IAaveATokenV2(reserveData.aTokenAddress);
    }

    function getIncentivesController(
        AaveV2Integration.AaveV2 storage aaveV2,
        address asset
    ) internal view returns (IAaveIncentivesController) {
        IAaveIncentivesController controller =
            aaveV2.getAtoken(asset).getIncentivesController();
        require(
            address(controller) != address(0),
            "Invalid AaveIncentivesController address"
        );
        return controller;
    }

    function getBalance(AaveV2Integration.AaveV2 storage aaveV2, address asset)
        internal
        view
        returns (uint256 balance)
    {
        return aaveV2.getAtoken(asset).balanceOf(address(this));
    }

    function deposit(
        AaveV2Integration.AaveV2 storage aaveV2,
        address asset,
        uint256 amount
    ) internal {
        IAaveLendingPoolV2(aaveV2.poolAddress).deposit(
            asset,
            amount,
            address(this),
            aaveV2.code
        );
    }

    function withdraw(
        AaveV2Integration.AaveV2 storage aaveV2,
        address asset,
        address to,
        uint256 amount
    ) internal {
        IAaveLendingPoolV2(aaveV2.poolAddress).withdraw(asset, amount, to);
    }

    function claim(
        AaveV2Integration.AaveV2 storage aaveV2,
        address asset,
        address to,
        uint256 amount
    ) internal returns (uint256) {
        address[] memory assets = new address[](1);
        assets[0] = asset;
        return
            aaveV2.getIncentivesController(asset).claimRewards(
                assets,
                amount,
                to
            );
    }
}
