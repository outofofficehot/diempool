import '@rainbow-me/rainbowkit/styles.css';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { WagmiProvider } from 'wagmi';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { RainbowKitProvider, darkTheme } from '@rainbow-me/rainbowkit';
import { config } from './config/wagmi';
import { brand } from './brand';
import { Header } from './components/Header';
import { BuyPage } from './pages/BuyPage';
import { PoolPage } from './pages/PoolPage';

const queryClient = new QueryClient();

function App() {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider
          theme={darkTheme({
            accentColor: brand.colors.primary,
            accentColorForeground: brand.colors.background,
            borderRadius: 'medium',
          })}
        >
          <BrowserRouter>
            <div style={styles.app}>
              <Header />
              <main style={styles.main}>
                <Routes>
                  <Route path="/" element={<Navigate to="/pool" replace />} />
                  <Route path="/supply" element={<Navigate to="/pool" replace />} />
                  <Route path="/buy" element={<BuyPage />} />
                  <Route path="/pool" element={<PoolPage />} />
                </Routes>
              </main>
            </div>
          </BrowserRouter>
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}

const styles: { [key: string]: React.CSSProperties } = {
  app: {
    minHeight: '100vh',
    background: brand.colors.background,
  },
  main: {
    paddingBottom: '48px',
  },
};

export default App;
