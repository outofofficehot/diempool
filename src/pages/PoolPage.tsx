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

type EarnMode = 'compound' | 'usdc';

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
  const [mode, setMode] = useState<EarnMode>('compound');
  const [depositAmount, setDepositAmount] = useState('');
  const [redeemAmount, setRedeemAmount] = useState('');
  const [withdrawAmount, setWithdrawAmount] = useState('');

  const account = address ?? ZERO_ADDRESS;
  const diem = CONTRACTS.DIEM_TOKEN as Address;
  const sdiem = CONTRACTS.SDIEM_V2 as Address;
  const csdiem = CONTRACTS.CSDIEM_V2 as Address;
  const spender = mode === 'compound' ? csdiem : sdiem;
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
  const activeAllowance = mode === 'compound' ? csAllowance : sAllowance;
  const needsApproval = parsedDeposit > 0n && parsedDeposit > activeAllowance;

  const dailyReward = rewardRate * DAY_SECONDS;
  const usdcPerDiemDay = totalStaked > 0n ? (dailyReward * parseUnits('1', 18)) / totalStaked : 0n;
  const sharePriceLabel =
    csTotalSupply > 0n ? `1 csDIEM = ${formatToken(csSharePrice)} sDIEM` : 'Vault opening';
  const dailyRewardLabel = dailyReward > 0n ? `${formatUsd(dailyReward)}/day` : 'Not streaming';
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
  const modePaused = mode === 'compound' ? csdiemPaused : sdiemPaused;
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
    if (mode === 'compound') {
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

  const handleCompleteWithdraw = () => {
    writeContract({ address: sdiem, abi: SDIEM_V2_ABI, functionName: 'completeWithdraw' });
  };

  const handleCancelWithdraw = () => {
    writeContract({ address: sdiem, abi: SDIEM_V2_ABI, functionName: 'cancelWithdraw' });
  };

  return (
    <div className="pool-page">
      <div className="pool-shell">
        <section className="pool-hero">
          <div className="pool-hero-copy">
            <div className="pool-kicker">DIEM Relay v2 vault</div>
            <h1 className="pool-title">Put DIEM to work.</h1>
            <p className="pool-subtitle">
              Deposit into the v2 vault, then choose automatic compounding or direct USDC cash yield.
              The default path is built for passive DIEM exposure.
            </p>
            <div className="pool-hero-points">
              <span>Base mainnet</span>
              <span>24h withdrawal cooldown</span>
              <span>v2 contracts</span>
            </div>
          </div>

          <div className="pool-panel pool-primary-panel">
            <div className="pool-panel-header pool-primary-header">
              <div>
                <h2 className="pool-panel-title">Deposit</h2>
                <p className="pool-panel-copy">{connectedLabel}</p>
              </div>
              <span className={`pool-live-dot ${sdiemPaused || csdiemPaused ? 'pool-live-dot-paused' : ''}`}>
                {sdiemPaused || csdiemPaused ? 'Paused' : 'Live'}
              </span>
            </div>

            <div className="pool-tabs">
              <button
                className={`pool-tab ${mode === 'compound' ? 'pool-tab-active' : ''}`}
                onClick={() => setMode('compound')}
                type="button"
              >
                <div className="pool-tab-title">
                  Auto-compound <span className="pool-badge">Default</span>
                </div>
                <div className="pool-tab-copy">Receive csDIEM and let rewards keep working.</div>
              </button>
              <button
                className={`pool-tab ${mode === 'usdc' ? 'pool-tab-active' : ''}`}
                onClick={() => setMode('usdc')}
                type="button"
              >
                <div className="pool-tab-title">Cash yield</div>
                <div className="pool-tab-copy">Receive sDIEM and claim USDC manually.</div>
              </button>
            </div>

            <div className="pool-form">
              {!isConnected ? (
                <div className="pool-connect">
                  Connect a wallet to deposit DIEM, claim USDC, or manage withdrawals.
                </div>
              ) : (
                <>
                  <div className="pool-input-row">
                    <div className="pool-input-meta">
                      <span>Deposit amount</span>
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

                  <div className="pool-preview">
                    <div className="pool-preview-row">
                      <span>You receive</span>
                      <strong>{mode === 'compound' ? 'csDIEM vault shares' : 'sDIEM staking balance'}</strong>
                    </div>
                    <div className="pool-preview-row">
                      <span>Reward handling</span>
                      <strong>{mode === 'compound' ? 'Auto-compounded' : 'Claimable USDC'}</strong>
                    </div>
                    <div className="pool-preview-row">
                      <span>Vault rate</span>
                      <strong>{dailyRewardLabel}</strong>
                    </div>
                    <div className="pool-preview-row">
                      <span>Reward period</span>
                      <strong>{periodFinish > 0n ? `${formatDuration(secondsUntil(periodFinish))} left` : 'Inactive'}</strong>
                    </div>
                    <div className="pool-preview-row">
                      <span>USDC per DIEM per day</span>
                      <strong>{formatUsd(usdcPerDiemDay, 5)}</strong>
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
                        : disableReason || (mode === 'compound' ? 'Deposit and compound' : 'Deposit for USDC yield')}
                  </button>
                  <p className="pool-note">
                    {mode === 'compound'
                      ? 'csDIEM compounds rewards through the vault. Redeem to sDIEM before exiting to DIEM.'
                      : 'sDIEM earns claimable USDC. Withdrawing DIEM uses the 24h cooldown.'}
                  </p>
                </>
              )}

              {txHash && (
                <div className="pool-tx">
                  {receipt.isLoading
                    ? 'Transaction submitted. Waiting for confirmation...'
                    : receipt.isSuccess
                      ? 'Transaction confirmed. Balances refreshed.'
                      : `Transaction: ${shortAddress(txHash as Address)}`}
                </div>
              )}
              {writeError && <div className="pool-tx">Wallet error: {writeError.message}</div>}
            </div>
          </div>
        </section>

        <section className="pool-stats">
          <div className="pool-stat">
            <span>Total staked</span>
            <strong>{formatToken(totalStaked)} DIEM</strong>
          </div>
          <div className="pool-stat">
            <span>Auto-compound vault</span>
            <strong>{formatToken(csTotalAssets)} sDIEM</strong>
          </div>
          <div className="pool-stat">
            <span>Current USDC rewards</span>
            <strong>{dailyRewardLabel}</strong>
          </div>
          <div className="pool-stat">
            <span>Share price</span>
            <strong>{sharePriceLabel}</strong>
          </div>
        </section>

        <section className="pool-grid">
          <div className="pool-panel">
            <div className="pool-panel-header">
              <h2 className="pool-panel-title">Mechanics</h2>
              <p className="pool-panel-copy">
                The two vault paths share the same underlying DIEM Relay v2 contracts.
              </p>
            </div>
            <div className="pool-risk-list pool-risk-list-compact">
              <div className="pool-risk-item">
                <strong>Auto-compound</strong>
                <span>DIEM deposits mint csDIEM. Rewards are harvested back into vault exposure.</span>
              </div>
              <div className="pool-risk-item">
                <strong>Cash yield</strong>
                <span>DIEM deposits mint sDIEM. USDC rewards accrue for manual claiming.</span>
              </div>
              <div className="pool-risk-item">
                <strong>Exit path</strong>
                <span>csDIEM redeems to sDIEM. sDIEM withdrawal requests complete after 24h.</span>
              </div>
              <div className="pool-risk-item">
                <strong>Contract state</strong>
                <span>sDIEM {sdiemPaused ? 'paused' : 'live'}; csDIEM {csdiemPaused ? 'paused' : 'live'}.</span>
              </div>
            </div>
          </div>

          <div className="pool-stack">
            <div className="pool-panel pool-position">
              <h3 className="pool-section-title">Your position</h3>
              {!isConnected ? (
                <div className="pool-empty-state">
                  Connect a wallet to see DIEM balance, csDIEM shares, claimable USDC, and withdrawal state.
                </div>
              ) : (
                <div className="pool-position-list">
                  <div className="pool-position-row">
                    <span>Wallet DIEM</span>
                    <strong>{formatToken(diemBalance)} DIEM</strong>
                  </div>
                  <div className="pool-position-row">
                    <span>csDIEM</span>
                    <strong>{formatToken(csBalance)} csDIEM</strong>
                  </div>
                  <div className="pool-position-row">
                    <span>sDIEM</span>
                    <strong>{formatToken(sdiemBalance)} sDIEM</strong>
                  </div>
                  <div className="pool-position-row">
                    <span>Claimable USDC</span>
                    <strong>{formatUsd(pendingUsdc)}</strong>
                  </div>
                  <div className="pool-position-row">
                    <span>Pending harvest</span>
                    <strong>{formatUsd(pendingHarvest)}</strong>
                  </div>
                </div>
              )}

              <div className="pool-manage">
                <h3 className="pool-section-title">Manage</h3>
                <div className="pool-actions-grid">
                  <button
                    className="pool-secondary-action"
                    disabled={isBusy || pendingUsdc <= 0n || !isConnected}
                    onClick={handleClaim}
                    type="button"
                  >
                    Claim USDC
                  </button>
                  {withdrawalAmount > 0n ? (
                    <button
                      className="pool-secondary-action"
                      disabled={isBusy || !isConnected}
                      onClick={canCompleteWithdraw ? handleCompleteWithdraw : handleCancelWithdraw}
                      type="button"
                    >
                      {canCompleteWithdraw ? 'Complete withdraw' : 'Cancel withdraw'}
                    </button>
                  ) : (
                    <button className="pool-secondary-action" disabled type="button">
                      No withdrawal queued
                    </button>
                  )}
                </div>

                {withdrawalAmount > 0n && (
                  <p className="pool-note">
                    {formatToken(withdrawalAmount)} DIEM queued.{' '}
                    {canCompleteWithdraw ? 'Ready to complete.' : `${formatDuration(withdrawalWait)} remaining.`}
                  </p>
                )}
              </div>

              <div className="pool-manage">
                <h3 className="pool-section-title">Exit path</h3>
                <input
                  className="pool-mini-input"
                  inputMode="decimal"
                  onChange={(event) => setRedeemAmount(event.target.value)}
                  placeholder="csDIEM amount to redeem to sDIEM"
                  value={redeemAmount}
                />
                <div className="pool-actions-grid">
                  <button
                    className="pool-secondary-action"
                    disabled={!isConnected}
                    onClick={() => setRedeemAmount(formatUnits(maxRedeem, 18))}
                    type="button"
                  >
                    Max csDIEM
                  </button>
                  <button
                    className="pool-secondary-action"
                    disabled={isBusy || !isConnected || parsedRedeem <= 0n || parsedRedeem > maxRedeem}
                    onClick={handleRedeem}
                    type="button"
                  >
                    Redeem to sDIEM
                  </button>
                </div>
                <p className="pool-note">
                  Preview: {formatToken(redeemPreview)} sDIEM returned. Then request sDIEM withdrawal to DIEM.
                </p>

                <input
                  className="pool-mini-input"
                  inputMode="decimal"
                  onChange={(event) => setWithdrawAmount(event.target.value)}
                  placeholder="sDIEM amount to withdraw to DIEM"
                  style={{ marginTop: 12 }}
                  value={withdrawAmount}
                />
                <div className="pool-actions-grid">
                  <button
                    className="pool-secondary-action"
                    disabled={!isConnected}
                    onClick={() => setWithdrawAmount(formatUnits(sdiemBalance, 18))}
                    type="button"
                  >
                    Max sDIEM
                  </button>
                  <button
                    className="pool-secondary-action"
                    disabled={isBusy || !isConnected || parsedWithdraw <= 0n || parsedWithdraw > sdiemBalance || withdrawalAmount > 0n}
                    onClick={handleRequestWithdraw}
                    type="button"
                  >
                    Request withdrawal
                  </button>
                </div>
              </div>
            </div>
          </div>
        </section>
      </div>
    </div>
  );
}
