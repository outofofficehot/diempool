import { useEffect, useMemo, useState } from 'react';
import {
  useAccount,
  useChainId,
  useReadContracts,
  useSwitchChain,
  useWaitForTransactionReceipt,
  useWriteContract,
} from 'wagmi';
import { base } from 'wagmi/chains';
import { formatUnits, parseUnits, type Address } from 'viem';
import { CSDIEM_V2_ABI, ERC20_ABI, SDIEM_V2_ABI } from '../abis/DIEMPool';
import { CONTRACTS } from '../config/contracts';
import './PoolPage.css';

type SupplyMode = 'liquid' | 'wrapped';
type ActionMode = 'supply' | 'withdraw';
type WithdrawMode = 'liquid' | 'wrapped';

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000' as Address;
const DAY_SECONDS = 86_400n;

function formatToken(value: bigint, decimals = 18, maxFraction = 4) {
  const numeric = Number(formatUnits(value, decimals));
  if (!Number.isFinite(numeric)) return '0';
  return numeric.toLocaleString(undefined, {
    maximumFractionDigits: numeric >= 100 ? 2 : maxFraction,
  });
}

function formatUsd(value: bigint, maxFraction = 2) {
  const numeric = Number(formatUnits(value, 6));
  if (!Number.isFinite(numeric)) return '$0.00';
  return numeric.toLocaleString(undefined, {
    style: 'currency',
    currency: 'USD',
    maximumFractionDigits: maxFraction,
  });
}

function formatApy(usdcPerDiemDay: bigint) {
  const annualPercent = Number(formatUnits(usdcPerDiemDay, 6)) * 365 * 100;
  if (!Number.isFinite(annualPercent) || annualPercent <= 0) return 'APY pending';
  return `${annualPercent.toLocaleString(undefined, {
    maximumFractionDigits: annualPercent >= 100 ? 0 : 2,
  })}%`;
}

