// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {AaveV2Integration} from "./AaveV2Integration.sol";
import {CompoundInegration} from "./CompoundInegration.sol";
import {IERC20} from "../../../dependencies/openzeppelin/contracts/IERC20.sol";
import {
    SafeMath
} from "../../../dependencies/openzeppelin/contracts/SafeMath.sol";
import {
    SafeERC20
} from "../../../dependencies/openzeppelin/contracts/SafeERC20.sol";

library Vault {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Vault for Vault.Storage;
    using AaveV2Integration for AaveV2Integration.AaveV2;
    using CompoundInegration for CompoundInegration.Compound;

    // ============ Structs ============

    struct Storage {
        uint256 depositReserveRatio;
        uint256 alertPercent;
        address underlyingAsset;
        AaveV2Integration.AaveV2 aaveV2;
        CompoundInegration.Compound compound;
        bool aaveActive;
    }

    // ============ Events ============

    // ============ Functions ============

    function liquidity(Vault.Storage storage vault)
        internal
        view
        returns (uint256)
    {
        return IERC20(vault.underlyingAsset).balanceOf(address(this));
    }

    function totalSupply(Vault.Storage storage vault)
        internal
        view
        returns (uint256)
    {
        if (!vault.aaveActive) {
            //add compound paltform balance
            //return vault.liquidity().add(vault.compound.getBalance);
        }
        return
            vault.liquidity().add(
                vault.aaveV2.getBalance(vault.underlyingAsset)
            );
    }

    function withdraw(Vault.Storage storage vault, uint256 amount) internal {
        if (!vault.aaveActive) {
            return;
        }
        vault.aaveV2.withdraw(vault.underlyingAsset, address(this), amount);
    }

    function deposit(Vault.Storage storage vault, uint256 amount) internal {
        if (!vault.aaveActive) {
            return;
        }
        vault.aaveV2.deposit(vault.underlyingAsset, amount);
    }

    function decreasePosition(Vault.Storage storage vault, uint256 amount)
        internal
    {
        uint256 lastSupply = vault.totalSupply();
        require(amount <= lastSupply, "not enough balance");
        uint256 newSupply = lastSupply.sub(amount);
        uint256 lastLiquidity = vault.liquidity();

        if (
            amount < lastLiquidity &&
            lastLiquidity.sub(amount) >
            newSupply.mul(vault.alertPercent).div(100)
        ) {
            return;
        }
        vault.withdraw(
            newSupply.mul(vault.depositReserveRatio).div(100).add(amount).sub(
                lastLiquidity
            )
        );
    }

    function updatePosition(Vault.Storage storage vault) internal {
        uint256 newLiquidity =
            vault.totalSupply().mul(vault.depositReserveRatio).div(100);
        uint256 lastLiquidity = vault.liquidity();
        require(lastLiquidity != newLiquidity, "Redundant operation");
        if (lastLiquidity > newLiquidity) {
            vault.deposit(lastLiquidity.sub(newLiquidity));
        } else {
            vault.withdraw(newLiquidity.sub(lastLiquidity));
        }
    }

    function safeTransfer(
        Vault.Storage storage vault,
        address to,
        uint256 amount
    ) internal {
        vault.decreasePosition(amount);
        IERC20(vault.underlyingAsset).safeTransfer(to, amount);
    }
}
