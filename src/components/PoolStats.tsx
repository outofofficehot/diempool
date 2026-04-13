import { brand } from '../brand';
import { usePoolStats, useCreditMarket, formatDIEM, formatCredits } from '../hooks/usePoolData';

export function PoolStats() {
  const { totalStakedDIEM, isLoading: poolLoading } = usePoolStats();
  const { availableCredits, currentPrice, utilizationPct, timeRemaining } = useCreditMarket();

  const formatTime = (seconds: bigint) => {
    const s = Number(seconds);
    const hours = Math.floor(s / 3600);
    const mins = Math.floor((s % 3600) / 60);
    return `${hours}h ${mins}m`;
  };

  return (
    <div style={styles.container}>
      <div style={styles.stat}>
        <span style={styles.label}>Total Staked</span>
        <span style={styles.value}>
          {poolLoading ? '...' : `${Number(formatDIEM(totalStakedDIEM)).toLocaleString()} DIEM`}
        </span>
      </div>
      <div style={styles.divider} />
      <div style={styles.stat}>
        <span style={styles.label}>Available Credits</span>
        <span style={styles.value}>
          ${Number(formatCredits(availableCredits)).toLocaleString()}
        </span>
      </div>
      <div style={styles.divider} />
      <div style={styles.stat}>
        <span style={styles.label}>Current Price</span>
        <span style={styles.valueHighlight}>
          ${currentPrice.toFixed(2)} / $1 credit
        </span>
      </div>
      <div style={styles.divider} />
      <div style={styles.stat}>
        <span style={styles.label}>Utilization</span>
        <span style={styles.value}>{utilizationPct.toFixed(1)}%</span>
      </div>
      <div style={styles.divider} />
      <div style={styles.stat}>
        <span style={styles.label}>Day Resets In</span>
        <span style={styles.value}>{formatTime(timeRemaining)}</span>
      </div>
    </div>
  );
}

const styles: { [key: string]: React.CSSProperties } = {
  container: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: '24px',
    padding: '16px 24px',
    background: brand.colors.surface,
    borderRadius: '12px',
    border: `1px solid ${brand.colors.border}`,
    flexWrap: 'wrap',
  },
  stat: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    gap: '4px',
  },
  label: {
    fontSize: '12px',
    color: brand.colors.textMuted,
    textTransform: 'uppercase',
    letterSpacing: '0.05em',
  },
  value: {
    fontSize: '16px',
    fontWeight: 600,
    color: brand.colors.text,
    fontFamily: brand.fonts.mono,
  },
  valueHighlight: {
    fontSize: '16px',
    fontWeight: 600,
    color: brand.colors.accent,
    fontFamily: brand.fonts.mono,
  },
  divider: {
    width: '1px',
    height: '40px',
    background: brand.colors.border,
  },
};
