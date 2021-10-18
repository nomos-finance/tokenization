// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {
    SafeMath
} from "../../../dependencies/openzeppelin/contracts/SafeMath.sol";

/**
 * @dev Compound and Cream C Token interface
 * Documentation: https://compound.finance/developers/ctokens
 */
interface ICERC20 {
    /**
     * @notice The mint function transfers an asset into the protocol, which begins accumulating
     * interest based on the current Supply Rate for the asset. The user receives a quantity of
     * cTokens equal to the underlying tokens supplied, divided by the current Exchange Rate.
     * @param mintAmount The amount of the asset to be supplied, in units of the underlying asset.
     * @return 0 on success, otherwise an Error codes
     */
    function mint(uint256 mintAmount) external returns (uint256);

    /**
     * @notice The redeem underlying function converts cTokens into a specified quantity of the underlying
     * asset, and returns them to the user. The amount of cTokens redeemed is equal to the quantity of
     * underlying tokens received, divided by the current Exchange Rate. The amount redeemed must be less
     * than the user's Account Liquidity and the market's available liquidity.
     * @param redeemAmount The amount of underlying to be redeemed.
     * @return 0 on success, otherwise an Error codes
     */
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    /**
     * @notice The user's underlying balance, representing their assets in the protocol, is equal to
     * the user's cToken balance multiplied by the Exchange Rate.
     * @param owner The account to get the underlying balance of.
     * @return The amount of underlying currently owned by the account.
     */
    function balanceOfUnderlying(address owner) external returns (uint256);

    /**
     * @notice Calculates the exchange rate from the underlying to the CToken
     * @dev This function does not accrue interest before calculating the exchange rate
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateStored() external view returns (uint256);

    /**
     * @notice Get the token balance of the `owner`
     * @param owner The address of the account to query
     * @return The number of tokens owned by `owner`
     */
    function balanceOf(address owner) external view returns (uint256);

    function comptroller() external view returns (IComptroller);
}

interface IComptroller {
    /**
     * @notice Claim all the comp accrued by holder in all markets
     * @param holder The address to claim COMP for
     */
    function claimComp(address holder) external;

    function compAccrued(address holder) external view returns (uint256);
}

library CompoundInegration {
    using CompoundInegration for CompoundInegration.Compound;
    using SafeMath for uint256;
    // ============ Structs ============

    struct Compound {
        address cToken;
    }

    // ============ Functions ============

    function getBalance(CompoundInegration.Compound storage cAsset)
        internal
        view
        returns (uint256 balance)
    {
        ICERC20 ctoken = ICERC20(cAsset.cToken);
        return
            ctoken
                .balanceOf(address(this))
                .mul(ctoken.exchangeRateStored())
                .div(1e18);
    }

    function getReward(CompoundInegration.Compound storage cAsset)
        internal
        view
        returns (uint256)
    {
        return ICERC20(cAsset.cToken).comptroller().compAccrued(address(this));
    }

    function deposit(CompoundInegration.Compound storage cAsset, uint256 amount)
        internal
        returns (uint256)
    {
        return ICERC20(cAsset.cToken).mint(amount);
    }

    function withdraw(
        CompoundInegration.Compound storage cAsset,
        uint256 amount
    ) internal returns (uint256) {
        return ICERC20(cAsset.cToken).redeemUnderlying(amount);
    }

    function claim(CompoundInegration.Compound storage cAsset) internal {
        IComptroller comtroller = ICERC20(cAsset.cToken).comptroller();
        comtroller.claimComp(address(this));
    }
}
