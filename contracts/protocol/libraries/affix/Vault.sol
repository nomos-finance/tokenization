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

    // ============ Enums ============
    enum Strategy {Local, Aave, Compound}

    // ============ Structs ============

    struct Storage {
        address foundation;
        address underlyingAsset;
        AaveV2Integration.AaveV2 aaveV2;
        CompoundInegration.Compound compound;
        uint256 debt;
        Strategy strategy;
        uint8 liquidityPercent;
        uint8 adjustPercent;
        bool initialize;
    }

    // ============ Events ============

    event StrategyAddress(address aaveV2, address atokenV2, address compound);

    event LiquidityPercent(uint8 liquidityPercent, uint8 adjustPercent);

    event NewFundation(address account);

    event NewStrategy(Strategy strategy);

    event Claim(Strategy strategy, uint256 amount);

    event Recover(Strategy strategy, uint256 amount);

    // ============ Functions ============

    function setStrategyAddress(
        Vault.Storage storage vault,
        address v2Aave,
        address v2AToken,
        address cToken
    ) internal {
        require(vault.initialize == false, "only once");
        vault.aaveV2.poolAddress = v2Aave;
        vault.aaveV2.aToken = v2AToken;
        vault.compound.cToken = cToken;
        vault.initialize = true;
        emit StrategyAddress(v2Aave, v2AToken, cToken);
    }

    function setLiquidityPercent(
        Vault.Storage storage vault,
        uint8 liquidity,
        uint8 adjust
    ) internal {
        require(adjust < liquidity, "invalid parameter");
        require(liquidity < 100, "invalid parameter");
        vault.liquidityPercent = liquidity;
        vault.adjustPercent = adjust;
        emit LiquidityPercent(liquidity, adjust);
    }

    function setFundation(Vault.Storage storage vault, address account)
        internal
    {
        require(account != address(0), "account can't be zero");
        vault.foundation = account;
        emit NewFundation(account);
    }

    function liquidity(Vault.Storage storage vault)
        internal
        view
        returns (uint256)
    {
        return IERC20(vault.underlyingAsset).balanceOf(address(this));
    }

    function totalLiquidity(Vault.Storage storage vault)
        internal
        view
        returns (uint256)
    {
        return vault.liquidity().add(vault.debt);
    }

    function incomings(Vault.Storage storage vault)
        internal
        view
        returns (uint256)
    {
        if (vault.strategy == Strategy.Local) return 0;
        if (vault.strategy == Strategy.Compound)
            return vault.compound.getBalance().sub(vault.debt);
        else return vault.aaveV2.getBalance().sub(vault.debt);
    }

    function recoverIncoming(Vault.Storage storage vault) internal {
        if (vault.strategy == Strategy.Local) return;
        require(vault.foundation != address(0), "set foundtion address please");
        uint256 amount = vault.incomings();
        if (vault.strategy == Strategy.Compound) {
            require(0 == vault.compound.withdraw(amount));
        } else
            vault.aaveV2.withdraw(
                vault.underlyingAsset,
                vault.foundation,
                amount
            );
        emit Recover(vault.strategy, amount);
    }

    function claimRewards(Vault.Storage storage vault) internal {
        require(vault.foundation != address(0), "set foundtion address please");
        if (vault.strategy == Strategy.Local) return;
        uint256 rewards = 0;
        if (vault.strategy == Strategy.Compound) {
            rewards = vault.compound.getReward();
            vault.compound.claim();
        } else
            rewards = vault.aaveV2.claim(
                vault.underlyingAsset,
                vault.foundation
            );

        emit Claim(vault.strategy, rewards);
    }

    function withdraw(Vault.Storage storage vault, uint256 amount) internal {
        require(amount <= vault.debt, "not enough balance");
        if (vault.strategy == Strategy.Local) return;
        else if (vault.strategy == Strategy.Compound)
            require(0 == vault.compound.withdraw(amount));
        else
            vault.aaveV2.withdraw(vault.underlyingAsset, address(this), amount);
        vault.debt.sub(amount);
    }

    function deposit(Vault.Storage storage vault, uint256 amount) internal {
        if (vault.strategy == Strategy.Local) return;
        else if (vault.strategy == Strategy.Compound)
            require(0 == vault.compound.deposit(amount));
        else vault.aaveV2.deposit(vault.underlyingAsset, amount);
        vault.debt.add(amount);
    }

    function decreasePosition(Vault.Storage storage vault, uint256 amount)
        internal
    {
        uint256 lastSupply = vault.totalLiquidity();
        require(amount <= lastSupply, "not enough balance");
        uint256 newSupply = lastSupply.sub(amount);
        uint256 lastLiquidity = vault.liquidity();

        if (
            amount < lastLiquidity &&
            lastLiquidity.sub(amount) >
            newSupply.mul(vault.adjustPercent).div(100)
        ) {
            return;
        }
        vault.withdraw(
            newSupply.mul(vault.liquidityPercent).div(100).add(amount).sub(
                lastLiquidity
            )
        );
    }

    function adjustPosition(Vault.Storage storage vault) internal {
        uint256 newLiquidity =
            vault.totalLiquidity().mul(vault.liquidityPercent).div(100);
        uint256 lastLiquidity = vault.liquidity();
        require(lastLiquidity != newLiquidity, "Redundant operation");
        if (lastLiquidity > newLiquidity) {
            vault.deposit(lastLiquidity.sub(newLiquidity));
        } else {
            vault.withdraw(newLiquidity.sub(lastLiquidity));
        }
    }

    function adjustStrategy(Vault.Storage storage vault, Strategy strategy)
        internal
    {
        Strategy lastStrategy = vault.strategy;
        require(strategy != lastStrategy, "same strategy");
        if (lastStrategy == Strategy.Local) {
            vault.strategy = strategy;
            vault.adjustPosition();
            emit NewStrategy(strategy);
            return;
        }

        require(vault.foundation != address(0), "set foundtion address please");
        address underlying = vault.underlyingAsset;
        uint256 incoming = 0;
        vault.claimRewards();
        if (lastStrategy == Strategy.Aave) {
            incoming = vault.aaveV2.getBalance().sub(vault.debt);
            vault.aaveV2.withdraw(underlying, address(this), uint256(-1));
        } else {
            uint256 amount = vault.compound.getBalance();
            incoming = amount.sub(vault.debt);
            require(0 == vault.compound.withdraw(amount));
        }

        if (strategy == Strategy.Aave)
            vault.aaveV2.deposit(
                vault.underlyingAsset,
                vault.debt.add(incoming)
            );
        else if (strategy == Strategy.Compound)
            require(0 == vault.compound.deposit(vault.debt.add(incoming)));
        else if (strategy == Strategy.Local) {
            vault.debt = 0;
            IERC20(vault.underlyingAsset).safeTransfer(
                vault.foundation,
                incoming
            );
        }
        vault.strategy = strategy;
        emit NewStrategy(strategy);
    }

    function safeTransfer(
        Vault.Storage storage vault,
        address to,
        uint256 amount
    ) internal {
        if (vault.strategy != Strategy.Local) vault.decreasePosition(amount);
        IERC20(vault.underlyingAsset).safeTransfer(to, amount);
    }
}
