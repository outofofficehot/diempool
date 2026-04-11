import type { VercelRequest, VercelResponse } from '@vercel/node';

const UPSTASH_URL = process.env.KV_REST_API_URL;
const UPSTASH_TOKEN = process.env.KV_REST_API_TOKEN;

async function redis(command: string[]) {
  const res = await fetch(`${UPSTASH_URL}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${UPSTASH_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(command),
  });
  return res.json();
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  // CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { email } = req.body;

  if (!email || typeof email !== 'string' || !email.includes('@')) {
    return res.status(400).json({ error: 'Invalid email' });
  }

  const cleanEmail = email.trim().toLowerCase();
  const timestamp = new Date().toISOString();

  try {
    // Add to sorted set (score = timestamp for ordering)
    await redis(['ZADD', 'waitlist', Date.now().toString(), cleanEmail]);
    
    // Store metadata
    await redis(['HSET', `waitlist:${cleanEmail}`, 'joined', timestamp, 'email', cleanEmail]);

    return res.status(200).json({ ok: true, message: 'Added to waitlist' });
  } catch (error) {
    console.error('Redis error:', error);
    return res.status(500).json({ error: 'Failed to join waitlist' });
  }
}