function shortAddress(address: Address) {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

function parseDiemAmount(value: string) {
  try {
    return value.trim() ? parseUnits(value, 18) : 0n;
  } catch {
    return 0n;
  }
}

function secondsUntil(timestamp: bigint) {
  const now = BigInt(Math.floor(Date.now() / 1000));
  return timestamp > now ? timestamp - now : 0n;
}

function formatDuration(seconds: bigint) {
  const total = Number(seconds);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  if (hours <= 0) return `${minutes}m`;
  return `${hours}h ${minutes}m`;
}

export function PoolPage() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const { switchChain, isPending: isSwitching } = useSwitchChain();
  const [actionMode, setActionMode] = useState<ActionMode>('supply');
  const [mode, setMode] = useState<SupplyMode>('liquid');
  const [withdrawMode, setWithdrawMode] = useState<WithdrawMode>('liquid');
  const [depositAmount, setDepositAmount] = useState('');
  const [redeemAmount, setRedeemAmount] = useState('');
  const [withdrawAmount, setWithdrawAmount] = useState('');

  const account = address ?? ZERO_ADDRESS;
  const diem = CONTRACTS.DIEM_TOKEN as Address;
  const sdiem = CONTRACTS.SDIEM_V2 as Address;
  const csdiem = CONTRACTS.CSDIEM_V2 as Address;
  const spender = mode === 'wrapped' ? csdiem : sdiem;
  const parsedDeposit = parseDiemAmount(depositAmount);
  const parsedRedeem = parseDiemAmount(redeemAmount);
  const parsedWithdraw = parseDiemAmount(withdrawAmount);
  const isBase = chainId === base.id;

  const reads = useReadContracts({
    contracts: [
      { address: diem, abi: ERC20_ABI, functionName: 'balanceOf', args: [account] },
      { address: diem, abi: ERC20_ABI, functionName: 'allowance', args: [account, csdiem] },
      { address: diem, abi: ERC20_ABI, functionName: 'allowance', args: [account, sdiem] },
      { address: sdiem, abi: SDIEM_V2_ABI, functionName: 'balanceOf', args: [account] },
      { address: sdiem, abi: SDIEM_V2_ABI, functionName: 'earned', args: [account] },
      { address: sdiem, abi: SDIEM_V2_ABI, functionName: 'withdrawalRequests', args: [account] },
      { address: sdiem, abi: SDIEM_V2_ABI, functionName: 'canCompleteWithdraw', args: [account] },
      { address: sdiem, abi: SDIEM_V2_ABI, functionName: 'totalStaked' },
      { address: sdiem, abi: SDIEM_V2_ABI, functionName: 'rewardRate' },
      { address: sdiem, abi: SDIEM_V2_ABI, functionName: 'periodFinish' },
      { address: sdiem, abi: SDIEM_V2_ABI, functionName: 'paused' },
      { address: csdiem, abi: CSDIEM_V2_ABI, functionName: 'totalAssets' },
      { address: csdiem, abi: CSDIEM_V2_ABI, functionName: 'totalSupply' },
      { address: csdiem, abi: CSDIEM_V2_ABI, functionName: 'balanceOf', args: [account] },
      { address: csdiem, abi: CSDIEM_V2_ABI, functionName: 'convertToAssets', args: [parseUnits('1', 18)] },
      { address: csdiem, abi: CSDIEM_V2_ABI, functionName: 'previewRedeem', args: [parsedRedeem] },
      { address: csdiem, abi: CSDIEM_V2_ABI, functionName: 'maxRedeem', args: [account] },
      { address: csdiem, abi: CSDIEM_V2_ABI, functionName: 'paused' },
      { address: csdiem, abi: CSDIEM_V2_ABI, functionName: 'pendingHarvest' },
    ],
    query: { refetchInterval: 20_000 },
  });

  const results = reads.data as Array<{ result?: unknown; status?: string }> | undefined;
  const read = <T,>(index: number, fallback: T): T =>
    results?.[index]?.status === 'success' ? (results[index].result as T) : fallback;

  const diemBalance = read<bigint>(0, 0n);
  const csAllowance = read<bigint>(1, 0n);
  const sAllowance = read<bigint>(2, 0n);
  const sdiemBalance = read<bigint>(3, 0n);
  const pendingUsdc = read<bigint>(4, 0n);
  const withdrawalRequest = read<readonly [bigint, bigint]>(5, [0n, 0n]);
  const canCompleteWithdraw = read<boolean>(6, false);
  const totalStaked = read<bigint>(7, 0n);
  const rewardRate = read<bigint>(8, 0n);
  const periodFinish = read<bigint>(9, 0n);
  const sdiemPaused = read<boolean>(10, false);
  const csTotalAssets = read<bigint>(11, 0n);
  const csTotalSupply = read<bigint>(12, 0n);
  const csBalance = read<bigint>(13, 0n);
  const csSharePrice = read<bigint>(14, parseUnits('1', 18));
  const redeemPreview = read<bigint>(15, 0n);
  const maxRedeem = read<bigint>(16, 0n);
  const csdiemPaused = read<boolean>(17, false);
  const pendingHarvest = read<bigint>(18, 0n);
  const withdrawInputAmount = withdrawMode === 'wrapped' ? redeemAmount : withdrawAmount;
  const parsedWithdrawInput = withdrawMode === 'wrapped' ? parsedRedeem : parsedWithdraw;
  const withdrawBalance = withdrawMode === 'wrapped' ? maxRedeem : sdiemBalance;
  const withdrawToken = withdrawMode === 'wrapped' ? 'csDIEM' : 'sDIEM';
  const activeAllowance = mode === 'wrapped' ? csAllowance : sAllowance;
  const needsApproval = parsedDeposit > 0n && parsedDeposit > activeAllowance;

  const dailyReward = rewardRate * DAY_SECONDS;
  const usdcPerDiemDay = totalStaked > 0n ? (dailyReward * parseUnits('1', 18)) / totalStaked : 0n;
  const rewardStreamActive = dailyReward > 0n && totalStaked > 0n && secondsUntil(periodFinish) > 0n;
  const currentApyLabel = rewardStreamActive ? formatApy(usdcPerDiemDay) : 'APY pending';
  const sharePriceLabel =
    csTotalSupply > 0n ? `1 csDIEM = ${formatToken(csSharePrice)} sDIEM` : 'Vault opening';
  const dailyRewardLabel = dailyReward > 0n ? `${formatUsd(dailyReward)}/day` : 'Not streaming';
  const rewardPeriodLabel = periodFinish > 0n ? `${formatDuration(secondsUntil(periodFinish))} left` : 'Inactive';
  const withdrawalAmount = withdrawalRequest[0] ?? 0n;
  const withdrawalStart = withdrawalRequest[1] ?? 0n;
  const withdrawalReadyAt = withdrawalStart + DAY_SECONDS;
  const withdrawalWait = secondsUntil(withdrawalReadyAt);

  const connectedLabel = useMemo(() => {
    if (!isConnected || !address) return 'Wallet not connected';
    return `${shortAddress(address)} on ${isBase ? 'Base' : 'wrong network'}`;
  }, [address, isBase, isConnected]);

  const { writeContract, data: txHash, isPending: isWriting, error: writeError } = useWriteContract();
  const receipt = useWaitForTransactionReceipt({ hash: txHash });

  useEffect(() => {
    if (receipt.isSuccess) {
      reads.refetch();
    }
  }, [receipt.isSuccess, reads]);

  const isBusy = isWriting || receipt.isLoading || isSwitching;
  const modePaused = mode === 'wrapped' ? csdiemPaused : sdiemPaused;
  const disableReason = !isConnected
    ? 'Connect wallet'
    : !isBase
      ? 'Switch to Base'
      : modePaused
        ? 'Deposits paused'
        : parsedDeposit <= 0n
          ? 'Enter amount'
          : parsedDeposit > diemBalance
            ? 'Insufficient DIEM'
            : '';
  const withdrawDisableReason = !isConnected
    ? 'Connect wallet'
    : !isBase
      ? 'Switch to Base'
      : withdrawMode === 'liquid' && withdrawalAmount > 0n
        ? 'Withdrawal queued'
        : parsedWithdrawInput <= 0n
          ? 'Enter amount'
          : parsedWithdrawInput > withdrawBalance
            ? `Insufficient ${withdrawToken}`
            : '';

  const handlePrimaryAction = () => {
    if (!isConnected) return;
    if (!isBase) {
      switchChain({ chainId: base.id });
      return;
    }
    if (needsApproval) {
      writeContract({
        address: diem,
        abi: ERC20_ABI,
        functionName: 'approve',
        args: [spender, parsedDeposit],
      });
      return;
    }
    if (mode === 'wrapped') {
      writeContract({
        address: csdiem,
        abi: CSDIEM_V2_ABI,
        functionName: 'depositDIEM',
        args: [parsedDeposit, account],
      });
      return;
    }
    writeContract({
      address: sdiem,
      abi: SDIEM_V2_ABI,
      functionName: 'stake',
      args: [parsedDeposit],
    });
  };

  const handleClaim = () => {
    writeContract({ address: sdiem, abi: SDIEM_V2_ABI, functionName: 'claimReward' });
  };

  const handleRedeem = () => {
    writeContract({
      address: csdiem,
      abi: CSDIEM_V2_ABI,
      functionName: 'redeem',
      args: [parsedRedeem, account, account],
    });
  };

  const handleRequestWithdraw = () => {
    writeContract({
      address: sdiem,
      abi: SDIEM_V2_ABI,
      functionName: 'requestWithdraw',
      args: [parsedWithdraw],
    });
  };

  const handleWithdrawAction = () => {
    if (!isConnected) return;
    if (!isBase) {
      switchChain({ chainId: base.id });
      return;
    }
    if (withdrawMode === 'wrapped') {
      handleRedeem();
      return;
    }
    handleRequestWithdraw();
  };

  const handleCompleteWithdraw = () => {
    writeContract({ address: sdiem, abi: SDIEM_V2_ABI, functionName: 'completeWithdraw' });
  };

  const handleCancelWithdraw = () => {
    writeContract({ address: sdiem, abi: SDIEM_V2_ABI, functionName: 'cancelWithdraw' });
  };

  return (
    <div className="pool-page">
      <div className="pool-shell">
        <section className="pool-hero pool-hero-compact">
          <div>
            <div className="pool-kicker">DIEM Relay v2 vault</div>
            <h1 className="pool-title">Supply DIEM</h1>
            <p className="pool-subtitle">
              Connect a wallet to supply, track rewards, and withdraw. sDIEM is the liquid receipt;
              csDIEM is the wrapped auto-compounding position.
            </p>
          </div>
          <div className="pool-status-card">
            <span>Current APY</span>
            <strong>{currentApyLabel}</strong>
            <small>{sdiemPaused || csdiemPaused ? 'Vault paused' : 'Vault live'}</small>
          </div>
        </section>

        <section className="pool-app-grid">
          <div className="pool-panel pool-primary-panel">
            <div className="pool-action-tabs">
              <button
                className={actionMode === 'supply' ? 'pool-action-tab-active' : ''}
                onClick={() => setActionMode('supply')}
                type="button"
              >
                Supply
              </button>
              <button
                className={actionMode === 'withdraw' ? 'pool-action-tab-active' : ''}
                onClick={() => setActionMode('withdraw')}
                type="button"
              >
                Withdraw
              </button>
            </div>

            {actionMode === 'supply' ? (
              <div className="pool-form pool-form-main">
                <div className="pool-panel-header pool-inline-header">
                  <div>
                    <h2 className="pool-panel-title">Supply DIEM</h2>
                    <p className="pool-panel-copy">Most users should receive sDIEM first. Wrap later if they want compounding.</p>
                  </div>
                </div>

                <div className="pool-token-tabs">
                  <button
                    className={mode === 'liquid' ? 'pool-token-tab-active' : ''}
                    onClick={() => setMode('liquid')}
                    type="button"
                  >
                    <strong>sDIEM</strong>
                    <span>Liquid staking + claimable USDC</span>
                  </button>
                  <button
                    className={mode === 'wrapped' ? 'pool-token-tab-active' : ''}
                    onClick={() => setMode('wrapped')}
                    type="button"
                  >
                    <strong>csDIEM</strong>
                    <span>Wrapped sDIEM + auto-compounding</span>
                  </button>
                </div>

                {!isConnected ? (
                  <div className="pool-connect">Connect a wallet to supply DIEM.</div>
                ) : (
                  <>
                    <div className="pool-input-row pool-input-row-large">
                      <div className="pool-input-meta">
                        <span>Supply amount</span>
                        <span>Wallet: {formatToken(diemBalance)} DIEM</span>
                      </div>
                      <div className="pool-input-line">
                        <input
                          className="pool-input"
                          inputMode="decimal"
                          onChange={(event) => setDepositAmount(event.target.value)}
                          placeholder="0.0"
                          value={depositAmount}
                        />
                        <button
                          className="pool-small-button"
                          onClick={() => setDepositAmount(formatUnits(diemBalance, 18))}
                          type="button"
                        >
                          MAX
                        </button>
                        <span className="pool-token">DIEM</span>
                      </div>
                    </div>

                    <div className="pool-preview pool-preview-quiet">
                      <div className="pool-preview-row">
                        <span>You receive</span>
                        <strong>{mode === 'liquid' ? 'sDIEM' : 'csDIEM'}</strong>
                      </div>
                      <div className="pool-preview-row">
                        <span>Rewards</span>
                        <strong>{mode === 'liquid' ? 'Claim USDC manually' : 'Auto-compound into share price'}</strong>
                      </div>
                      <div className="pool-preview-row">
                        <span>Current rate</span>
                        <strong>{dailyRewardLabel}</strong>
                      </div>
                    </div>

                    <button
                      className="pool-action"
                      disabled={isBusy || (!!disableReason && disableReason !== 'Switch to Base') || (isBase && needsApproval && parsedDeposit <= 0n)}
                      onClick={handlePrimaryAction}
                      type="button"
                    >
                      {!isBase && isConnected
                        ? 'Switch to Base'
                        : needsApproval
                          ? 'Approve DIEM'
                          : disableReason || (mode === 'liquid' ? 'Supply DIEM' : 'Supply and wrap')}
                    </button>
                  </>
                )}
              </div>
            ) : (
              <div className="pool-form pool-form-main">
                <div className="pool-panel-header pool-inline-header">
                  <div>
                    <h2 className="pool-panel-title">Withdraw DIEM</h2>
                    <p className="pool-panel-copy">Choose the token you hold. sDIEM requests DIEM withdrawal; csDIEM unwraps to sDIEM first.</p>
                  </div>
                </div>

                <div className="pool-token-tabs">
                  <button
                    className={withdrawMode === 'liquid' ? 'pool-token-tab-active' : ''}
                    onClick={() => setWithdrawMode('liquid')}
                    type="button"
                  >
                    <strong>sDIEM</strong>
                    <span>Request DIEM withdrawal</span>
                  </button>
                  <button
                    className={withdrawMode === 'wrapped' ? 'pool-token-tab-active' : ''}
                    onClick={() => setWithdrawMode('wrapped')}
                    type="button"
                  >
                    <strong>csDIEM</strong>
                    <span>Unwrap to sDIEM first</span>
                  </button>
                </div>

                {!isConnected ? (
                  <div className="pool-connect">Connect a wallet to withdraw DIEM.</div>
                ) : (
                  <>
                    <div className="pool-input-row pool-input-row-large">
                      <div className="pool-input-meta">
                        <span>Withdraw amount</span>
                        <span>Balance: {formatToken(withdrawBalance)} {withdrawToken}</span>
                      </div>
                      <div className="pool-input-line">
                        <input
                          className="pool-input"
                          inputMode="decimal"
                          onChange={(event) =>
                            withdrawMode === 'wrapped'
                              ? setRedeemAmount(event.target.value)
                              : setWithdrawAmount(event.target.value)
                          }
                          placeholder="0.0"
                          value={withdrawInputAmount}
                        />
                        <button
                          className="pool-small-button"
                          onClick={() =>
                            withdrawMode === 'wrapped'
                              ? setRedeemAmount(formatUnits(maxRedeem, 18))
                              : setWithdrawAmount(formatUnits(sdiemBalance, 18))
                          }
                          type="button"
                        >
                          MAX
                        </button>
                        <span className="pool-token">{withdrawToken}</span>
                      </div>
                    </div>

                    <div className="pool-preview pool-preview-quiet">
                      <div className="pool-preview-row">
                        <span>You receive</span>
                        <strong>{withdrawMode === 'wrapped' ? `${formatToken(redeemPreview)} sDIEM` : 'DIEM after cooldown'}</strong>
                      </div>
                      <div className="pool-preview-row">
                        <span>Next step</span>
                        <strong>{withdrawMode === 'wrapped' ? 'Then withdraw sDIEM' : 'Complete after 24h'}</strong>
                      </div>
                      {withdrawalAmount > 0n && (
                        <div className="pool-preview-row">
                          <span>Queued</span>
                          <strong>
                            {formatToken(withdrawalAmount)} DIEM -{' '}
                            {canCompleteWithdraw ? 'ready' : `${formatDuration(withdrawalWait)} left`}
                          </strong>
                        </div>
                      )}
                    </div>

                    <button
                      className="pool-action"
                      disabled={isBusy || (!!withdrawDisableReason && withdrawDisableReason !== 'Switch to Base')}
                      onClick={handleWithdrawAction}
                      type="button"
                    >
                      {!isBase && isConnected
                        ? 'Switch to Base'
                        : withdrawDisableReason ||
                          (withdrawMode === 'wrapped' ? 'Unwrap to sDIEM' : 'Request withdrawal')}
                    </button>

                    {withdrawalAmount > 0n && (
                      <button
                        className="pool-secondary-action pool-secondary-action-full"
                        disabled={isBusy || !isConnected}
                        onClick={canCompleteWithdraw ? handleCompleteWithdraw : handleCancelWithdraw}
                        type="button"
                      >
                        {canCompleteWithdraw ? 'Complete withdrawal' : 'Cancel queued withdrawal'}
                      </button>
                    )}
                  </>
                )}
              </div>
            )}

            {txHash && (
              <div className="pool-tx pool-tx-main">
                {receipt.isLoading
                  ? 'Transaction submitted. Waiting for confirmation...'
                  : receipt.isSuccess
                    ? 'Transaction confirmed. Balances refreshed.'
                    : `Transaction: ${shortAddress(txHash as Address)}`}
              </div>
            )}
            {writeError && <div className="pool-tx pool-tx-main">Wallet error: {writeError.message}</div>}
          </div>

          <aside className="pool-panel pool-position-panel">
            <div className="pool-panel-header">
              <div>
                <h2 className="pool-panel-title">Position</h2>
                <p className="pool-panel-copy">{connectedLabel}</p>
              </div>
            </div>

            {!isConnected ? (
              <div className="pool-empty-state pool-empty-state-large">
                Connect a wallet to see supplied DIEM, claimable rewards, and withdrawal status.
              </div>
            ) : (
              <>
                <div className="pool-balance-grid">
                  <div>
                    <span>DIEM</span>
                    <strong>{formatToken(diemBalance)}</strong>
                  </div>
                  <div>
                    <span>sDIEM</span>
                    <strong>{formatToken(sdiemBalance)}</strong>
                  </div>
                  <div>
                    <span>csDIEM</span>
                    <strong>{formatToken(csBalance)}</strong>
                  </div>
                  <div>
                    <span>csDIEM vault</span>
                    <strong>{formatToken(csTotalAssets)}</strong>
                  </div>
                  <div>
                    <span>USDC rewards</span>
                    <strong>{formatUsd(pendingUsdc)}</strong>
                  </div>
                  <div>
                    <span>Pending harvest</span>
                    <strong>{formatUsd(pendingHarvest)}</strong>
                  </div>
                </div>

                <div className="pool-rewards-card">
                  <div>
                    <span>Claimable USDC</span>
                    <strong>{formatUsd(pendingUsdc)}</strong>
                  </div>
                  <button
                    className="pool-secondary-action"
                    disabled={isBusy || pendingUsdc <= 0n}
                    onClick={handleClaim}
                    type="button"
                  >
                    Claim
                  </button>
                </div>
              </>
            )}
          </aside>
        </section>

        <section className="pool-stats pool-stats-tight">
          <div className="pool-stat">
            <span>Total supplied</span>
            <strong>{formatToken(totalStaked)} DIEM</strong>
          </div>
          <div className="pool-stat">
            <span>Rewards</span>
            <strong>{dailyRewardLabel}</strong>
          </div>
          <div className="pool-stat">
            <span>Per DIEM / day</span>
            <strong>{formatUsd(usdcPerDiemDay, 5)}</strong>
          </div>
          <div className="pool-stat">
            <span>csDIEM</span>
            <strong>{sharePriceLabel}</strong>
          </div>
          <div className="pool-stat">
            <span>Reward period</span>
            <strong>{rewardPeriodLabel}</strong>
          </div>
        </section>

        <section className="pool-mechanics-strip">
          <div>
            <strong>sDIEM</strong>
            <span>Liquid staking receipt. Accrues claimable USDC rewards.</span>
          </div>
          <div>
            <strong>csDIEM</strong>
            <span>Wrapped sDIEM. Rewards compound into the exchange rate.</span>
          </div>
          <div>
            <strong>Withdrawals</strong>
            <span>sDIEM withdrawal requests complete after the 24h cooldown.</span>
          </div>
        </section>
      </div>
    </div>
  );
}
