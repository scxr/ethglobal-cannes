import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { sepolia, arbitrumSepolia, optimismSepolia, baseSepolia } from 'wagmi/chains';

export const config = getDefaultConfig({
  appName: 'OmniDAO',
  projectId: 'a55dea7621dd2029035fbe0cc3b42b34', // Get one at https://cloud.walletconnect.com
  chains: [
    sepolia,
    arbitrumSepolia,
    optimismSepolia,
    baseSepolia,
  ],
  ssr: true,
}); 