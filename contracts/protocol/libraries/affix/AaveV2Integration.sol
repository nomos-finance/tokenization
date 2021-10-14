// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

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
        returns (IAaveIncentivesControllerV2);
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
}

interface IAaveIncentivesControllerV2 {
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
        address aToken;
        uint16 code;
    }

    // ============ Events ============

    // ============ Functions ============

    function getAtoken(AaveV2Integration.AaveV2 storage aaveV2)
        internal
        view
        returns (IAaveATokenV2)
    {
        require(aaveV2.aToken != address(0), "Invalid AToken address");
        return IAaveATokenV2(aaveV2.aToken);
    }

    function getIncentivesController(AaveV2Integration.AaveV2 storage aaveV2)
        internal
        view
        returns (IAaveIncentivesControllerV2)
    {
        IAaveIncentivesControllerV2 controller =
            aaveV2.getAtoken().getIncentivesController();
        require(
            address(controller) != address(0),
            "Invalid AaveIncentivesController address"
        );
        return controller;
    }

    function getBalance(AaveV2Integration.AaveV2 storage aaveV2)
        internal
        view
        returns (uint256 balance)
    {
        return aaveV2.getAtoken().balanceOf(address(this));
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
            aaveV2.getIncentivesController().claimRewards(assets, amount, to);
    }
}
