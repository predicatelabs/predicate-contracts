 import { PredicateClient, PredicateRequest, packFunctionArgs, signaturesToBytes } from '@predicate/core';
import { ethers } from 'ethers';

// ---------------------------
// CONFIG – FILL THESE IN
// ---------------------------

// Deployed MetaCoin contract address
const META_COIN_ADDRESS = '0xYOUR_METACOIN_ADDRESS_HERE';

// The EVM receiver of the MetaCoin transfer (the `_receiver` argument)
const RECEIVER_ADDRESS = '0xRECEIVER_ADDRESS_HERE';

// Solana address to validate (32-byte public key as hex, 0x + 64 chars).
// Base58: 8SfpAAUkA4E1ZTSzXiAR51f1iGuVQU4r7kiNUxh7GpVM
// This MUST match what your policy expects and is passed as bytes32 onchain.
const SOLANA_ADDRESS_BYTES32 =
  '0x6e9536fc5afc72c1d40c97c39a749b7f257fecbd38b554a28ae92f70fae72600';

// Internal function that Predicate sees (must match the abi.encodeWithSignature string)
const FUNCTION_SIGNATURE = '_sendCoin(address,bytes32)';

// ---------------------------
// SETUP
// ---------------------------

if (!process.env.PREDICATE_API_KEY) {
  console.error('Error: PREDICATE_API_KEY is not set.');
  process.exit(1);
}

if (!process.env.RPC) {
  console.error('Error: RPC is not set.');
  process.exit(1);
}

if (!process.env.PRIVATE_KEY) {
  console.error('Error: PRIVATE_KEY is not set.');
  process.exit(1);
}

const predicateClient = new PredicateClient({
  apiUrl: 'https://api.predicate.io/',
  apiKey: process.env.PREDICATE_API_KEY!,
});

const provider = new ethers.JsonRpcProvider(process.env.RPC);
const wallet = new ethers.Wallet(process.env.PRIVATE_KEY!, provider);

// ABI matching your modified MetaCoin
const contractABI = [
  // sendCoin(address _receiver, bytes32 solanaAddress, PredicateMessage _message)
  'function sendCoin(address _receiver, bytes32 solanaAddress, tuple(string taskId, uint256 expireByTime, address[] signerAddresses, bytes[] signatures) _message) external payable',
];

const contract = new ethers.Contract(META_COIN_ADDRESS, contractABI, wallet);

// Extend PredicateRequest with the new fields your API expects
type ExtendedPredicateRequest = PredicateRequest & {
  address_to_validate: string;
  function_signature: string;
};

async function main() {
  const contractAddress = await contract.getAddress();
  console.log('Using MetaCoin at:', contractAddress);
  console.log('Sender wallet:', wallet.address);
  console.log('Receiver:', RECEIVER_ADDRESS);
  console.log('Solana address (bytes32):', SOLANA_ADDRESS_BYTES32);

  // 1. Encode the internal function + args exactly as the contract does
  const functionArgs = [RECEIVER_ADDRESS, SOLANA_ADDRESS_BYTES32];

  const data = packFunctionArgs(FUNCTION_SIGNATURE, functionArgs);

  // 2. Build the Predicate request including address_to_validate and function_signature
  const request: ExtendedPredicateRequest = {
    from: wallet.address,
    to: contractAddress,
    data,
    msg_value: '0',

    // New fields required by Predicate API for address extraction
    address_to_validate: SOLANA_ADDRESS_BYTES32,
    function_signature: FUNCTION_SIGNATURE,
  };

  console.log('Evaluating policy with request:', {
    from: request.from,
    to: request.to,
    msg_value: request.msg_value,
    address_to_validate: request.address_to_validate,
    function_signature: request.function_signature,
  });

  // 3. Call Predicate to evaluate the policy
  const evaluationResult = await predicateClient.evaluatePolicy(request);
  console.log('Policy evaluation result:', evaluationResult);

  if (!evaluationResult.is_compliant) {
    console.error('Policy evaluation failed - transaction not compliant');
    return;
  }

  // 4. Convert evaluation result into the PredicateMessage tuple expected by MetaCoin
  const predicateMessage = signaturesToBytes(evaluationResult);

  // Depending on your @predicate/core version, the field may be expireByTime or expireByBlockNumber.
  // Prefer expireByTime if present, otherwise fall back.
  const expireBy =
    (predicateMessage as any).expireByTime ??
    (predicateMessage as any).expireByBlockNumber;

  if (!expireBy) {
    console.error(
      'Predicate message is missing an expiry field (expireByTime/expireByBlockNumber).',
    );
    return;
  }

  // 5. Submit the onchain transaction to MetaCoin.sendCoin
  console.log('Submitting transaction with predicate message...');

  const tx = await contract.sendCoin(
    RECEIVER_ADDRESS,
    SOLANA_ADDRESS_BYTES32,
    [
      predicateMessage.taskId,
      expireBy,
      predicateMessage.signerAddresses,
      predicateMessage.signatures,
    ],
    {
      value: 0, // msg.value
    },
  );

  console.log('Tx submitted:', tx.hash);
  const receipt = await tx.wait();
  console.log('Transaction mined. Receipt:', receipt);
}

main().catch((error) => {
  console.error('Error running MetaCoin predicate script:', error);
  process.exit(1);
});


