import { ConnectButton } from '@rainbow-me/rainbowkit';
import { Link, useLocation } from 'react-router-dom';
import './Header.css';

export function Header() {
  const location = useLocation();
  const isSupplier = location.pathname === '/' || location.pathname === '/supply' || location.pathname === '/pool';
  const isBuyer = location.pathname === '/buy';

  return (
    <header className="site-header">
      <div className="site-header-left">
        <Link className="site-logo" to="/">
          <span className="site-logo-icon">◈</span>
          <span className="site-logo-text">DIEMpool</span>
        </Link>
        <nav className="site-nav">
          <Link
            className={`site-nav-link${isSupplier ? ' site-nav-link-active' : ''}`}
            to="/pool"
          >
            Supply DIEM
          </Link>
          <a
            className={`site-nav-link${isBuyer ? ' site-nav-link-active' : ''}`}
            href="https://cheaptokens.ai/buy"
            rel="noopener noreferrer"
          >
            Buy Inference
          </a>
        </nav>
      </div>
      <div className="site-header-right">
        <ConnectButton />
      </div>
    </header>
  );
}
