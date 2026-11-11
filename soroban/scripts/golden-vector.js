#!/usr/bin/env node
//
// Regenerates the attestation-digest golden vector.
//
// The digest is consumed by two independent implementations: this repo's
// predicate-registry (`validation::compute_hash`) and the Predicate API's Go
// signer (`stmapiv2/internal/domain/types.go`, `stellarDigestBytes`). Tests on
// either side that ask their own code for the digest and then sign it only ever
// check that code against itself — reordering the hash preimage, or renaming a
// `Statement` field (`#[contracttype]` uses field names as ScMap keys), changes
// the wire format while every such test still passes.
//
// So this script is a third implementation, deliberately hand-rolled from the
// XDR spec rather than sharing code with either side. Its output is pinned as
// constants in both, which locks them to one value instead of each to itself.
//
//   node soroban/scripts/golden-vector.js            # print the vector
//   node soroban/scripts/golden-vector.js --check    # verify the pinned constants
//
// `--check` is what keeps this honest, and it runs in CI. A pinned constant on
// its own only survives until someone hits a failing golden test and pastes in
// whatever digest the code now produces — at which point the suite is green and
// the protection is gone. Under --check that no longer works: this script's model
// is independent, so a pasted digest disagrees with it and CI fails. Changing the
// format then requires editing this model too, which is a visible, reviewable act
// rather than a one-character fix.
//
// Consumers of the output:
//   * soroban/predicate-registry/src/lib.rs — the GV_* constants (checked here)
//   * predicate-avs stmapiv2 — the Go golden-vector test (not reachable from
//     this repo; keep it in step manually)
//
// Changing the digest invalidates every attestation already issued. If a change
// is deliberate, regenerate here and update both sides in the same rollout.

const crypto = require('crypto');

// --- strkey (SEP-23) ---------------------------------------------------------

const B32_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
const VERSION_BYTE_ACCOUNT = 6 << 3; // renders as 'G'
const VERSION_BYTE_CONTRACT = 2 << 3; // renders as 'C'

/** CRC16-XModem: polynomial 0x1021, initial value 0. */
function crc16(buf) {
  let crc = 0;
  for (const byte of buf) {
    crc ^= byte << 8;
    for (let i = 0; i < 8; i++) {
      crc = crc & 0x8000 ? ((crc << 1) ^ 0x1021) & 0xffff : (crc << 1) & 0xffff;
    }
  }
  return crc;
}

function base32(buf) {
  let bits = '';
  for (const byte of buf) bits += byte.toString(2).padStart(8, '0');
  while (bits.length % 5) bits += '0';
  let out = '';
  for (let i = 0; i < bits.length; i += 5) {
    out += B32_ALPHABET[parseInt(bits.slice(i, i + 5), 2)];
  }
  return out;
}

function strkey(versionByte, payload) {
  const body = Buffer.concat([Buffer.from([versionByte]), payload]);
  const checksum = crc16(body);
  return base32(
    Buffer.concat([body, Buffer.from([checksum & 0xff, (checksum >> 8) & 0xff])]),
  );
}

// --- XDR ScVal ---------------------------------------------------------------

const u32 = (n) => {
  const b = Buffer.alloc(4);
  b.writeUInt32BE(n);
  return b;
};

/** XDR pads opaque and string payloads up to a 4-byte boundary. */
const pad4 = (b) => Buffer.concat([b, Buffer.alloc(((-b.length % 4) + 4) % 4)]);

