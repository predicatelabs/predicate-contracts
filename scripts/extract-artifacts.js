#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

// List of contracts to extract
// Foundry outputs artifacts at: out/{ContractName}.sol/{ContractName}.json
const contracts = [
  'PredicateRegistry',
  'PredicateClient',
  'IPredicateRegistry',
  'IPredicateClient',
  'PredicateClientProxy',
  'PredicateProtected',
  'IPredicateProtected',
  'MetaCoin',
  'PredicateHolding',
  'TransparentUpgradeableProxy',
];

const artifactsDir = 'artifacts';
const outDir = 'out';

// Ensure artifacts directory exists
if (!fs.existsSync(artifactsDir)) {
  fs.mkdirSync(artifactsDir, { recursive: true });
}

const extractedContracts = [];
let compilerMetadataExtracted = false;

// Process each contract
for (const contractName of contracts) {
  // Foundry creates artifacts based on directory structure
  // For contracts in inheritance examples, check inheritance directory first, then default
  let jsonFile;
  if (contractName === 'MetaCoin') {
    // MetaCoin from inheritance pattern: src/examples/inheritance/MetaCoin.sol
    jsonFile = path.join(outDir, 'inheritance', `${contractName}.sol`, `${contractName}.json`);
  } else if (contractName === 'PredicateHolding') {
    // PredicateHolding may be in default location or inheritance directory
    const defaultPath = path.join(outDir, `${contractName}.sol`, `${contractName}.json`);
    const inheritancePath = path.join(outDir, 'inheritance', `${contractName}.sol`, `${contractName}.json`);
    jsonFile = fs.existsSync(defaultPath) ? defaultPath : inheritancePath;
  } else {
    // Default: Foundry flattens structure by contract name
    jsonFile = path.join(outDir, `${contractName}.sol`, `${contractName}.json`);
  }

  // Check if the artifact file exists
  if (!fs.existsSync(jsonFile)) {
    console.log(`⚠ Skipping ${contractName} (artifact not found at ${jsonFile})`);
    continue;
  }

  console.log(`Processing ${contractName} from ${jsonFile}`);

  try {
    // Read and parse the artifact file
    const artifactContent = fs.readFileSync(jsonFile, 'utf8');
    const artifact = JSON.parse(artifactContent);

    // Extract compiler metadata (only once, from first contract)
    if (!compilerMetadataExtracted && artifact.metadata) {
      try {
        const metadata = JSON.parse(artifact.metadata);
        const compilerInfo = {
          compiler: {
            version: metadata.compiler?.version || 'unknown',
          },
          settings: {
            optimizer: {
              enabled: metadata.settings?.optimizer?.enabled || false,
              runs: metadata.settings?.optimizer?.runs || 200,
            },
            evmVersion: metadata.settings?.evmVersion || 'default',
            viaIR: metadata.settings?.viaIR || false,
          },
        };
        
        const compilerMetadataFile = path.join(artifactsDir, 'compiler-metadata.json');
        fs.writeFileSync(compilerMetadataFile, JSON.stringify(compilerInfo, null, 2));
        console.log(`✓ Extracted compiler metadata`);
        compilerMetadataExtracted = true;
      } catch (error) {
        console.log(`⚠ Could not parse compiler metadata: ${error.message}`);
      }
    }

    // Extract source file information from metadata for verification
    let sourceFile = 'unknown';
    let compilationTarget = null;
    if (artifact.metadata) {
      try {
        const metadata = JSON.parse(artifact.metadata);
        compilationTarget = metadata.settings?.compilationTarget || {};
        // Get the source file from compilation target (most reliable)
        const targetKeys = Object.keys(compilationTarget);
        if (targetKeys.length > 0) {
          sourceFile = targetKeys[0]; // First key is the source file path
        }
      } catch (error) {
        // Ignore metadata parsing errors for source info
      }
    }

    // Extract ABI and bytecode
    const abi = artifact.abi;
    const bytecode = artifact.bytecode?.object || artifact.bytecode || '';
    const deployedBytecode = artifact.deployedBytecode?.object || artifact.deployedBytecode || '';

    // Create artifact directory
    const contractArtifactDir = path.join(artifactsDir, contractName);
    if (!fs.existsSync(contractArtifactDir)) {
      fs.mkdirSync(contractArtifactDir, { recursive: true });
    }

    // Save source metadata for this contract
    const sourceMetadata = {
      contractName: contractName,
      artifactPath: jsonFile,
      sourceFile: sourceFile,
      compilationTarget: compilationTarget,
    };
    const sourceMetadataFile = path.join(contractArtifactDir, `${contractName}.source.json`);
    fs.writeFileSync(sourceMetadataFile, JSON.stringify(sourceMetadata, null, 2));

    // Always save ABI (even for interfaces)
    if (abi && Array.isArray(abi) && abi.length > 0) {
      const abiFile = path.join(contractArtifactDir, `${contractName}.abi.json`);
      fs.writeFileSync(abiFile, JSON.stringify(abi, null, 2));
      console.log(`✓ Extracted ABI for ${contractName}`);
    }

    // Save bytecode if it exists and is not empty
    if (bytecode && bytecode !== 'null' && bytecode !== '0x' && bytecode.length > 10) {
      const bytecodeFile = path.join(contractArtifactDir, `${contractName}.bytecode`);
      fs.writeFileSync(bytecodeFile, bytecode);
      
      // Calculate bytecode hash for verification (first 16 chars of keccak256)
      const crypto = require('crypto');
      const bytecodeHash = crypto.createHash('sha256').update(bytecode).digest('hex').substring(0, 16);
      
      console.log(`✓ Extracted bytecode for ${contractName} (length: ${bytecode.length}, hash: ${bytecodeHash})`);
      console.log(`  Source: ${sourceFile}`);
      if (compilationTarget && Object.keys(compilationTarget).length > 0) {
        console.log(`  Compilation target: ${JSON.stringify(compilationTarget)}`);
      }

      // Save deployed bytecode if it exists
      if (
        deployedBytecode &&
        deployedBytecode !== 'null' &&
        deployedBytecode !== '0x' &&
        deployedBytecode.length > 10
      ) {
        const deployedBytecodeFile = path.join(
          contractArtifactDir,
          `${contractName}.deployed.bytecode`
        );
        fs.writeFileSync(deployedBytecodeFile, deployedBytecode);
        console.log(`✓ Extracted deployed bytecode for ${contractName}`);
      }
    }

    extractedContracts.push(contractName);
  } catch (error) {
    console.error(`✗ Error processing ${contractName}:`, error.message);
    process.exitCode = 1;
  }
}

// Output summary
if (extractedContracts.length > 0) {
  const sortedContracts = extractedContracts.sort();
  
  // Write to GitHub Actions output if GITHUB_OUTPUT is set
  const githubOutput = process.env.GITHUB_OUTPUT;
  if (githubOutput) {
    const outputContent = `contracts<<EOF
${sortedContracts.join('\n')}
EOF
`;
    fs.appendFileSync(githubOutput, outputContent);
  }
  
  console.log('');
  console.log('Found contracts:');
  console.log(sortedContracts.join('\n'));
  console.log('');
  console.log('Artifact summary:');
  
  // List all artifact files
  const artifactFiles = [];
  function listFiles(dir, baseDir = '') {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name);
      const relativePath = baseDir ? path.join(baseDir, entry.name) : entry.name;
      if (entry.isDirectory()) {
        listFiles(fullPath, relativePath);
      } else {
        artifactFiles.push(`  - artifacts/${relativePath}`);
      }
    }
  }
  listFiles(artifactsDir);
  console.log(artifactFiles.join('\n'));
} else {
  console.log('Warning: No contracts found to extract');
  process.exitCode = 1;
}
