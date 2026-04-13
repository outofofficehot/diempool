import { useReadContract } from 'wagmi';
import { DIEM_POOL_ABI, ERC20_ABI } from '../abis/DIEMPool';
import { CONTRACTS } from '../config/contracts';
import { formatUnits } from 'viem';

const poolAddress = CONTRACTS.DIEM_POOL as `0x${string}`;
const diemAddress = CONTRACTS.DIEM_TOKEN as `0x${string}`;
const usdcAddress = CONTRACTS.USDC as `0x${string}`;

export function usePoolStats() {
  const { data, isLoading, refetch } = useReadContract({
    address: poolAddress,
    abi: DIEM_POOL_ABI,
    functionName: 'getPoolStats',
  });

  return {
    totalShares: data?.[0] ?? 0n,
    totalStakedDIEM: data?.[1] ?? 0n,
    accRewardPerShare: data?.[2] ?? 0n,
    operatorPendingUSDC: data?.[3] ?? 0n,
    isLoading,
    refetch,
  };
}

export function useCreditMarket() {
  const { data, isLoading, refetch } = useReadContract({
    address: poolAddress,
    abi: DIEM_POOL_ABI,
    functionName: 'getCreditMarketStatus',
  });

  const availableCredits = data?.[0] ?? 0n;
  const creditsSold = data?.[1] ?? 0n;
  const currentPriceBps = data?.[2] ?? 8000n;
  const timeRemaining = data?.[3] ?? 0n;

  // Calculate utilization
  const totalCredits = availableCredits + creditsSold;
  const utilizationPct = totalCredits > 0n 
    ? Number((creditsSold * 10000n) / totalCredits) / 100 
    : 0;

  return {
    availableCredits,
    creditsSold,
    currentPriceBps,
    currentPrice: Number(currentPriceBps) / 10000, // e.g., 0.80
    timeRemaining,
    utilizationPct,
    isLoading,
    refetch,
  };
}

export function useStakerInfo(address: `0x${string}` | undefined) {
  const { data: stakerData, isLoading: stakerLoading, refetch: refetchStaker } = useReadContract({
    address: poolAddress,
    abi: DIEM_POOL_ABI,
    functionName: 'stakers',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const { data: pendingYield, refetch: refetchPending } = useReadContract({
    address: poolAddress,
    abi: DIEM_POOL_ABI,
    functionName: 'pendingYield',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const { data: sharePercentage } = useReadContract({
    address: poolAddress,
    abi: DIEM_POOL_ABI,
    functionName: 'getSharePercentage',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const { data: withdrawalData, refetch: refetchWithdrawal } = useReadContract({
    address: poolAddress,
    abi: DIEM_POOL_ABI,
    functionName: 'withdrawalStatus',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  return {
    shares: stakerData?.[0] ?? 0n,
    rewardDebt: stakerData?.[1] ?? 0n,
    pendingUSDC: stakerData?.[2] ?? 0n,
    stakedDIEM: stakerData?.[3] ?? 0n,
    cooldownDIEM: stakerData?.[4] ?? 0n,
    cooldownEnd: stakerData?.[5] ?? 0n,
    pendingYield: pendingYield ?? 0n,
    sharePercentageBps: sharePercentage ?? 0n,
    withdrawalAmount: withdrawalData?.[0] ?? 0n,
    withdrawalCooldownEnd: withdrawalData?.[1] ?? 0n,
    canCompleteWithdrawal: withdrawalData?.[2] ?? false,
    isLoading: stakerLoading,
    refetch: () => {
      refetchStaker();
      refetchPending();
      refetchWithdrawal();
    },
  };
}

export function useTokenBalances(address: `0x${string}` | undefined) {
  const { data: diemBalance, refetch: refetchDiem } = useReadContract({
    address: diemAddress,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const { data: usdcBalance, refetch: refetchUsdc } = useReadContract({
    address: usdcAddress,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const { data: diemAllowance, refetch: refetchDiemAllowance } = useReadContract({
    address: diemAddress,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: address ? [address, poolAddress] : undefined,
    query: { enabled: !!address },
  });

  const { data: usdcAllowance, refetch: refetchUsdcAllowance } = useReadContract({
    address: usdcAddress,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: address ? [address, poolAddress] : undefined,
    query: { enabled: !!address },
  });

  return {
    diemBalance: diemBalance ?? 0n,
    usdcBalance: usdcBalance ?? 0n,
    diemAllowance: diemAllowance ?? 0n,
    usdcAllowance: usdcAllowance ?? 0n,
    refetch: () => {
      refetchDiem();
      refetchUsdc();
      refetchDiemAllowance();
      refetchUsdcAllowance();
    },
  };
}

// Formatting helpers
export function formatDIEM(amount: bigint): string {
  return formatUnits(amount, 18);
}

export function formatUSDC(amount: bigint): string {
  return formatUnits(amount, 6);
}

export function formatCredits(amount: bigint): string {
  // Credits are in 1e6 precision (1 credit = $1)
  return formatUnits(amount, 6);
}
