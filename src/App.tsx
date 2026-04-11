import React, { useState } from 'react';
import { brand, copy } from './brand';

function App() {
  const [email, setEmail] = useState('');
  const [submitted, setSubmitted] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');

    if (!email || !email.includes('@')) {
      setError('Please enter a valid email');
      return;
    }

    try {
      const res = await fetch('/api/waitlist', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email }),
      });

      if (!res.ok) {
        const data = await res.json();
        throw new Error(data.error || 'Failed to join waitlist');
      }

      setSubmitted(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Something went wrong. Please try again.');
    }
  };

  return (
    <div style={styles.container}>
      {/* Header */}
      <header style={styles.header}>
        <div style={styles.logo}>
          <span style={styles.logoIcon}>◈</span>
          <span style={styles.logoText}>{brand.name}</span>
        </div>
      </header>

      {/* Venice Ecosystem Banner */}
      <div style={styles.ecosystemBanner}>
        <span style={styles.ecosystemText}>Built for the</span>
        <a href="https://venice.ai" target="_blank" rel="noopener noreferrer" style={styles.ecosystemLink}>
          <img src="/venice-keys.svg" alt="Venice" style={styles.ecosystemLogo} />
          <span style={styles.ecosystemVenice}>Venice</span>
        </a>
        <span style={styles.ecosystemText}>ecosystem</span>
        <span style={styles.ecosystemDivider}>•</span>
        <span style={styles.ecosystemTokens}>
          <span style={styles.tokenBadge}>VVV</span>
          <span style={styles.tokenBadge}>DIEM</span>
        </span>
      </div>

      {/* Hero Section */}
      <section style={styles.hero}>
        <div style={styles.heroContent}>
          <div style={styles.badge}>Coming Soon</div>
          <h1 style={styles.headline}>{copy.hero.headline}</h1>
          <p style={styles.subline}>{copy.hero.subline}</p>
          
          {/* Yield Preview */}
          <div style={styles.yieldPreview}>
            <div style={styles.yieldItem}>
              <span style={styles.yieldLabel}>Example stake</span>
              <span style={styles.yieldValue}>1,000 DIEM</span>
            </div>
            <div style={styles.yieldDivider}>→</div>
            <div style={styles.yieldItem}>
              <span style={styles.yieldLabel}>Est. daily yield</span>
              <span style={styles.yieldValueHighlight}>$0.65 - $0.95</span>
            </div>
            <div style={styles.yieldDivider}>→</div>
            <div style={styles.yieldItem}>
              <span style={styles.yieldLabel}>Est. APY</span>
              <span style={styles.yieldValueHighlight}>24-35%</span>
            </div>
          </div>
          
          <p style={styles.yieldNote}>*Based on 70-100% pool utilization</p>
        </div>

        {/* Animated background gradient */}
        <div style={styles.heroGlow} />
      </section>

      {/* How It Works */}
      <section style={styles.section}>
        <h2 style={styles.sectionTitle}>{copy.howItWorks.title}</h2>
        <div style={styles.stepsGrid}>
          {copy.howItWorks.steps.map((step, i) => (
            <div key={i} style={styles.stepCard}>
              <div style={styles.stepNumber}>{i + 1}</div>
              <div style={styles.stepIcon}>{step.icon}</div>
              <h3 style={styles.stepTitle}>{step.title}</h3>
              <p style={styles.stepDesc}>{step.desc}</p>
            </div>
          ))}
        </div>
      </section>

      {/* Benefits Split */}
      <section style={styles.section}>
        <div style={styles.benefitsGrid}>
          <div style={styles.benefitCard}>
            <h3 style={styles.benefitTitle}>{copy.benefits.stakers.title}</h3>
            <ul style={styles.benefitList}>
              {copy.benefits.stakers.points.map((point, i) => (
                <li key={i} style={styles.benefitItem}>
                  <span style={styles.checkmark}>✓</span>
                  {point}
                </li>
              ))}
            </ul>
          </div>
          <div style={{...styles.benefitCard, ...styles.benefitCardAlt}}>
            <h3 style={styles.benefitTitle}>{copy.benefits.buyers.title}</h3>
            <ul style={styles.benefitList}>
              {copy.benefits.buyers.points.map((point, i) => (
                <li key={i} style={styles.benefitItem}>
                  <span style={{...styles.checkmark, color: brand.colors.accent}}>✓</span>
                  {point}
                </li>
              ))}
            </ul>
          </div>
        </div>
      </section>

      {/* Economics */}
      <section style={styles.section}>
        <h2 style={styles.sectionTitle}>{copy.economics.title}</h2>
        <div style={styles.economicsGrid}>
          {copy.economics.items.map((item, i) => (
            <div key={i} style={styles.economicCard}>
              <div style={styles.economicValue}>{item.value}</div>
              <div style={styles.economicLabel}>{item.label}</div>
              <div style={styles.economicDesc}>{item.desc}</div>
            </div>
          ))}
        </div>
      </section>

      {/* Dynamic Pricing */}
      <section style={styles.section}>
        <div style={styles.pricingCard}>
          <div style={styles.pricingContent}>
            <h3 style={styles.pricingTitle}>{copy.dynamicPricing.title}</h3>
            <p style={styles.pricingDesc}>{copy.dynamicPricing.desc}</p>
          </div>
          <div style={styles.pricingChart}>
            {/* Simple visualization of price curve */}
            <div style={styles.chartContainer}>
              <div style={styles.chartLabel}>Price</div>
              <svg viewBox="0 0 200 100" style={styles.chartSvg}>
                <defs>
                  <linearGradient id="priceGradient" x1="0%" y1="0%" x2="100%" y2="0%">
                    <stop offset="0%" stopColor={brand.colors.primary} />
                    <stop offset="100%" stopColor={brand.colors.accent} />
                  </linearGradient>
                </defs>
                <path
                  d="M 0 20 Q 50 20, 100 40 T 200 80"
                  fill="none"
                  stroke="url(#priceGradient)"
                  strokeWidth="3"
                />
              </svg>
              <div style={styles.chartLabels}>
                <span>Morning</span>
                <span>End of day</span>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Waitlist CTA */}
      <section style={styles.ctaSection}>
        <div style={styles.ctaContent}>
          <h2 style={styles.ctaHeadline}>{copy.cta.headline}</h2>
          <p style={styles.ctaSubline}>{copy.cta.subline}</p>
          
          {submitted ? (
            <div style={styles.successMessage}>
              <span style={styles.successIcon}>✓</span>
              <span>You're on the list! We'll notify you when DIEMpool launches.</span>
            </div>
          ) : (
            <form onSubmit={handleSubmit} style={styles.form}>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder={copy.cta.placeholder}
                style={styles.input}
              />
              <button type="submit" style={styles.button}>
                {copy.cta.button}
              </button>
            </form>
          )}
          
          {error && <p style={styles.error}>{error}</p>}
        </div>
      </section>

      {/* Footer */}
      <footer style={styles.footer}>
        <div style={styles.footerContent}>
          <div style={styles.footerLogo}>
            <span style={styles.logoIcon}>◈</span>
            <span>{brand.name}</span>
          </div>
          <p style={styles.footerPowered}>{copy.footer.powered}</p>
          <p style={styles.footerDisclaimer}>{copy.footer.disclaimer}</p>
        </div>
      </footer>
    </div>
  );
}

