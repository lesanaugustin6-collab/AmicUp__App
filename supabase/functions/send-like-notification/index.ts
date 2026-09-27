// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";
import * as jose from "npm:jose@5";

Deno.serve(async (req: Request) => {
  try {
    const payload = await req.json();
    console.log("1. Webhook Payload Received:", JSON.stringify(payload));

    const record = payload.record;
    if (!record) {
      return new Response(JSON.stringify({ error: "Missing record payload" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    // 1. Skip dislikes/passes (only proceed if is_like === true)
    if (record.is_like !== true) {
      console.log("Interaction was a dislike/pass. Skipping push notification.");
      return new Response(JSON.stringify({ message: "Ignored dislike" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    const serviceAccountEnv = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
    if (!serviceAccountEnv) {
      throw new Error("FIREBASE_SERVICE_ACCOUNT secret is missing from Supabase settings.");
    }
    const serviceAccount = JSON.parse(serviceAccountEnv);

    // 2. Generate Google OAuth Access Token
    const pemKey = serviceAccount.private_key;
    const key = await jose.importPKCS8(pemKey, "RS256");
    const jwt = await new jose.SignJWT({
      scope: "https://www.googleapis.com/auth/firebase.messaging",
    })
      .setProtectedHeader({ alg: "RS256" })
      .setIssuer(serviceAccount.client_email)
      .setAudience("https://oauth2.googleapis.com/token")
      .setExpirationTime("1h")
      .setIssuedAt()
      .sign(key);

    const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: jwt,
      }),
    });

    const tokenData = await tokenResponse.json();
    const accessToken = tokenData.access_token;

    if (!accessToken) {
      throw new Error(`Failed to obtain FCM Access Token: ${JSON.stringify(tokenData)}`);
    }

    // 3. Connect to Supabase
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const likerId = record.liker_id;
    const likedId = record.liked_id;

    console.log(`2. Liker ID: ${likerId} | Liked ID: ${likedId}`);

    // 4. Fetch Liked User's FCM Token from profiles
    const { data: receiver, error: receiverErr } = await supabase
      .from("profiles")
      .select("fcm_token")
      .eq("id", likedId)
      .single();

    if (receiverErr) console.error("Error fetching receiver profile:", receiverErr);

    if (!receiver?.fcm_token) {
      console.log(`Liked user (${likedId}) has no FCM token saved.`);
      return new Response(JSON.stringify({ message: "Receiver has no FCM token" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    // 5. Fetch Liker's Full Name from profiles
    const { data: liker } = await supabase
      .from("profiles")
      .select("full_name")
      .eq("id", likerId)
      .single();

    const likerName = liker?.full_name || "Someone";

    // 6. Send Push Notification via FCM HTTP v1
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;
    const fcmRes = await fetch(fcmUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: receiver.fcm_token,
          notification: {
            title: "New Like! ❤️",
            body: `${likerName} liked your profile!`,
          },
          android: {
            notification: {
              channel_id: "background_messages_v1",
              sound: "default",
            },
          },
          apns: {
            payload: { aps: { sound: "default" } },
          },
          data: {
            type: "activity",
            actor_id: String(likerId || ""),
          },
        },
      }),
    });

    const fcmResult = await fcmRes.json();
    console.log("3. FCM Response:", JSON.stringify(fcmResult));

    return new Response(JSON.stringify(fcmResult), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err: unknown) {
    const errorMessage = err instanceof Error ? err.message : String(err);
    console.error("Fatal Error inside Edge Function:", errorMessage);
    return new Response(JSON.stringify({ error: errorMessage }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