const scBytes = (b) => Buffer.concat([u32(13), u32(b.length), pad4(b)]);
const scString = (s) => {
  const b = Buffer.from(s, 'utf8');
  return Buffer.concat([u32(14), u32(b.length), pad4(b)]);
};
const scSymbol = (s) => {
  const b = Buffer.from(s, 'utf8');
  return Buffer.concat([u32(15), u32(b.length), pad4(b)]);
};
const scU64 = (v) => {
  const b = Buffer.alloc(8);
  b.writeBigUInt64BE(BigInt(v));
  return Buffer.concat([u32(5), b]);
};
/** ScVal::I128 carries Int128Parts { hi: int64, lo: uint64 }. */
const scI128 = (v) => {
  const x = BigInt(v);
  const hi = Buffer.alloc(8);
  const lo = Buffer.alloc(8);
  hi.writeBigInt64BE(x >> 64n);
  lo.writeBigUInt64BE(x & ((1n << 64n) - 1n));
  return Buffer.concat([u32(10), hi, lo]);
};
// ScAddress::Account wraps AccountId -> PublicKey, a union whose own
// discriminant (0 = ed25519) sits before the key. ScAddress::Contract wraps a
// bare Hash and has no inner discriminant. Missing those 4 bytes is the easiest
// way to get this encoding subtly wrong.
const scAccount = (key) => Buffer.concat([u32(18), u32(0), u32(0), key]);
const scContract = (key) => Buffer.concat([u32(18), u32(1), key]);

/** A #[contracttype] struct is an ScMap with symbol keys in ascending order. */
const scMap = (entries) =>
  Buffer.concat([
    u32(17),
    u32(1), // the Option<ScMap> is present
    u32(entries.length),
    ...entries.map(([k, v]) => Buffer.concat([scSymbol(k), v])),
  ]);

// --- fixed inputs ------------------------------------------------------------

const NETWORK_PASSPHRASE = 'Test SDF Network ; September 2015';
const MSG_SENDER_KEY = Buffer.alloc(32, 0x11);
const TARGET_KEY = Buffer.alloc(32, 0x22);
const ATTESTER_SEED = Buffer.alloc(32, 0x33);

const STATEMENT = {
  uuid: '3f2504e0-4f89-11d3-9a0c-0305e82c3301',
  msgValue: 1000000n,
  encodedSigAndArgs: Buffer.from([1, 2, 3, 4, 5, 6, 7, 8]),
  policy: 'x-golden-vector-policy',
  expiration: 1767225600n, // 2026-01-01T00:00:00Z
};

// --- derive ------------------------------------------------------------------

const networkId = crypto.createHash('sha256').update(NETWORK_PASSPHRASE).digest();

const statementXdr = scMap([
  ['encoded_sig_and_args', scBytes(STATEMENT.encodedSigAndArgs)],
  ['expiration', scU64(STATEMENT.expiration)],
  ['msg_sender', scAccount(MSG_SENDER_KEY)],
  ['msg_value', scI128(STATEMENT.msgValue)],
  ['policy', scString(STATEMENT.policy)],
  ['target', scContract(TARGET_KEY)],
  ['uuid', scString(STATEMENT.uuid)],
]);

const preimage = Buffer.concat([scBytes(networkId), statementXdr]);
const digest = crypto.createHash('sha256').update(preimage).digest();

// The attester signs the 32-byte digest directly; the contract passes it to
// ed25519_verify unhashed.
const privateKey = crypto.createPrivateKey({
  key: Buffer.concat([
    Buffer.from('302e020100300506032b657004220420', 'hex'), // PKCS#8 Ed25519 seed prefix
    ATTESTER_SEED,
  ]),
  format: 'der',
  type: 'pkcs8',
});
const publicKey = crypto.createPublicKey(privateKey);
const attesterPk = publicKey.export({ format: 'der', type: 'spki' }).subarray(12);
const signature = crypto.sign(null, digest, privateKey);

if (!crypto.verify(null, digest, publicKey, signature)) {
  throw new Error('self-check failed: signature does not verify over the digest');
}

// --- the vector --------------------------------------------------------------

