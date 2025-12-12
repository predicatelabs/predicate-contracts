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
  'TransparentUpgradeableProxy',
];

const artifactsDir = 'artifacts';
const outDir = 'out';

// Ensure artifacts directory exists
if (!fs.existsSync(artifactsDir)) {
  fs.mkdirSync(artifactsDir, { recursive: true });
}

const extractedContracts = [];

// Process each contract
for (const contractName of contracts) {
  // Foundry flattens structure by contract name
  const jsonFile = path.join(outDir, `${contractName}.sol`, `${contractName}.json`);

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

    // Extract ABI and bytecode
    const abi = artifact.abi;
    const bytecode = artifact.bytecode?.object || artifact.bytecode || '';
    const deployedBytecode = artifact.deployedBytecode?.object || artifact.deployedBytecode || '';

    // Create artifact directory
    const contractArtifactDir = path.join(artifactsDir, contractName);
    if (!fs.existsSync(contractArtifactDir)) {
      fs.mkdirSync(contractArtifactDir, { recursive: true });
    }

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
      console.log(`✓ Extracted bytecode for ${contractName}`);

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
