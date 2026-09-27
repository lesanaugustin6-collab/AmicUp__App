// @ts-nocheck
/// <reference lib="deno.ns" />

import { createClient } from "npm:@supabase/supabase-js@2";
import * as jwt from "https://deno.land/x/djwt@v3.0.2/mod.ts";

type WebhookRecord = {
  sender_id?: string;
  receiver_id?: string;
  content?: string;
};

type WebhookPayload = {
  record?: WebhookRecord;
};

type FirebaseServiceAccount = {
  client_email: string;
  private_key: string;
  project_id: string;
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY environment variables.");
}

const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
    },
  });
}

async function importPrivateKey(privateKey: string): Promise<CryptoKey> {
  const normalizedPrivateKey = privateKey
    .replaceAll("\\n", "\n")
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");

  const keyBytes = Uint8Array.from(atob(normalizedPrivateKey), (char) => char.charCodeAt(0));

  return await crypto.subtle.importKey(
    "pkcs8",
    keyBytes.buffer,
    {
      name: "RSASSA-PKCS1-v1_5",
      hash: "SHA-256",
    },
    false,
    ["sign"],
  );
}

async function getGoogleAccessToken(serviceAccount: FirebaseServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = {
    alg: "RS256",
    typ: "JWT",
  };

  const payload = {
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const key = await importPrivateKey(serviceAccount.private_key);
  const assertion = await jwt.create(header, payload, key);

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!response.ok) {
    throw new Error(`Failed to exchange Google OAuth token: ${response.status} ${await response.text()}`);
  }

  const data = await response.json() as { access_token?: string };
  if (!data.access_token) {
    throw new Error("Google OAuth token response did not include access_token.");
  }

  return data.access_token;
}

async function fetchRecipientFcmToken(receiverId: string): Promise<string | null> {
  const { data, error } = await supabaseAdmin
    .from("profiles")
    .select("fcm_token")
    .eq("id", receiverId)
    .maybeSingle();

  if (error) {
    throw error;
  }

  const token = data?.fcm_token?.toString().trim() ?? "";
  return token || null;
}

async function sendFcmPush(params: {
  token: string;
  content: string;
  serviceAccount: FirebaseServiceAccount;
}): Promise<void> {
  const accessToken = await getGoogleAccessToken(params.serviceAccount);

  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${params.serviceAccount.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: params.token,
          notification: {
            title: "New Message",
            body: params.content,
          },
        },
      }),
    },
  );

  if (!response.ok) {
    throw new Error(`FCM send failed: ${response.status} ${await response.text()}`);
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  let body: WebhookPayload;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const record = body.record;
  const receiverId = record?.receiver_id?.trim();
  const content = record?.content?.trim();

  if (!receiverId || !content) {
    return jsonResponse({ error: "Missing record.receiver_id or record.content" }, 400);
  }

  const recipientFcmToken = await fetchRecipientFcmToken(receiverId);
  if (!recipientFcmToken) {
    return jsonResponse({ success: true, message: "No FCM token found" }, 200);
  }

  const rawServiceAccount = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!rawServiceAccount) {
    throw new Error("Missing FIREBASE_SERVICE_ACCOUNT environment variable.");
  }

  const serviceAccount = JSON.parse(rawServiceAccount) as FirebaseServiceAccount;
  if (!serviceAccount.client_email || !serviceAccount.private_key || !serviceAccount.project_id) {
    throw new Error("FIREBASE_SERVICE_ACCOUNT must contain client_email, private_key, and project_id.");
  }

  await sendFcmPush({
    token: recipientFcmToken,
    content,
    serviceAccount,
  });

  return jsonResponse({ success: true });
});
