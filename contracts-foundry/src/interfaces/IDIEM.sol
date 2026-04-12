// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IDIEM
 * @notice Interface for the Venice DIEM token on Base
 * @dev DIEM has built-in staking with a cooldown period for unstaking
 *
 * Address on Base: 0xf4d97f2da56e8c3098f3a8d538db630a2606a024
 */
interface IDIEM is IERC20 {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct StakedInfo {
        uint256 amountStaked;
        uint256 coolDownEnd;
        uint256 coolDownAmount;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event UnstakeInitiated(address indexed user, uint256 amount);
    event CooldownDurationUpdated(uint256 cooldownDuration);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Cooldown period for withdrawals (default: 1 day)
    function cooldownDuration() external view returns (uint256);

    /// @notice Total amount of Diem staked in the DIEM contract
    function totalStaked() external view returns (uint256);

    /// @notice Get staking info for an address
    /// @param user The address to query
    /// @return amountStaked Amount currently staked
    /// @return coolDownEnd Timestamp when cooldown ends
    /// @return coolDownAmount Amount in cooldown
    function stakedInfos(address user)
        external
        view
        returns (uint256 amountStaked, uint256 coolDownEnd, uint256 coolDownAmount);

    /*//////////////////////////////////////////////////////////////
                           STAKING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Stakes DIEM tokens for use within the VeniceAI ecosystem
    /// @dev Transfers tokens from caller to DIEM contract (uses internal _update, no approval
    /// needed) @param amount The amount of tokens to stake
    function stake(uint256 amount) external;

    /// @notice Initiates a cooldown period for unstaking DIEM tokens
    /// @dev Starts the cooldown timer. Can add more to existing cooldown but resets timer.
    /// @param amount The amount of tokens to initiate unstake for
    function initiateUnstake(uint256 amount) external;

    /// @notice Unstakes DIEM tokens after the cooldown period has ended
    /// @dev Transfers cooldown amount back to caller. Reverts if cooldown not over.
    function unstake() external;
}