const styles: { [key: string]: React.CSSProperties } = {
  container: {
    minHeight: '100vh',
    background: brand.colors.background,
  },

  // Header
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: `${brand.spacing.lg} ${brand.spacing.xl}`,
    maxWidth: '1200px',
    margin: '0 auto',
  },
  logo: {
    display: 'flex',
    alignItems: 'center',
    gap: brand.spacing.sm,
  },
  logoIcon: {
    fontSize: '28px',
    color: brand.colors.primary,
  },
  logoText: {
    fontFamily: brand.fonts.display,
    fontSize: '24px',
    fontWeight: 600,
    color: brand.colors.text,
  },

  // Ecosystem Banner
  ecosystemBanner: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: brand.spacing.sm,
    padding: `${brand.spacing.md} ${brand.spacing.xl}`,
    background: `linear-gradient(90deg, ${brand.colors.primaryMuted} 0%, rgba(0, 212, 170, 0.1) 100%)`,
    borderBottom: `1px solid ${brand.colors.border}`,
    flexWrap: 'wrap',
  },
  ecosystemText: {
    fontSize: '14px',
    color: brand.colors.textSecondary,
  },
  ecosystemLink: {
    display: 'flex',
    alignItems: 'center',
    gap: '6px',
    textDecoration: 'none',
  },
  ecosystemLogo: {
    width: '20px',
    height: '20px',
  },
  ecosystemVenice: {
    fontSize: '15px',
    fontWeight: 600,
    color: brand.colors.text,
  },
  ecosystemDivider: {
    color: brand.colors.textMuted,
    margin: `0 ${brand.spacing.xs}`,
  },
  ecosystemTokens: {
    display: 'flex',
    gap: brand.spacing.xs,
  },
  tokenBadge: {
    padding: `2px ${brand.spacing.sm}`,
    background: brand.colors.surface,
    border: `1px solid ${brand.colors.border}`,
    borderRadius: brand.borderRadius.sm,
    fontSize: '12px',
    fontWeight: 600,
    fontFamily: brand.fonts.mono,
    color: brand.colors.primary,
  },

  // Hero
  hero: {
    position: 'relative',
    padding: `${brand.spacing.xxxl} ${brand.spacing.xl}`,
    textAlign: 'center',
    overflow: 'hidden',
  },
  heroContent: {
    position: 'relative',
    zIndex: 1,
    maxWidth: '800px',
    margin: '0 auto',
  },
  heroGlow: {
    position: 'absolute',
    top: '50%',
    left: '50%',
    transform: 'translate(-50%, -50%)',
    width: '600px',
    height: '600px',
    background: `radial-gradient(circle, ${brand.colors.primaryMuted} 0%, transparent 70%)`,
    pointerEvents: 'none',
  },
  badge: {
    display: 'inline-block',
    padding: `${brand.spacing.xs} ${brand.spacing.md}`,
    background: brand.colors.primaryMuted,
    color: brand.colors.primary,
    borderRadius: brand.borderRadius.full,
    fontSize: '14px',
    fontWeight: 600,
    marginBottom: brand.spacing.lg,
  },
  headline: {
    fontFamily: brand.fonts.display,
    fontSize: 'clamp(36px, 7vw, 64px)',
    fontWeight: 700,
    color: brand.colors.text,
    marginBottom: brand.spacing.lg,
    lineHeight: 1.1,
  },
  subline: {
    fontSize: 'clamp(18px, 3vw, 22px)',
    color: brand.colors.textSecondary,
    marginBottom: brand.spacing.xxl,
    maxWidth: '600px',
    marginLeft: 'auto',
    marginRight: 'auto',
  },

  // Yield Preview
  yieldPreview: {
    display: 'flex',
    flexWrap: 'wrap',
    justifyContent: 'center',
    alignItems: 'center',
    gap: brand.spacing.lg,
    padding: brand.spacing.xl,
    background: brand.colors.surface,
    borderRadius: brand.borderRadius.xl,
    border: `1px solid ${brand.colors.border}`,
    marginBottom: brand.spacing.md,
  },
  yieldItem: {
    display: 'flex',
    flexDirection: 'column',
    gap: brand.spacing.xs,
  },
  yieldLabel: {
    fontSize: '13px',
    color: brand.colors.textMuted,
    textTransform: 'uppercase',
    letterSpacing: '0.05em',
  },
  yieldValue: {
    fontFamily: brand.fonts.mono,
    fontSize: '24px',
    fontWeight: 600,
    color: brand.colors.text,
  },
  yieldValueHighlight: {
    fontFamily: brand.fonts.mono,
    fontSize: '24px',
    fontWeight: 600,
    color: brand.colors.accent,
  },
  yieldDivider: {
    color: brand.colors.textMuted,
    fontSize: '20px',
  },
  yieldNote: {
    fontSize: '13px',
    color: brand.colors.textMuted,
    fontStyle: 'italic',
  },

  // Sections
  section: {
    padding: `${brand.spacing.xxxl} ${brand.spacing.xl}`,
    maxWidth: '1200px',
    margin: '0 auto',
  },
  sectionTitle: {
    fontFamily: brand.fonts.display,
    fontSize: 'clamp(28px, 5vw, 40px)',
    fontWeight: 600,
    color: brand.colors.text,
    textAlign: 'center',
    marginBottom: brand.spacing.xxl,
  },

  // Steps
  stepsGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(250px, 1fr))',
    gap: brand.spacing.lg,
  },
  stepCard: {
    position: 'relative',
    padding: brand.spacing.xl,
    background: brand.colors.surface,
    borderRadius: brand.borderRadius.lg,
    border: `1px solid ${brand.colors.border}`,
    transition: 'all 0.2s ease',
  },
  stepNumber: {
    position: 'absolute',
    top: brand.spacing.md,
    right: brand.spacing.md,
    width: '28px',
    height: '28px',
    background: brand.colors.primaryMuted,
    color: brand.colors.primary,
    borderRadius: brand.borderRadius.full,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontSize: '14px',
    fontWeight: 600,
  },
  stepIcon: {
    fontSize: '36px',
    marginBottom: brand.spacing.md,
  },
  stepTitle: {
    fontFamily: brand.fonts.display,
    fontSize: '18px',
    fontWeight: 600,
    color: brand.colors.text,
    marginBottom: brand.spacing.sm,
  },
  stepDesc: {
    fontSize: '15px',
    color: brand.colors.textSecondary,
    lineHeight: 1.6,
  },

  // Benefits
  benefitsGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))',
    gap: brand.spacing.lg,
  },
  benefitCard: {
    padding: brand.spacing.xl,
    background: brand.colors.surface,
    borderRadius: brand.borderRadius.lg,
    border: `1px solid ${brand.colors.border}`,
  },
  benefitCardAlt: {
    background: brand.colors.backgroundAlt,
  },
  benefitTitle: {
    fontFamily: brand.fonts.display,
    fontSize: '22px',
    fontWeight: 600,
    color: brand.colors.text,
    marginBottom: brand.spacing.lg,
  },
  benefitList: {
    listStyle: 'none',
  },
  benefitItem: {
    display: 'flex',
    alignItems: 'flex-start',
    gap: brand.spacing.sm,
    marginBottom: brand.spacing.md,
    fontSize: '15px',
    color: brand.colors.textSecondary,
  },
  checkmark: {
    color: brand.colors.primary,
    fontWeight: 600,
    marginTop: '2px',
  },

  // Economics
  economicsGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
    gap: brand.spacing.lg,
  },
  economicCard: {
    textAlign: 'center',
    padding: brand.spacing.xl,
    background: brand.colors.surface,
    borderRadius: brand.borderRadius.lg,
    border: `1px solid ${brand.colors.border}`,
  },
  economicValue: {
    fontFamily: brand.fonts.display,
    fontSize: '36px',
    fontWeight: 700,
    color: brand.colors.primary,
    marginBottom: brand.spacing.xs,
  },
  economicLabel: {
    fontSize: '16px',
    fontWeight: 600,
    color: brand.colors.text,
    marginBottom: brand.spacing.xs,
  },
  economicDesc: {
    fontSize: '14px',
    color: brand.colors.textMuted,
  },

  // Dynamic Pricing
  pricingCard: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))',
    gap: brand.spacing.xl,
    padding: brand.spacing.xl,
    background: `linear-gradient(135deg, ${brand.colors.surface} 0%, ${brand.colors.backgroundAlt} 100%)`,
    borderRadius: brand.borderRadius.xl,
    border: `1px solid ${brand.colors.border}`,
  },
  pricingContent: {
    display: 'flex',
    flexDirection: 'column',
    justifyContent: 'center',
  },
  pricingTitle: {
    fontFamily: brand.fonts.display,
    fontSize: '24px',
    fontWeight: 600,
    color: brand.colors.text,
    marginBottom: brand.spacing.md,
  },
  pricingDesc: {
    fontSize: '16px',
    color: brand.colors.textSecondary,
    lineHeight: 1.7,
  },
  pricingChart: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
  },
  chartContainer: {
    width: '100%',
    maxWidth: '300px',
  },
  chartLabel: {
    fontSize: '12px',
    color: brand.colors.textMuted,
    marginBottom: brand.spacing.sm,
  },
  chartSvg: {
    width: '100%',
    height: '100px',
  },
  chartLabels: {
    display: 'flex',
    justifyContent: 'space-between',
    fontSize: '12px',
    color: brand.colors.textMuted,
    marginTop: brand.spacing.sm,
  },

  // CTA
  ctaSection: {
    padding: `${brand.spacing.xxxl} ${brand.spacing.xl}`,
    background: brand.colors.surface,
    borderTop: `1px solid ${brand.colors.border}`,
  },
  ctaContent: {
    maxWidth: '500px',
    margin: '0 auto',
    textAlign: 'center',
  },
  ctaHeadline: {
    fontFamily: brand.fonts.display,
    fontSize: '32px',
    fontWeight: 600,
    color: brand.colors.text,
    marginBottom: brand.spacing.md,
  },
  ctaSubline: {
    fontSize: '16px',
    color: brand.colors.textSecondary,
    marginBottom: brand.spacing.xl,
  },
  form: {
    display: 'flex',
    gap: brand.spacing.sm,
    maxWidth: '400px',
    margin: '0 auto',
  },
  input: {
    flex: 1,
    padding: `${brand.spacing.md} ${brand.spacing.lg}`,
    background: brand.colors.background,
    border: `1px solid ${brand.colors.border}`,
    borderRadius: brand.borderRadius.md,
    color: brand.colors.text,
    fontSize: '16px',
    outline: 'none',
    transition: 'border-color 0.2s ease',
  },
  button: {
    padding: `${brand.spacing.md} ${brand.spacing.xl}`,
    background: brand.colors.primary,
    color: brand.colors.background,
    border: 'none',
    borderRadius: brand.borderRadius.md,
    fontSize: '16px',
    fontWeight: 600,
    cursor: 'pointer',
    transition: 'all 0.2s ease',
    whiteSpace: 'nowrap',
  },
  successMessage: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: brand.spacing.sm,
    padding: brand.spacing.lg,
    background: brand.colors.accentMuted,
    color: brand.colors.accent,
    borderRadius: brand.borderRadius.md,
    fontSize: '15px',
  },
  successIcon: {
    fontWeight: 700,
  },
  error: {
    marginTop: brand.spacing.md,
    color: brand.colors.error,
    fontSize: '14px',
  },

  // Footer
  footer: {
    padding: `${brand.spacing.xxl} ${brand.spacing.xl}`,
    borderTop: `1px solid ${brand.colors.border}`,
  },
  footerContent: {
    maxWidth: '1200px',
    margin: '0 auto',
    textAlign: 'center',
  },
  footerLogo: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: brand.spacing.sm,
    fontFamily: brand.fonts.display,
    fontSize: '20px',
    fontWeight: 600,
    color: brand.colors.text,
    marginBottom: brand.spacing.md,
  },
  footerPowered: {
    fontSize: '14px',
    color: brand.colors.textSecondary,
    marginBottom: brand.spacing.sm,
  },
  footerDisclaimer: {
    fontSize: '12px',
    color: brand.colors.textMuted,
    maxWidth: '500px',
    margin: '0 auto',
  },
};

export default App;
