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
//   node soroban/scripts/golden-vector.js
//
// Consumers of the output:
//   * soroban/predicate-registry/src/lib.rs — the GV_* constants
//   * predicate-avs stmapiv2 — the Go golden-vector test
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

// --- output ------------------------------------------------------------------

console.log(`network passphrase   ${NETWORK_PASSPHRASE}`);
console.log(`GV_NETWORK_ID        ${networkId.toString('hex')}`);
console.log(`GV_MSG_SENDER        ${strkey(VERSION_BYTE_ACCOUNT, MSG_SENDER_KEY)}`);
console.log(`GV_TARGET            ${strkey(VERSION_BYTE_CONTRACT, TARGET_KEY)}`);
console.log(`GV_UUID              ${STATEMENT.uuid}`);
console.log(`GV_POLICY            ${STATEMENT.policy}`);
console.log(`GV_MSG_VALUE         ${STATEMENT.msgValue}`);
console.log(`GV_EXPIRATION        ${STATEMENT.expiration}`);
console.log(`preimage             ${preimage.length} bytes`);
console.log(`GV_DIGEST            ${digest.toString('hex')}`);
console.log(`GV_ATTESTER_PK       ${attesterPk.toString('hex')}`);
console.log(`GV_SIGNATURE         ${signature.toString('hex')}`);
