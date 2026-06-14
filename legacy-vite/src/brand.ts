/**
 * DIEMpool Brand Configuration
 */

export const brand = {
  name: 'DIEMpool',
  tagline: 'Earn yield on your idle DIEM',
  description: 'Stake your DIEM tokens and earn passive income from AI inference demand.',

  colors: {
    // Venice-inspired dark theme with golden accents
    background: '#0a0a0f',
    backgroundAlt: '#12121a',
    surface: '#1a1a24',
    surfaceHover: '#22222e',
    
    primary: '#f7931a', // DIEM gold/orange
    primaryHover: '#ffa726',
    primaryMuted: 'rgba(247, 147, 26, 0.15)',
    
    accent: '#00d4aa', // Teal for positive/yield
    accentMuted: 'rgba(0, 212, 170, 0.15)',
    
    text: '#ffffff',
    textSecondary: '#a0a0b0',
    textMuted: '#666680',
    
    border: '#2a2a3a',
    borderHover: '#3a3a4a',
    
    success: '#00d4aa',
    warning: '#f7931a',
    error: '#ff4757',
  },

  fonts: {
    display: "'Space Grotesk', sans-serif",
    body: "'Inter', system-ui, sans-serif",
    mono: "'JetBrains Mono', monospace",
  },

  spacing: {
    xs: '4px',
    sm: '8px',
    md: '16px',
    lg: '24px',
    xl: '32px',
    xxl: '48px',
    xxxl: '64px',
  },

  borderRadius: {
    sm: '4px',
    md: '8px',
    lg: '12px',
    xl: '16px',
    full: '9999px',
  },

  shadows: {
    sm: '0 2px 8px rgba(0, 0, 0, 0.3)',
    md: '0 4px 16px rgba(0, 0, 0, 0.4)',
    lg: '0 8px 32px rgba(0, 0, 0, 0.5)',
    glow: '0 0 20px rgba(247, 147, 26, 0.3)',
    glowAccent: '0 0 20px rgba(0, 212, 170, 0.3)',
  },
};

export const copy = {
  hero: {
    headline: 'Earn yield on your idle DIEM',
    subline: 'Stake your tokens. Let others use the inference credits. Get paid daily.',
  },
  
  howItWorks: {
    title: 'How DIEMpool works',
    steps: [
      {
        title: 'Stake your DIEM',
        desc: 'Deposit DIEM tokens to the pool. Your tokens remain yours — withdraw anytime.',
        icon: '📥',
      },
      {
        title: 'Pool generates credits',
        desc: 'Staked DIEM generates $1/day of AI inference credits per token.',
        icon: '⚡',
      },
      {
        title: 'Buyers consume credits',
        desc: 'Developers pay to access pooled credits at a discount to staking themselves.',
        icon: '🔌',
      },
      {
        title: 'You earn yield',
        desc: '95% of all payments flow directly to stakers, proportional to their stake.',
        icon: '💰',
      },
    ],
  },

  benefits: {
    stakers: {
      title: 'For DIEM holders',
      points: [
        'Passive yield on tokens you\'re not using',
        'No lockup — withdraw anytime',
        'Daily yield distribution',
        'Non-custodial: your DIEM stays yours',
      ],
    },
    buyers: {
      title: 'For developers',
      points: [
        '20-30% cheaper than staking yourself',
        'No capital lockup required',
        'Pay-as-you-go API access',
        'Same Venice models, lower cost',
      ],
    },
  },

  economics: {
    title: 'Transparent economics',
    items: [
      { label: 'Staker share', value: '95%', desc: 'of all credit sales' },
      { label: 'Protocol fee', value: '5%', desc: 'to operate the service' },
      { label: 'Buyer discount', value: '20-30%', desc: 'vs staking directly' },
      { label: 'Settlement', value: 'Daily', desc: 'yield distributed every 24h' },
    ],
  },

  dynamicPricing: {
    title: 'Dynamic pricing',
    desc: 'Credit prices adjust throughout the day based on supply and demand. Low utilization? Prices drop — ensuring credits are never wasted.',
  },

  cta: {
    headline: 'Be first in line',
    subline: 'Join the waitlist and get notified when DIEMpool launches.',
    button: 'Join waitlist',
    placeholder: 'you@example.com',
  },

  footer: {
    powered: 'Powered by Venice.ai',
    disclaimer: 'DIEMpool is not affiliated with Venice.ai. DIEM token interactions carry risk.',
  },
};
