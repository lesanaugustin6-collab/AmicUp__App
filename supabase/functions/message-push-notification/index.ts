/// <reference lib="deno.ns" />

const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const FIREBASE_SERVICE_ACCOUNT = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !FIREBASE_SERVICE_ACCOUNT) {
  throw new Error(
    'Missing Supabase service variables or FIREBASE_SERVICE_ACCOUNT secret.',
  );
}

let firebaseAccount: {
  project_id?: string;
  client_email?: string;
  private_key?: string;
};
try {
  firebaseAccount = JSON.parse(FIREBASE_SERVICE_ACCOUNT);
} catch {
  throw new Error('FIREBASE_SERVICE_ACCOUNT must contain valid JSON.');
}

const GOOGLE_PROJECT_ID = firebaseAccount.project_id;
const GOOGLE_CLIENT_EMAIL = firebaseAccount.client_email;
const GOOGLE_PRIVATE_KEY = firebaseAccount.private_key;

if (!GOOGLE_PROJECT_ID || !GOOGLE_CLIENT_EMAIL || !GOOGLE_PRIVATE_KEY) {
  throw new Error(
    'FIREBASE_SERVICE_ACCOUNT is missing project_id, client_email, or private_key.',
  );
}

type WebhookPayload = {
  record?: {
    id?: string;
    match_id?: string;
    sender_id?: string;
    content?: string;
  };
};

type MatchRow = {
  user_1?: string;
  user_2?: string;
};

type ProfileRow = {
  fcm_token?: string | null;
};

const supabaseHeaders = {
  apikey: SUPABASE_SERVICE_ROLE_KEY,
  Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
  'Content-Type': 'application/json',
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function encodeBase64Url(input: Uint8Array | string): string {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : input;
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replaceAll('=', '');
}

async function importServiceAccountPrivateKey(pemKey: string): Promise<CryptoKey> {
  const normalizedPem = pemKey
    .replaceAll('\\n', '\n')
    .trim()
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replaceAll(/\s+/g, '');

  const der = Uint8Array.from(atob(normalizedPem), (character) => character.charCodeAt(0));
  return await crypto.subtle.importKey(
    'pkcs8',
    der.buffer,
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign'],
  );
}

async function getGoogleAccessToken(): Promise<string> {
  const privateKey = await importServiceAccountPrivateKey(GOOGLE_PRIVATE_KEY!);
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'RS256', typ: 'JWT' };
  const payload = {
    iss: GOOGLE_CLIENT_EMAIL,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };

  const encodedHeader = encodeBase64Url(JSON.stringify(header));
  const encodedPayload = encodeBase64Url(JSON.stringify(payload));
  const unsignedJwt = `${encodedHeader}.${encodedPayload}`;

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    privateKey,
    new TextEncoder().encode(unsignedJwt),
  );
  const encodedSignature = encodeBase64Url(new Uint8Array(signature));
  const jwt = `${unsignedJwt}.${encodedSignature}`;

  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });

  if (!tokenResponse.ok) {
    const errorText = await tokenResponse.text();
    throw new Error(`Google OAuth token request failed: ${tokenResponse.status} ${errorText}`);
  }

  const tokenData = await tokenResponse.json() as { access_token?: string };
  if (!tokenData.access_token) {
    throw new Error('Google OAuth token response did not include an access_token.');
  }

  return tokenData.access_token;
}

async function fetchMatchRecipientUserId(matchId: string, senderId: string): Promise<string | null> {
  const response = await fetch(
    `${SUPABASE_URL}/rest/v1/matches?id=eq.${encodeURIComponent(matchId)}&select=user_1,user_2`,
    {
      headers: supabaseHeaders,
    },
  );

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Failed to fetch match record: ${response.status} ${errorText}`);
  }

  const rows = await response.json() as MatchRow[];
  const match = rows[0];
  if (!match) {
    return null;
  }

  if (match.user_1 === senderId) {
    return match.user_2 ?? null;
  }

  if (match.user_2 === senderId) {
    return match.user_1 ?? null;
  }

  return null;
}

async function fetchRecipientToken(userId: string): Promise<string | null> {
  const response = await fetch(
    `${SUPABASE_URL}/rest/v1/profiles?id=eq.${encodeURIComponent(userId)}&select=fcm_token&limit=1`,
    {
      headers: supabaseHeaders,
    },
  );

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Failed to fetch recipient profile: ${response.status} ${errorText}`);
  }

  const rows = await response.json() as ProfileRow[];
  return rows[0]?.fcm_token?.trim() || null;
}

async function sendFcmPush(
  token: string,
  messageBody: string,
  matchId: string,
  senderId: string,
  messageId: string,
): Promise<void> {
  const accessToken = await getGoogleAccessToken();
  const url = `https://fcm.googleapis.com/v1/projects/${GOOGLE_PROJECT_ID}/messages:send`;

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      message: {
        token,
        notification: {
          title: 'New Message',
          body: messageBody,
        },
        android: {
          notification: {
            channel_id: 'background_messages_v1',
            sound: 'default',
          },
        },
        apns: {
          payload: { aps: { sound: 'default' } },
        },
        data: {
          type: 'direct',
          title: 'New Message',
          body: messageBody,
          match_id: matchId,
          message_id: messageId,
          sender_id: senderId,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
      },
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`FCM send failed: ${response.status} ${errorText}`);
  }
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  let payload: WebhookPayload;
  try {
    payload = await request.json();
  } catch {
    return jsonResponse({ error: 'Invalid JSON payload' }, 400);
  }

  const record = payload.record;
  const matchId = record?.match_id?.trim();
  const senderId = record?.sender_id?.trim();
  const content = record?.content?.trim();

  if (!matchId || !senderId || !content) {
    return jsonResponse({ error: 'Missing record.match_id, record.sender_id, or record.content' }, 400);
  }

  const recipientUserId = await fetchMatchRecipientUserId(matchId, senderId);
  if (!recipientUserId || recipientUserId === senderId) {
    return jsonResponse({ ok: true, skipped: true, reason: 'No recipient found' });
  }

  const recipientToken = await fetchRecipientToken(recipientUserId);
  if (!recipientToken) {
    return jsonResponse({ ok: true, skipped: true, reason: 'Recipient has no fcm_token' });
  }

  await sendFcmPush(
    recipientToken,
    content,
    matchId,
    senderId,
    record?.id?.trim() ?? '',
  );
  return jsonResponse({ ok: true });
});
