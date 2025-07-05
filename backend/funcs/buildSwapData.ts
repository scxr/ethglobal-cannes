import { parseEther, encodeFunctionData } from 'viem';
import { readFileSync } from 'fs';
import path from 'path';

let chainAddresses = {
    "ETH": "0x96ab23d6224cCA013D119Edd5A31813C32BCA077",
    "BNB": "0x6B5b5A7A5195Da7E20251822022Ae03B12Df5952",
    "Arbitrum": "0x2f4B6e5Ae6728C1832E93DE67141908F8Aa9255B",
    "Optimism": "0xB55a9254b467A0a52d6696cD327f4C4a37498c1A"
}
let chainIds = {
    "ETH": 10161,
    "BNB": 10102,
    "Arbitrum": 10231,
    "Optimism": 10232
}
let stargateAbi = readFileSync(path.join(__dirname, '../abis/stargateAbi.json'), 'utf8');
let allowedChains = ["ETH", "BNB", "Arbitrum", "Optimism"]
function generateCallData(
    srcChain: "ETH" | "BNB" | "Arbitrum" | "Optimism",
    dstChain: "ETH" | "BNB" | "Arbitrum" | "Optimism",
    amount: number,
    amountOutMin: number,
) {
    let swapData = {
        "_dstChainId": chainIds[dstChain],
        "_srcPoolId": srcChain == "BNB" ? 2 : 1,
        "_dstPoolId": dstChain == "BNB" ? 2 : 1,
        "_refundAddress": "0x0000000000000000000000000000000000000000", // todo: change to deployed contract
        "_amountLD": parseEther(amount.toString()),
        "_minAmountLD": parseEther(amountOutMin.toString()),
        "_lzTxParams.dstGasForCall": 0,
        "_lzTxParams.dstNativeAmount": "",
        "_lzTxParams.dstNativeAddr": "0x0000000000000000000000000000000000000000", // todo: change to deployed contract
        "_to": "0x0000000000000000000000000000000000000000", // todo: change to deployed contract
        "_payload": ""
    }

    const callData = encodeFunctionData({
        abi: JSON.parse(stargateAbi),
        functionName: "swap",
        args: [swapData]
    });

    return callData
    
}

export default generateCallData;