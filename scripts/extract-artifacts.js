#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

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

// Contracts that need Standard JSON Input for block explorer verification
// These are the contracts that get deployed and users interact with
const contractsNeedingVerification = [
  'PredicateRegistry',
  'MetaCoin',
  'PredicateHolding',
  'TransparentUpgradeableProxy',
];

const artifactsDir = 'artifacts';
const outDir = 'out';

/**
 * Read source file content from the filesystem
 * Handles both local sources (src/) and library sources (lib/)
 */
function readSourceFile(sourcePath) {
  try {
    const content = fs.readFileSync(sourcePath, 'utf8');
    return content;
  } catch (error) {
    console.log(`⚠ Could not read source file: ${sourcePath}`);
    return null;
  }
}

/**
 * Generate Standard JSON Input for a contract
 * This format is used for block explorer verification (Etherscan, etc.)
 */
function generateStandardJsonInput(artifact, contractName) {
  try {
    // Parse the raw metadata which contains source dependencies and settings
    const metadata = JSON.parse(artifact.rawMetadata);
    
    // Get the list of source files this contract depends on
    const sourcePaths = Object.keys(metadata.sources || {});
    
    if (sourcePaths.length === 0) {
      console.log(`⚠ No sources found in metadata for ${contractName}`);
      return null;
    }
    
    // Read the content of each source file
    const sources = {};
    for (const sourcePath of sourcePaths) {
      const content = readSourceFile(sourcePath);
      if (content) {
        sources[sourcePath] = { content };
      } else {
        // If we can't read a file, we can't create a valid Standard JSON Input
        console.log(`⚠ Skipping Standard JSON for ${contractName}: missing source ${sourcePath}`);
        return null;
      }
    }
    
    // Build the Standard JSON Input
    const standardJsonInput = {
      language: 'Solidity',
      sources: sources,
      settings: {
        optimizer: metadata.settings?.optimizer || { enabled: false, runs: 200 },
        evmVersion: metadata.settings?.evmVersion || 'paris',
        remappings: metadata.settings?.remappings || [],
        metadata: metadata.settings?.metadata || { bytecodeHash: 'ipfs' },
        outputSelection: {
          '*': {
            '*': ['abi', 'evm.bytecode', 'evm.deployedBytecode', 'metadata'],
          },
        },
      },
    };
    
    // Add viaIR if it was used (important for bytecode matching)
    if (metadata.settings?.viaIR) {
      standardJsonInput.settings.viaIR = true;
    }
    
    // Add libraries if any were used
    if (metadata.settings?.libraries && Object.keys(metadata.settings.libraries).length > 0) {
      standardJsonInput.settings.libraries = metadata.settings.libraries;
    }
    
    return standardJsonInput;
  } catch (error) {
    console.log(`⚠ Error generating Standard JSON Input for ${contractName}: ${error.message}`);
    return null;
  }
}

/**
 * Generate compiler settings JSON for a contract
 * This is a separate file for easy access to compiler configuration
 */
function generateCompilerSettings(artifact, contractName) {
  try {
    const metadata = JSON.parse(artifact.rawMetadata);
    
    return {
      compilerVersion: `v${metadata.compiler?.version || 'unknown'}`,
      language: metadata.language || 'Solidity',
      evmVersion: metadata.settings?.evmVersion || 'default',
      optimizer: {
        enabled: metadata.settings?.optimizer?.enabled || false,
        runs: metadata.settings?.optimizer?.runs || 200,
      },
      viaIR: metadata.settings?.viaIR || false,
      metadata: {
        bytecodeHash: metadata.settings?.metadata?.bytecodeHash || 'ipfs',
      },
      compilationTarget: metadata.settings?.compilationTarget || {},
    };
  } catch (error) {
    console.log(`⚠ Error generating compiler settings for ${contractName}: ${error.message}`);
    return null;
  }
}

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

    // Generate Standard JSON Input for contracts that need verification
    if (contractsNeedingVerification.includes(contractName)) {
      const standardJsonInput = generateStandardJsonInput(artifact, contractName);
      if (standardJsonInput) {
        const standardJsonFile = path.join(contractArtifactDir, `${contractName}.standard-json.json`);
        fs.writeFileSync(standardJsonFile, JSON.stringify(standardJsonInput, null, 2));
        const sourceCount = Object.keys(standardJsonInput.sources).length;
        console.log(`✓ Generated Standard JSON Input for ${contractName} (${sourceCount} sources)`);
      }
      
      // Generate separate compiler settings file for easy access
      const compilerSettings = generateCompilerSettings(artifact, contractName);
      if (compilerSettings) {
        const compilerSettingsFile = path.join(contractArtifactDir, `${contractName}.compiler-settings.json`);
        fs.writeFileSync(compilerSettingsFile, JSON.stringify(compilerSettings, null, 2));
        console.log(`✓ Generated compiler settings for ${contractName}`);
      }
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
      
      // Calculate bytecode hash for verification (first 16 chars of sha256)
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
