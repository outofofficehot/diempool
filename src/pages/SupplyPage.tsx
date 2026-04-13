import React, { useState } from 'react';
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseUnits } from 'viem';
import { brand } from '../brand';
import { PoolStats } from '../components/PoolStats';
import { useStakerInfo, useTokenBalances, formatDIEM, formatUSDC } from '../hooks/usePoolData';
import { DIEM_POOL_ABI, ERC20_ABI } from '../abis/DIEMPool';
import { CONTRACTS } from '../config/contracts';

export function SupplyPage() {
  const { address, isConnected } = useAccount();
  const [depositAmount, setDepositAmount] = useState('');
  const [withdrawAmount, setWithdrawAmount] = useState('');
  const [activeTab, setActiveTab] = useState<'deposit' | 'withdraw'>('deposit');

  const stakerInfo = useStakerInfo(address as `0x${string}`);
  const balances = useTokenBalances(address as `0x${string}`);

  const { writeContract, data: txHash, isPending } = useWriteContract();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash: txHash });

  const poolAddress = CONTRACTS.DIEM_POOL as `0x${string}`;
  const diemAddress = CONTRACTS.DIEM_TOKEN as `0x${string}`;

  const handleApprove = () => {
    const amount = parseUnits(depositAmount || '0', 18);
    writeContract({
      address: diemAddress,
      abi: ERC20_ABI,
      functionName: 'approve',
      args: [poolAddress, amount],
    });
  };

  const handleDeposit = () => {
    const amount = parseUnits(depositAmount || '0', 18);
    writeContract({
      address: poolAddress,
      abi: DIEM_POOL_ABI,
      functionName: 'deposit',
      args: [amount],
    });
  };

  const handleRequestWithdraw = () => {
    const amount = parseUnits(withdrawAmount || '0', 18);
    writeContract({
      address: poolAddress,
      abi: DIEM_POOL_ABI,
      functionName: 'requestWithdraw',
      args: [amount],
    });
  };

  const handleCompleteWithdraw = () => {
    writeContract({
      address: poolAddress,
      abi: DIEM_POOL_ABI,
      functionName: 'completeWithdraw',
      args: [],
    });
  };

  const handleCancelWithdraw = () => {
    writeContract({
      address: poolAddress,
      abi: DIEM_POOL_ABI,
      functionName: 'cancelWithdraw',
      args: [],
    });
  };

  const handleClaimYield = () => {
    writeContract({
      address: poolAddress,
      abi: DIEM_POOL_ABI,
      functionName: 'claimYield',
      args: [],
    });
  };

  const needsApproval = depositAmount && 
    parseUnits(depositAmount, 18) > balances.diemAllowance;

  if (!isConnected) {
    return (
      <div style={styles.container}>
        <PoolStats />
        <div style={styles.card}>
          <h2 style={styles.cardTitle}>Supply DIEM</h2>
          <p style={styles.cardSubtitle}>Connect your wallet to start earning yield on your DIEM</p>
        </div>
      </div>
    );
  }

  return (
    <div style={styles.container}>
      <PoolStats />

      {/* Your Position */}
      <div style={styles.card}>
        <h3 style={styles.sectionTitle}>Your Position</h3>
        <div style={styles.positionGrid}>
          <div style={styles.positionItem}>
            <span style={styles.positionLabel}>Staked DIEM</span>
            <span style={styles.positionValue}>
              {Number(formatDIEM(stakerInfo.stakedDIEM)).toLocaleString()}
            </span>
          </div>
          <div style={styles.positionItem}>
            <span style={styles.positionLabel}>Pool Share</span>
            <span style={styles.positionValue}>
              {(Number(stakerInfo.sharePercentageBps) / 100).toFixed(2)}%
            </span>
          </div>
          <div style={styles.positionItem}>
            <span style={styles.positionLabel}>Pending Yield</span>
            <span style={styles.positionValueHighlight}>
              ${Number(formatUSDC(stakerInfo.pendingYield)).toFixed(2)}
            </span>
          </div>
          <div style={styles.positionItem}>
            <span style={styles.positionLabel}>Wallet Balance</span>
            <span style={styles.positionValue}>
              {Number(formatDIEM(balances.diemBalance)).toLocaleString()} DIEM
            </span>
          </div>
        </div>

        {stakerInfo.pendingYield > 0n && (
          <button 
            onClick={handleClaimYield} 
            style={styles.claimButton}
            disabled={isPending || isConfirming}
          >
            {isPending || isConfirming ? 'Processing...' : `Claim $${Number(formatUSDC(stakerInfo.pendingYield)).toFixed(2)} USDC`}
          </button>
        )}
      </div>

      {/* Withdrawal in Progress */}
      {stakerInfo.cooldownDIEM > 0n && (
        <div style={styles.card}>
          <h3 style={styles.sectionTitle}>Pending Withdrawal</h3>
          <div style={styles.withdrawalInfo}>
            <span>Amount: {Number(formatDIEM(stakerInfo.cooldownDIEM)).toLocaleString()} DIEM</span>
            {stakerInfo.canCompleteWithdrawal ? (
              <span style={styles.readyText}>Ready to complete!</span>
            ) : (
              <span>Cooldown ends: {new Date(Number(stakerInfo.cooldownEnd) * 1000).toLocaleString()}</span>
            )}
          </div>
          <div style={styles.withdrawalActions}>
            {stakerInfo.canCompleteWithdrawal ? (
              <button onClick={handleCompleteWithdraw} style={styles.primaryButton} disabled={isPending}>
                Complete Withdrawal
              </button>
            ) : (
              <button onClick={handleCancelWithdraw} style={styles.secondaryButton} disabled={isPending}>
                Cancel Withdrawal
              </button>
            )}
          </div>
        </div>
      )}

      {/* Deposit / Withdraw Tabs */}
      <div style={styles.card}>
        <div style={styles.tabs}>
          <button 
            onClick={() => setActiveTab('deposit')}
            style={{
              ...styles.tab,
              ...(activeTab === 'deposit' ? styles.tabActive : {}),
            }}
          >
            Deposit
          </button>
          <button 
            onClick={() => setActiveTab('withdraw')}
            style={{
              ...styles.tab,
              ...(activeTab === 'withdraw' ? styles.tabActive : {}),
            }}
          >
            Withdraw
          </button>
        </div>

        {activeTab === 'deposit' ? (
          <div style={styles.formSection}>
            <label style={styles.inputLabel}>Amount to Deposit</label>
            <div style={styles.inputWrapper}>
              <input
                type="number"
                value={depositAmount}
                onChange={(e) => setDepositAmount(e.target.value)}
                placeholder="0.0"
                style={styles.input}
              />
              <button 
                onClick={() => setDepositAmount(formatDIEM(balances.diemBalance))}
                style={styles.maxButton}
              >
                MAX
              </button>
              <span style={styles.inputSuffix}>DIEM</span>
            </div>
            
            {needsApproval ? (
              <button onClick={handleApprove} style={styles.primaryButton} disabled={isPending}>
                {isPending ? 'Approving...' : 'Approve DIEM'}
              </button>
            ) : (
              <button 
                onClick={handleDeposit} 
                style={styles.primaryButton} 
                disabled={isPending || !depositAmount}
              >
                {isPending ? 'Depositing...' : 'Deposit DIEM'}
              </button>
            )}
          </div>
        ) : (
          <div style={styles.formSection}>
            <label style={styles.inputLabel}>Amount to Withdraw</label>
            <div style={styles.inputWrapper}>
              <input
                type="number"
                value={withdrawAmount}
                onChange={(e) => setWithdrawAmount(e.target.value)}
                placeholder="0.0"
                style={styles.input}
              />
              <button 
                onClick={() => setWithdrawAmount(formatDIEM(stakerInfo.stakedDIEM))}
                style={styles.maxButton}
              >
                MAX
              </button>
              <span style={styles.inputSuffix}>DIEM</span>
            </div>
            <p style={styles.note}>
              Note: Withdrawals have a 1-day cooldown period due to DIEM staking mechanics.
            </p>
            <button 
              onClick={handleRequestWithdraw} 
              style={styles.primaryButton}
              disabled={isPending || !withdrawAmount || stakerInfo.cooldownDIEM > 0n}
            >
              {isPending ? 'Processing...' : 'Request Withdrawal'}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}

const styles: { [key: string]: React.CSSProperties } = {
  container: {
    maxWidth: '600px',
    margin: '0 auto',
    padding: '24px',
    display: 'flex',
    flexDirection: 'column',
    gap: '24px',
  },
  card: {
    background: brand.colors.surface,
    borderRadius: '16px',
    border: `1px solid ${brand.colors.border}`,
    padding: '24px',
  },
  cardTitle: {
    fontFamily: brand.fonts.display,
    fontSize: '24px',
    fontWeight: 600,
    color: brand.colors.text,
    marginBottom: '8px',
  },
  cardSubtitle: {
    color: brand.colors.textSecondary,
    fontSize: '14px',
  },
  sectionTitle: {
    fontFamily: brand.fonts.display,
    fontSize: '18px',
    fontWeight: 600,
    color: brand.colors.text,
    marginBottom: '16px',
  },
  positionGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(2, 1fr)',
    gap: '16px',
    marginBottom: '16px',
  },
  positionItem: {
    display: 'flex',
    flexDirection: 'column',
    gap: '4px',
  },
  positionLabel: {
    fontSize: '12px',
    color: brand.colors.textMuted,
    textTransform: 'uppercase',
  },
  positionValue: {
    fontSize: '18px',
    fontWeight: 600,
    color: brand.colors.text,
    fontFamily: brand.fonts.mono,
  },
  positionValueHighlight: {
    fontSize: '18px',
    fontWeight: 600,
    color: brand.colors.accent,
    fontFamily: brand.fonts.mono,
  },
  claimButton: {
    width: '100%',
    padding: '12px',
    background: brand.colors.accent,
    color: brand.colors.background,
    border: 'none',
    borderRadius: '8px',
    fontSize: '14px',
    fontWeight: 600,
    cursor: 'pointer',
  },
  withdrawalInfo: {
    display: 'flex',
    flexDirection: 'column',
    gap: '8px',
    marginBottom: '16px',
    color: brand.colors.textSecondary,
  },
  readyText: {
    color: brand.colors.accent,
    fontWeight: 600,
  },
  withdrawalActions: {
    display: 'flex',
    gap: '12px',
  },
  tabs: {
    display: 'flex',
    gap: '8px',
    marginBottom: '24px',
  },
  tab: {
    flex: 1,
    padding: '12px',
    background: 'transparent',
    border: `1px solid ${brand.colors.border}`,
    borderRadius: '8px',
    color: brand.colors.textSecondary,
    fontSize: '14px',
    fontWeight: 500,
    cursor: 'pointer',
  },
  tabActive: {
    background: brand.colors.primaryMuted,
    borderColor: brand.colors.primary,
    color: brand.colors.primary,
  },
  formSection: {
    display: 'flex',
    flexDirection: 'column',
    gap: '16px',
  },
  inputLabel: {
    fontSize: '14px',
    color: brand.colors.textSecondary,
  },
  inputWrapper: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    background: brand.colors.background,
    border: `1px solid ${brand.colors.border}`,
    borderRadius: '8px',
    padding: '4px 12px',
  },
  input: {
    flex: 1,
    background: 'transparent',
    border: 'none',
    outline: 'none',
    color: brand.colors.text,
    fontSize: '18px',
    fontFamily: brand.fonts.mono,
    padding: '8px 0',
  },
  maxButton: {
    padding: '4px 8px',
    background: brand.colors.primaryMuted,
    border: 'none',
    borderRadius: '4px',
    color: brand.colors.primary,
    fontSize: '12px',
    fontWeight: 600,
    cursor: 'pointer',
  },
  inputSuffix: {
    color: brand.colors.textMuted,
    fontSize: '14px',
  },
  primaryButton: {
    width: '100%',
    padding: '14px',
    background: brand.colors.primary,
    color: brand.colors.background,
    border: 'none',
    borderRadius: '8px',
    fontSize: '16px',
    fontWeight: 600,
    cursor: 'pointer',
  },
  secondaryButton: {
    flex: 1,
    padding: '12px',
    background: 'transparent',
    border: `1px solid ${brand.colors.border}`,
    borderRadius: '8px',
    color: brand.colors.textSecondary,
    fontSize: '14px',
    fontWeight: 500,
    cursor: 'pointer',
  },
  note: {
    fontSize: '13px',
    color: brand.colors.textMuted,
    fontStyle: 'italic',
  },
};
