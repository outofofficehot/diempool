import { ConnectButton } from '@rainbow-me/rainbowkit';
import { Link, useLocation } from 'react-router-dom';
import { brand } from '../brand';

export function Header() {
  const location = useLocation();
  const isSupplier = location.pathname === '/' || location.pathname === '/supply' || location.pathname === '/pool';
  const isBuyer = location.pathname === '/buy';

  return (
    <header style={styles.header}>
      <div style={styles.left}>
        <Link to="/" style={styles.logo}>
          <span style={styles.logoIcon}>◈</span>
          <span style={styles.logoText}>DIEMpool</span>
        </Link>
        <nav style={styles.nav}>
          <Link
            to="/pool"
            style={{
              ...styles.navLink,
              ...(isSupplier ? styles.navLinkActive : {}),
            }}
          >
            Supply DIEM
          </Link>
          <a
            href="https://cheaptokens.ai/buy"
            rel="noopener noreferrer"
            style={{
              ...styles.navLink,
              ...(isBuyer ? styles.navLinkActive : {}),
            }}
          >
            Buy Inference
          </a>
        </nav>
      </div>
      <div style={styles.right}>
        <ConnectButton />
      </div>
    </header>
  );
}

const styles: { [key: string]: React.CSSProperties } = {
  header: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    flexWrap: 'wrap',
    gap: '12px',
    padding: '16px 24px',
    borderBottom: `1px solid ${brand.colors.border}`,
    background: brand.colors.backgroundAlt,
    overflow: 'hidden',
  },
  left: {
    display: 'flex',
    alignItems: 'center',
    flexWrap: 'wrap',
    gap: '16px',
    minWidth: 0,
  },
  logo: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    textDecoration: 'none',
  },
  logoIcon: {
    fontSize: '24px',
    color: brand.colors.primary,
  },
  logoText: {
    fontFamily: brand.fonts.display,
    fontSize: '20px',
    fontWeight: 600,
    color: brand.colors.text,
  },
  nav: {
    display: 'flex',
    gap: '8px',
  },
  navLink: {
    padding: '8px 10px',
    borderRadius: '8px',
    textDecoration: 'none',
    fontSize: '14px',
    fontWeight: 500,
    color: brand.colors.textSecondary,
    transition: 'all 0.2s',
  },
  navLinkActive: {
    background: brand.colors.primaryMuted,
    color: brand.colors.primary,
  },
  right: {
    marginLeft: 'auto',
    minWidth: 0,
  },
};
