// @ts-nocheck
import { createClient } from "npm:@supabase/supabase-js@2";
import * as jose from "npm:jose@5";

Deno.serve(async (req: Request) => {
  try {
    const payload = await req.json();
    console.log("1. Webhook Payload Received:", JSON.stringify(payload));

    const record = payload.record;
    if (!record) {
      console.error("Error: Missing record payload inside request body.");
      return new Response(JSON.stringify({ error: "Missing record payload" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const serviceAccountEnv = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
    if (!serviceAccountEnv) {
      console.error("Error: FIREBASE_SERVICE_ACCOUNT secret is missing from Supabase settings.");
      throw new Error("FIREBASE_SERVICE_ACCOUNT secret is missing.");
    }

    const serviceAccount = JSON.parse(serviceAccountEnv);

    // 1. Generate JWT for Google OAuth2
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

    // 2. Fetch Access Token
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
      console.error("Error: Failed to obtain Google OAuth access token:", tokenData);
      throw new Error(`Failed to obtain FCM Access Token: ${JSON.stringify(tokenData)}`);
    }

    // 3. Connect to Supabase
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Exact column match for matches table (user_1 & user_2)
    const targetUserId = record.user_2 || record.user2_id || record.target_user_id || record.receiver_id;
    const actorUserId = record.user_1 || record.user1_id || record.user_id || record.sender_id;

    console.log(`2. Target User ID: ${targetUserId} | Actor User ID: ${actorUserId}`);

    if (!targetUserId) {
      console.error("Error: Could not identify Target User ID from record columns!", record);
      return new Response(JSON.stringify({ error: "Could not identify target user ID" }), { status: 400 });
    }

    // 4. Fetch Receiver FCM Token
    const { data: receiver, error: receiverErr } = await supabase
      .from("profiles")
      .select("fcm_token")
      .eq("id", targetUserId)
      .single();

    if (receiverErr) {
      console.error("Error querying receiver profile:", receiverErr);
    }

    console.log("3. FCM Token found for receiver:", receiver?.fcm_token ? "YES" : "NO");

    if (!receiver?.fcm_token) {
      console.warn(`User ${targetUserId} has NO fcm_token saved in the profiles table.`);
      return new Response(JSON.stringify({ message: "Receiver has no FCM token saved" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    // 5. Fetch Actor Name
    const { data: actor } = await supabase
      .from("profiles")
      .select("full_name")
      .eq("id", actorUserId)
      .single();

    const actorName = actor?.full_name || "Someone";

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
            title: "It's a Match! 🎉",
            body: `You matched with ${actorName}`,
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
            actor_id: String(actorUserId || ""),
          },
        },
      }),
    });

    const fcmResult = await fcmRes.json();
    console.log("4. FCM Send Result:", JSON.stringify(fcmResult));

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
