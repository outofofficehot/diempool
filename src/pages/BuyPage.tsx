import React, { useState } from 'react';
import { useAccount, useWriteContract } from 'wagmi';
import { parseUnits } from 'viem';
import { QRCodeSVG } from 'qrcode.react';
import { brand } from '../brand';
import { PoolStats } from '../components/PoolStats';
import { useCreditMarket, useTokenBalances, formatUSDC } from '../hooks/usePoolData';
import { DIEM_POOL_ABI, ERC20_ABI } from '../abis/DIEMPool';
import { CONTRACTS, RHINO_CONFIG } from '../config/contracts';

type PaymentMethod = 'direct' | 'crosschain';

interface SmartDepositAddress {
  address: string;
  chain: string;
  token: string;
  expiresAt: number;
}

export function BuyPage() {
  const { address, isConnected } = useAccount();
  const [usdcAmount, setUsdcAmount] = useState('');
  const [paymentMethod, setPaymentMethod] = useState<PaymentMethod>('direct');
  const [selectedChain, setSelectedChain] = useState(RHINO_CONFIG.SUPPORTED_CHAINS[0]);
  const [sdaLoading, setSdaLoading] = useState(false);
  const [sda, setSda] = useState<SmartDepositAddress | null>(null);

  const { currentPrice } = useCreditMarket();
  const balances = useTokenBalances(address as `0x${string}`);

  const { writeContract, isPending } = useWriteContract();

  const poolAddress = CONTRACTS.DIEM_POOL as `0x${string}`;
  const usdcAddress = CONTRACTS.USDC as `0x${string}`;

  // Calculate credits user will receive
  const usdcValue = parseFloat(usdcAmount) || 0;
  const creditsReceived = usdcValue / currentPrice;
  const savingsPercent = ((1 - currentPrice) * 100).toFixed(0);

  const handleApprove = () => {
    const amount = parseUnits(usdcAmount || '0', 6);
    writeContract({
      address: usdcAddress,
      abi: ERC20_ABI,
      functionName: 'approve',
      args: [poolAddress, amount],
    });
  };

  const handleBuyCredits = () => {
    const amount = parseUnits(usdcAmount || '0', 6);
    writeContract({
      address: poolAddress,
      abi: DIEM_POOL_ABI,
      functionName: 'buyCreditsWithMaxUSDC',
      args: [amount],
    });
  };

  const needsApproval = usdcAmount && 
    parseUnits(usdcAmount, 6) > balances.usdcAllowance;

  // Create Smart Deposit Address via Rhino
  const createSDA = async () => {
    setSdaLoading(true);
    try {
      // In production, this would call your backend which uses rhino.fi SDK
      // For now, simulate the response
      await new Promise(resolve => setTimeout(resolve, 1500));
      
      // Mock SDA response - in production this comes from rhino.fi SDK
      setSda({
        address: '0x' + Array(40).fill(0).map(() => Math.floor(Math.random() * 16).toString(16)).join(''),
        chain: selectedChain.name,
        token: selectedChain.token,
        expiresAt: Date.now() + 24 * 60 * 60 * 1000, // 24 hours
      });
    } catch (error) {
      console.error('Failed to create SDA:', error);
    }
    setSdaLoading(false);
  };

  if (!isConnected) {
    return (
      <div style={styles.container}>
        <PoolStats />
        <div style={styles.card}>
          <h2 style={styles.cardTitle}>Buy Inference Credits</h2>
          <p style={styles.cardSubtitle}>Connect your wallet to purchase AI inference credits at a discount</p>
        </div>
      </div>
    );
  }

  return (
    <div style={styles.container}>
      <PoolStats />

      {/* Price Info */}
      <div style={styles.priceCard}>
        <div style={styles.priceMain}>
          <span style={styles.priceLabel}>Current Price</span>
          <span style={styles.priceValue}>${currentPrice.toFixed(2)}</span>
          <span style={styles.pricePer}>per $1 of inference</span>
        </div>
        <div style={styles.savingsBadge}>
          Save {savingsPercent}%
        </div>
      </div>

      {/* Payment Method Tabs */}
      <div style={styles.card}>
        <div style={styles.tabs}>
          <button 
            onClick={() => setPaymentMethod('direct')}
            style={{
              ...styles.tab,
              ...(paymentMethod === 'direct' ? styles.tabActive : {}),
            }}
          >
            <span>Direct Payment</span>
            <span style={styles.tabSubtext}>Pay with USDC on Base</span>
          </button>
          <button 
            onClick={() => setPaymentMethod('crosschain')}
            style={{
              ...styles.tab,
              ...(paymentMethod === 'crosschain' ? styles.tabActive : {}),
            }}
          >
            <span>Cross-Chain</span>
            <span style={styles.tabSubtext}>Pay from any chain</span>
          </button>
        </div>

        {paymentMethod === 'direct' ? (
          <div style={styles.formSection}>
            <div style={styles.balanceRow}>
              <span style={styles.balanceLabel}>Your USDC Balance:</span>
              <span style={styles.balanceValue}>
                ${Number(formatUSDC(balances.usdcBalance)).toFixed(2)}
              </span>
            </div>

            <label style={styles.inputLabel}>Amount to Spend</label>
            <div style={styles.inputWrapper}>
              <span style={styles.inputPrefix}>$</span>
              <input
                type="number"
                value={usdcAmount}
                onChange={(e) => setUsdcAmount(e.target.value)}
                placeholder="0.00"
                style={styles.input}
              />
              <button 
                onClick={() => setUsdcAmount(formatUSDC(balances.usdcBalance))}
                style={styles.maxButton}
              >
                MAX
              </button>
              <span style={styles.inputSuffix}>USDC</span>
            </div>

            {usdcValue > 0 && (
              <div style={styles.previewBox}>
                <div style={styles.previewRow}>
                  <span>You Pay</span>
                  <span>${usdcValue.toFixed(2)} USDC</span>
                </div>
                <div style={styles.previewRow}>
                  <span>You Receive</span>
                  <span style={styles.previewHighlight}>${creditsReceived.toFixed(2)} of inference credits</span>
                </div>
                <div style={styles.previewRow}>
                  <span>You Save</span>
                  <span style={styles.savingsText}>${(creditsReceived - usdcValue).toFixed(2)}</span>
                </div>
              </div>
            )}

            {needsApproval ? (
              <button onClick={handleApprove} style={styles.primaryButton} disabled={isPending}>
                {isPending ? 'Approving...' : 'Approve USDC'}
              </button>
            ) : (
              <button 
                onClick={handleBuyCredits} 
                style={styles.primaryButton} 
                disabled={isPending || !usdcAmount || usdcValue <= 0}
              >
                {isPending ? 'Processing...' : `Buy $${creditsReceived.toFixed(2)} of Credits`}
              </button>
            )}
          </div>
        ) : (
          <div style={styles.formSection}>
            <p style={styles.crosschainIntro}>
              Pay with USDC or USDT from any supported chain. Funds are automatically bridged to Base via{' '}
              <a href="https://rhino.fi" target="_blank" rel="noopener noreferrer" style={styles.link}>
                rhino.fi
              </a>
            </p>

            <label style={styles.inputLabel}>Select Source Chain</label>
            <div style={styles.chainGrid}>
              {RHINO_CONFIG.SUPPORTED_CHAINS.map((chain) => (
                <button
                  key={chain.id}
                  onClick={() => {
                    setSelectedChain(chain);
                    setSda(null);
                  }}
                  style={{
                    ...styles.chainButton,
                    ...(selectedChain.id === chain.id ? styles.chainButtonActive : {}),
                  }}
                >
                  {chain.name}
                </button>
              ))}
            </div>

            <label style={styles.inputLabel}>Amount to Deposit</label>
            <div style={styles.inputWrapper}>
              <span style={styles.inputPrefix}>$</span>
              <input
                type="number"
                value={usdcAmount}
                onChange={(e) => {
                  setUsdcAmount(e.target.value);
                  setSda(null);
                }}
                placeholder="0.00"
                style={styles.input}
              />
              <span style={styles.inputSuffix}>{selectedChain.token}</span>
            </div>

            {!sda ? (
              <button 
                onClick={createSDA} 
                style={styles.primaryButton}
                disabled={sdaLoading || !usdcAmount || parseFloat(usdcAmount) <= 0}
              >
                {sdaLoading ? 'Generating Address...' : 'Generate Deposit Address'}
              </button>
            ) : (
              <div style={styles.sdaCard}>
                <h4 style={styles.sdaTitle}>Send {selectedChain.token} to this address</h4>
                <p style={styles.sdaChain}>on {sda.chain}</p>
                
                <div style={styles.qrWrapper}>
                  <QRCodeSVG 
                    value={sda.address} 
                    size={180}
                    bgColor={brand.colors.surface}
                    fgColor={brand.colors.text}
                  />
                </div>

                <div style={styles.addressBox}>
                  <code style={styles.addressText}>{sda.address}</code>
                  <button 
                    onClick={() => navigator.clipboard.writeText(sda.address)}
                    style={styles.copyButton}
                  >
                    Copy
                  </button>
                </div>

                <div style={styles.sdaInfo}>
                  <div style={styles.sdaInfoRow}>
                    <span>Amount to send:</span>
                    <span>${usdcAmount} {selectedChain.token}</span>
                  </div>
                  <div style={styles.sdaInfoRow}>
                    <span>You'll receive:</span>
                    <span style={styles.previewHighlight}>${creditsReceived.toFixed(2)} of credits</span>
                  </div>
                  <div style={styles.sdaInfoRow}>
                    <span>Expires:</span>
                    <span>{new Date(sda.expiresAt).toLocaleString()}</span>
                  </div>
                </div>

                <p style={styles.sdaNote}>
                  Funds will be automatically bridged to Base and used to purchase credits.
                  This typically takes 1-5 minutes.
                </p>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Info Box */}
      <div style={styles.infoCard}>
        <h4 style={styles.infoTitle}>How it works</h4>
        <ul style={styles.infoList}>
          <li>Purchase inference credits at a discount (currently {savingsPercent}% off)</li>
          <li>Credits are valid for Venice AI inference services</li>
          <li>Price decreases throughout the day if credits go unused</li>
          <li>Your purchase helps DIEM stakers earn yield</li>
        </ul>
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
  priceCard: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    background: `linear-gradient(135deg, ${brand.colors.surface} 0%, ${brand.colors.backgroundAlt} 100%)`,
    borderRadius: '16px',
    border: `1px solid ${brand.colors.border}`,
    padding: '24px',
  },
  priceMain: {
    display: 'flex',
    flexDirection: 'column',
  },
  priceLabel: {
    fontSize: '12px',
    color: brand.colors.textMuted,
    textTransform: 'uppercase',
    marginBottom: '4px',
  },
  priceValue: {
    fontSize: '36px',
    fontWeight: 700,
    color: brand.colors.accent,
    fontFamily: brand.fonts.mono,
  },
  pricePer: {
    fontSize: '14px',
    color: brand.colors.textSecondary,
  },
  savingsBadge: {
    padding: '8px 16px',
    background: brand.colors.accentMuted,
    color: brand.colors.accent,
    borderRadius: '20px',
    fontSize: '14px',
    fontWeight: 600,
  },
  tabs: {
    display: 'flex',
    gap: '12px',
    marginBottom: '24px',
  },
  tab: {
    flex: 1,
    padding: '16px',
    background: 'transparent',
    border: `1px solid ${brand.colors.border}`,
    borderRadius: '12px',
    color: brand.colors.textSecondary,
    fontSize: '14px',
    fontWeight: 500,
    cursor: 'pointer',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    gap: '4px',
  },
  tabActive: {
    background: brand.colors.primaryMuted,
    borderColor: brand.colors.primary,
    color: brand.colors.primary,
  },
  tabSubtext: {
    fontSize: '11px',
    opacity: 0.7,
  },
  formSection: {
    display: 'flex',
    flexDirection: 'column',
    gap: '16px',
  },
  balanceRow: {
    display: 'flex',
    justifyContent: 'space-between',
    padding: '12px',
    background: brand.colors.background,
    borderRadius: '8px',
  },
  balanceLabel: {
    fontSize: '14px',
    color: brand.colors.textSecondary,
  },
  balanceValue: {
    fontSize: '14px',
    fontWeight: 600,
    color: brand.colors.text,
    fontFamily: brand.fonts.mono,
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
  inputPrefix: {
    color: brand.colors.textMuted,
    fontSize: '18px',
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
  previewBox: {
    padding: '16px',
    background: brand.colors.background,
    borderRadius: '8px',
    display: 'flex',
    flexDirection: 'column',
    gap: '8px',
  },
  previewRow: {
    display: 'flex',
    justifyContent: 'space-between',
    fontSize: '14px',
    color: brand.colors.textSecondary,
  },
  previewHighlight: {
    color: brand.colors.accent,
    fontWeight: 600,
  },
  savingsText: {
    color: brand.colors.success,
    fontWeight: 600,
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
  crosschainIntro: {
    fontSize: '14px',
    color: brand.colors.textSecondary,
    lineHeight: 1.6,
  },
  link: {
    color: brand.colors.primary,
  },
  chainGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(3, 1fr)',
    gap: '8px',
  },
  chainButton: {
    padding: '12px 8px',
    background: 'transparent',
    border: `1px solid ${brand.colors.border}`,
    borderRadius: '8px',
    color: brand.colors.textSecondary,
    fontSize: '13px',
    cursor: 'pointer',
  },
  chainButtonActive: {
    background: brand.colors.primaryMuted,
    borderColor: brand.colors.primary,
    color: brand.colors.primary,
  },
  sdaCard: {
    padding: '24px',
    background: brand.colors.background,
    borderRadius: '12px',
    textAlign: 'center',
  },
  sdaTitle: {
    fontSize: '16px',
    fontWeight: 600,
    color: brand.colors.text,
    marginBottom: '4px',
  },
  sdaChain: {
    fontSize: '14px',
    color: brand.colors.textSecondary,
    marginBottom: '20px',
  },
  qrWrapper: {
    display: 'inline-block',
    padding: '16px',
    background: brand.colors.surface,
    borderRadius: '12px',
    marginBottom: '16px',
  },
  addressBox: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    padding: '12px',
    background: brand.colors.surface,
    borderRadius: '8px',
    marginBottom: '16px',
  },
  addressText: {
    flex: 1,
    fontSize: '12px',
    color: brand.colors.text,
    fontFamily: brand.fonts.mono,
    wordBreak: 'break-all',
    textAlign: 'left',
  },
  copyButton: {
    padding: '6px 12px',
    background: brand.colors.primaryMuted,
    border: 'none',
    borderRadius: '4px',
    color: brand.colors.primary,
    fontSize: '12px',
    fontWeight: 600,
    cursor: 'pointer',
    whiteSpace: 'nowrap',
  },
  sdaInfo: {
    display: 'flex',
    flexDirection: 'column',
    gap: '8px',
    marginBottom: '16px',
    textAlign: 'left',
  },
  sdaInfoRow: {
    display: 'flex',
    justifyContent: 'space-between',
    fontSize: '14px',
    color: brand.colors.textSecondary,
  },
  sdaNote: {
    fontSize: '12px',
    color: brand.colors.textMuted,
    fontStyle: 'italic',
  },
  infoCard: {
    padding: '20px',
    background: brand.colors.backgroundAlt,
    borderRadius: '12px',
    border: `1px solid ${brand.colors.border}`,
  },
  infoTitle: {
    fontSize: '14px',
    fontWeight: 600,
    color: brand.colors.text,
    marginBottom: '12px',
  },
  infoList: {
    margin: 0,
    paddingLeft: '20px',
    fontSize: '13px',
    color: brand.colors.textSecondary,
    lineHeight: 1.8,
  },
};