const VECTOR = {
  GV_NETWORK_ID: networkId.toString('hex'),
  GV_MSG_SENDER: strkey(VERSION_BYTE_ACCOUNT, MSG_SENDER_KEY),
  GV_TARGET: strkey(VERSION_BYTE_CONTRACT, TARGET_KEY),
  GV_UUID: STATEMENT.uuid,
  GV_POLICY: STATEMENT.policy,
  GV_MSG_VALUE: STATEMENT.msgValue.toString(),
  GV_EXPIRATION: STATEMENT.expiration.toString(),
  GV_ENCODED_SIG_AND_ARGS: [...STATEMENT.encodedSigAndArgs].join(','),
  GV_DIGEST: digest.toString('hex'),
  GV_ATTESTER_PK: attesterPk.toString('hex'),
  GV_SIGNATURE: signature.toString('hex'),
};

// --- output / check ----------------------------------------------------------

const RUST_SOURCE = require('path').join(
  __dirname,
  '..',
  'predicate-registry',
  'src',
  'lib.rs',
);

/** How each constant is written in the Rust source, so it can be read back. */
const RUST_PATTERNS = {
  GV_NETWORK_ID: /GV_NETWORK_ID\s*:\s*&str\s*=\s*"([0-9a-f]+)"/,
  GV_MSG_SENDER: /GV_MSG_SENDER\s*:\s*&str\s*=\s*"([A-Z2-7]+)"/,
  GV_TARGET: /GV_TARGET\s*:\s*&str\s*=\s*"([A-Z2-7]+)"/,
  GV_UUID: /GV_UUID\s*:\s*&str\s*=\s*"([^"]+)"/,
  GV_POLICY: /GV_POLICY\s*:\s*&str\s*=\s*"([^"]+)"/,
  GV_MSG_VALUE: /GV_MSG_VALUE\s*:\s*i128\s*=\s*([0-9_]+)/,
  GV_EXPIRATION: /GV_EXPIRATION\s*:\s*u64\s*=\s*([0-9_]+)/,
  GV_ENCODED_SIG_AND_ARGS: /GV_ENCODED_SIG_AND_ARGS\s*:\s*\[u8;\s*\d+\]\s*=\s*\[([^\]]+)\]/,
  GV_DIGEST: /GV_DIGEST\s*:\s*&str\s*=\s*"([0-9a-f]+)"/,
  GV_ATTESTER_PK: /GV_ATTESTER_PK\s*:\s*&str\s*=\s*"([0-9a-f]+)"/,
  GV_SIGNATURE: /GV_SIGNATURE\s*:\s*&str\s*=\s*"([0-9a-f]+)"/,
};

/** Rust writes numbers as 1_000_000 and byte arrays as [1, 2, 3]. */
const normalise = (s) => s.replace(/[_\s]/g, '');

function check() {
  const source = require('fs').readFileSync(RUST_SOURCE, 'utf8');
  const problems = [];

  for (const [name, expected] of Object.entries(VECTOR)) {
    const match = source.match(RUST_PATTERNS[name]);
    if (!match) {
      // Never pass silently because a constant moved or was deleted — that is
      // exactly how a golden vector rots into a no-op.
      problems.push(`${name}: not found in ${RUST_SOURCE}`);
      continue;
    }
    const actual = normalise(match[1]);
    if (actual !== normalise(expected)) {
      problems.push(`${name}:\n    pinned in Rust  ${actual}\n    computed here   ${normalise(expected)}`);
    }
  }

  if (problems.length) {
    console.error('Golden vector mismatch — the pinned constants do not match this');
    console.error('independent implementation:\n');
    for (const p of problems) console.error(`  ${p}`);
    console.error(
      '\nIf the format change was deliberate, update the model in this script and',
    );
    console.error(
      'regenerate every consumer, including the Go signer, in the same rollout.',
    );
    process.exit(1);
  }

  console.log(`Golden vector OK — ${Object.keys(VECTOR).length} constants match.`);
}

if (process.argv.includes('--check')) {
  check();
} else {
  console.log(`network passphrase        ${NETWORK_PASSPHRASE}`);
  console.log(`preimage                 ${preimage.length} bytes`);
  for (const [name, value] of Object.entries(VECTOR)) {
    console.log(`${name.padEnd(24)} ${value}`);
  }
}
