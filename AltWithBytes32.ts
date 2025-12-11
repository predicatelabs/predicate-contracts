import dotenv from 'dotenv';
dotenv.config();
import {PredicateClient, PredicateRequest, packFunctionArgs, signaturesToBytes} from '@predicate/core';
import { ethers, hexlify } from 'ethers';
import bs58 from "bs58";

// Set to the deployed Depositor address
const CONTRACT_ADDRESS = '0xe7Eb9538D308f29389780769E8035A40C4D9c3B6';
const SOLANA_ADDRESS_STRING ='8SfpAAUkA4E1ZTSzXiAR51f1iGuVQU4r7kiNUxh7GpVM';
const FUNCTION_SIGNATURE = '_deposit(bytes32)';

export const solanaAddressToHex = (solanaAddress: string): string =>
  hexlify(bs58.decode(solanaAddress));

export const hexToSolanaAddress = (hex: string): string =>
  bs58.encode(ethers.getBytes(hex));

const predicateClient = new PredicateClient({
    apiUrl: 'https://api.predicate.io/',
    apiKey: process.env.PREDICATE_API_KEY!
});

// ABI for Depositor.deposit(bytes32, PredicateMessage)
const contractABI = [
    "function deposit(bytes32 depositor, tuple(string, uint256, address[], bytes[]) predicateMessage)"
];

const provider = new ethers.JsonRpcProvider(process.env.RPC);
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY || "", provider);
const contract = new ethers.Contract(CONTRACT_ADDRESS, contractABI, wallet);
  
type ExtendedPredicateRequest = PredicateRequest & {
    address_to_validate: string;
    function_signature: string;
  };

async function main() {
    const contractAddress = await contract.getAddress();

    // _deposit(bytes32) takes only the depositor identifier (bytes32)
    const depositorBytes32 = solanaAddressToHex(SOLANA_ADDRESS_STRING);
    const functionArgs = [depositorBytes32];
    const data = packFunctionArgs(FUNCTION_SIGNATURE, functionArgs);

    const request: ExtendedPredicateRequest = {
        from: wallet.address,
        to: contractAddress,
        data, // Hex encoded data 
        msg_value: '0',
        // The Predicate API validates the Solana address embedded in the calldata
        address_to_validate: SOLANA_ADDRESS_STRING,
        function_signature: FUNCTION_SIGNATURE,
      };


    const evaluationResult = await predicateClient.evaluatePolicy(request);
    console.log("Policy evaluation result:", evaluationResult);
    if (!evaluationResult.is_compliant) {
        console.error("Policy evaluation failed - transaction not compliant");
        return;
    }

    const predicateMessage = signaturesToBytes(evaluationResult);

    // Call Depositor.deposit(bytes32, PredicateMessage)
    const tx = await contract.deposit(
      depositorBytes32,
      [
        predicateMessage.taskId,
        predicateMessage.expireByBlockNumber,
        predicateMessage.signerAddresses,
        predicateMessage.signatures,
      ],
      {
        value: 0,
      },
    );
    
      console.log('Tx submitted:', tx.hash);
      const receipt = await tx.wait();
      console.log('Transaction mined. Receipt:', receipt);
    }

main().catch((error) => {
    console.error("Error evaluating policy:", error);
    process.exit(1);
});