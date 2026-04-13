/**
 * Contract addresses and configuration
 */

// Base Mainnet
export const BASE_CHAIN_ID = 8453;

// Contract addresses on Base
export const CONTRACTS = {
  DIEM_POOL: '0x0000000000000000000000000000000000000000', // TODO: Deploy and update
  DIEM_TOKEN: '0xf4d97f2da56e8c3098f3a8d538db630a2606a024',
  USDC: '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913',
} as const;

// For testnet (Base Sepolia)
export const TESTNET_CONTRACTS = {
  DIEM_POOL: '0x0000000000000000000000000000000000000000', // TODO: Deploy
  DIEM_TOKEN: '0x0000000000000000000000000000000000000000', // TODO: Deploy mock
  USDC: '0x0000000000000000000000000000000000000000', // TODO: Deploy mock
} as const;

// Credit precision (1e6 = $1 worth of credits)
export const CREDIT_PRECISION = 1_000_000n;

// Rhino.fi configuration for cross-chain payments
export const RHINO_CONFIG = {
  // Supported chains for USDC/USDT deposits
  SUPPORTED_CHAINS: [
    { id: 1, name: 'Ethereum', token: 'USDC' },
    { id: 42161, name: 'Arbitrum', token: 'USDC' },
    { id: 10, name: 'Optimism', token: 'USDC' },
    { id: 137, name: 'Polygon', token: 'USDC' },
    { id: 8453, name: 'Base', token: 'USDC' },
    { id: 43114, name: 'Avalanche', token: 'USDC' },
  ],
  // Destination chain for all deposits (Base)
  DESTINATION_CHAIN: 'BASE',
  DESTINATION_TOKEN: 'USDC',
};
