// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IDIEM } from "../../src/interfaces/IDIEM.sol";

/**
 * @title MockDIEM
 * @notice Mock DIEM token for testing that replicates the real DIEM staking behavior
 */
contract MockDIEM is ERC20, IDIEM {
    uint256 public override cooldownDuration = 1 days;
    uint256 public override totalStaked;

    mapping(address => StakedInfo) private _stakedInfos;

    constructor() ERC20("Diem", "DIEM") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setCooldownDuration(uint256 _duration) external {
        cooldownDuration = _duration;
        emit CooldownDurationUpdated(_duration);
    }

    function stakedInfos(address user)
        external
        view
        override
        returns (uint256 amountStaked, uint256 coolDownEnd, uint256 coolDownAmount)
    {
        StakedInfo storage info = _stakedInfos[user];
        return (info.amountStaked, info.coolDownEnd, info.coolDownAmount);
    }

    function stake(uint256 amount) external override {
        require(amount > 0, "STAKE_ZERO");
        require(balanceOf(msg.sender) >= amount, "INSUFFICIENT_BALANCE");

        totalStaked += amount;
        _stakedInfos[msg.sender].amountStaked += amount;

        // Transfer to this contract (mimics real DIEM behavior)
        _transfer(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    function initiateUnstake(uint256 amount) external override {
        require(amount > 0, "UNSTAKE_ZERO");
        require(_stakedInfos[msg.sender].amountStaked >= amount, "INSUFFICIENT_STAKED");

        StakedInfo storage info = _stakedInfos[msg.sender];
        info.coolDownEnd = block.timestamp + cooldownDuration;
        info.coolDownAmount += amount;
        info.amountStaked -= amount;

        emit UnstakeInitiated(msg.sender, amount);
    }

    function unstake() external override {
        StakedInfo storage info = _stakedInfos[msg.sender];
        require(info.coolDownAmount > 0, "NO_COOLDOWN");
        require(block.timestamp >= info.coolDownEnd, "COOLDOWN_NOT_OVER");

        uint256 amount = info.coolDownAmount;
        totalStaked -= amount;
        info.coolDownAmount = 0;
        info.coolDownEnd = 0;

        // Transfer back to user
        _transfer(address(this), msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }
}
