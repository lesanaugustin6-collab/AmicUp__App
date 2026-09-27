// @ts-nocheck
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { GoogleAuth } from "npm:google-auth-library";

serve(async (req) => {
  try {
    const payload = await req.json();
    console.log("Incoming Webhook Payload:", JSON.stringify(payload));

    const record = payload.record;
    if (!record || !record.match_id) {
      console.error("Missing record or match_id in webhook payload");
      return new Response(JSON.stringify({ error: "Missing record or match_id in payload" }), {
        headers: { "Content-Type": "application/json" },
        status: 400,
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // 1. Look up match details
    const { data: match, error: matchError } = await supabase
      .from("matches")
      .select("user_1, user_2")
      .eq("id", record.match_id)
      .single();

    if (matchError || !match) {
      console.error("Match lookup failed:", matchError);
      return new Response(JSON.stringify({ error: "Match not found", details: matchError }), {
        headers: { "Content-Type": "application/json" },
        status: 400,
      });
    }

    // 2. Identify recipient
    const recipientId = record.sender_id === match.user_1 ? match.user_2 : match.user_1;

    // 3. Get ALL profile columns for sender and log the result
    const { data: senderProfile, error: senderError } = await supabase
      .from("profiles")
      .select("*")
      .eq("id", record.sender_id)
      .single();

    if (senderError) {
      console.error("Sender profile lookup error:", JSON.stringify(senderError));
    }
    console.log("Sender Profile Record:", JSON.stringify(senderProfile));

    // Check all standard name column variations automatically
    const senderName =
      senderProfile?.display_name ||
      senderProfile?.full_name ||
      senderProfile?.name ||
      senderProfile?.first_name ||
      senderProfile?.username ||
      senderProfile?.user_name ||
      "New Message";

    console.log(`Resolved Notification Title: "${senderName}"`);

    // 4. Get FCM Token for recipient
    const { data: profile, error: profileError } = await supabase
      .from("profiles")
      .select("fcm_token")
      .eq("id", recipientId)
      .single();

    if (profileError || !profile?.fcm_token) {
      console.log(`No FCM token found for recipient ID: ${recipientId}`);
      return new Response(JSON.stringify({ message: "No FCM token found for recipient" }), {
        headers: { "Content-Type": "application/json" },
        status: 200,
      });
    }

    // 5. Parse Firebase Secret
    const serviceAccountStr = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
    if (!serviceAccountStr) {
      throw new Error("FIREBASE_SERVICE_ACCOUNT secret is missing in Supabase.");
    }

    const serviceAccount = typeof serviceAccountStr === "string" ? JSON.parse(serviceAccountStr) : serviceAccountStr;
    const clientEmail = serviceAccount.client_email;
    const privateKey = serviceAccount.private_key ? serviceAccount.private_key.replace(/\\n/g, "\n") : null;
    const projectId = serviceAccount.project_id;

    if (!clientEmail || !privateKey || !projectId) {
      throw new Error("FIREBASE_SERVICE_ACCOUNT is missing client_email, private_key, or project_id.");
    }

    // 6. Authenticate with Google OAuth2
    const auth = new GoogleAuth({
      credentials: {
        client_email: clientEmail,
        private_key: privateKey,
      },
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });

    const client = await auth.getClient();
    const accessTokenResponse = await client.getAccessToken();
    const accessToken = accessTokenResponse.token;

    // 7. Send FCM Message
    const fcmEndpoint = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
    const fcmResponse = await fetch(fcmEndpoint, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: profile.fcm_token,
          notification: {
            title: senderName,
            body: record.content || "Sent you a message",
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
            type: "direct",
            match_id: String(record.match_id),
            sender_id: String(record.sender_id),
            message_id: String(record.id || ""),
            sender_name: String(senderName),
            body: String(record.content || "Sent you a message"),
            click_action: "FLUTTER_NOTIFICATION_CLICK",
          },
        },
      }),
    });

    const result = await fcmResponse.json();
    console.log("FCM Response:", JSON.stringify(result));

    return new Response(JSON.stringify({ success: true, result }), {
      headers: { "Content-Type": "application/json" },
      status: 200,
    });
  } catch (err: any) {
    console.error("Function error:", err.message);
    return new Response(JSON.stringify({ error: err.message }), {
      headers: { "Content-Type": "application/json" },
      status: 500,
    });
  }
});
