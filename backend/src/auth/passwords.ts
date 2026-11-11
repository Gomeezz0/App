import { randomBytes, scrypt, timingSafeEqual } from 'node:crypto';

const N = 1 << 15;
const KEY_LEN = 32;

function derive(password: string, salt: Buffer, n: number): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    scrypt(password, salt, KEY_LEN, { N: n, r: 8, p: 1, maxmem: 128 * n * 8 * 2 }, (err, key) =>
      err ? reject(err) : resolve(key),
    );
  });
}

/** Formato: scrypt$N$salt$hash (base64). */
export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16);
  const key = await derive(password, salt, N);
  return `scrypt$${N}$${salt.toString('base64')}$${key.toString('base64')}`;
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const [scheme, n, salt, hash] = stored.split('$');
  if (scheme !== 'scrypt' || !n || !salt || !hash) return false;
  const expected = Buffer.from(hash, 'base64');
  const actual = await derive(password, Buffer.from(salt, 'base64'), Number(n));
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}
