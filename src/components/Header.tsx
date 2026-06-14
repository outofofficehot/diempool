"use client";

import { ConnectButton } from "@rainbow-me/rainbowkit";
import { usePathname } from "next/navigation";
import { CHEAPTOKENS_BUY_URL } from "@/config/protocol-links";

export function Header() {
  const pathname = usePathname();

  return (
    <header className="site-header">
      <div className="site-header-left">
        <a className="site-logo" href="/">
          <span className="site-logo-icon">D</span>
          <span className="site-logo-text">Diempool</span>
        </a>
        <nav className="site-nav">
          <a className={`site-nav-link${pathname === "/" ? " site-nav-link-active" : ""}`} href="/">
            Pool
          </a>
          <a
            className="site-nav-link"
            href={CHEAPTOKENS_BUY_URL}
            rel="noopener noreferrer"
            target="_blank"
          >
            Buy inference
          </a>
        </nav>
      </div>
      <div className="site-header-right">
        <div className="site-connect-button">
          <ConnectButton />
        </div>
      </div>
    </header>
  );
}
