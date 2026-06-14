import type { VercelRequest, VercelResponse } from '@vercel/node';

const UPSTASH_URL = process.env.KV_REST_API_URL;
const UPSTASH_TOKEN = process.env.KV_REST_API_TOKEN;
const ADMIN_SECRET = process.env.ADMIN_SECRET;

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
  // Simple auth check
  const authHeader = req.headers.authorization;
  if (!ADMIN_SECRET || authHeader !== `Bearer ${ADMIN_SECRET}`) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    // Get all emails from sorted set (newest first)
    const result = await redis(['ZREVRANGE', 'waitlist', '0', '-1', 'WITHSCORES']);
    
    // Get count
    const countResult = await redis(['ZCARD', 'waitlist']);
    
    const emails: { email: string; joined: string }[] = [];
    const items = result.result || [];
    
    for (let i = 0; i < items.length; i += 2) {
      const email = items[i];
      const timestamp = parseInt(items[i + 1]);
      emails.push({
        email,
        joined: new Date(timestamp).toISOString(),
      });
    }

    return res.status(200).json({
      count: countResult.result || 0,
      emails,
    });
  } catch (error) {
    console.error('Redis error:', error);
    return res.status(500).json({ error: 'Failed to fetch waitlist' });
  }
}
