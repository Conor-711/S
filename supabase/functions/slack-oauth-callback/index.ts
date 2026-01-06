// Supabase Edge Function: slack-oauth-callback
// This function handles Slack OAuth callback and token exchange
// It receives the authorization code from Slack, exchanges it for tokens, and redirects to the app

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const APP_CALLBACK_SCHEME = "s-navigator://slack/callback"

// Slack OAuth credentials
const SLACK_CLIENT_ID = Deno.env.get("SLACK_CLIENT_ID") || "3484211601798.10235979120821"
const SLACK_CLIENT_SECRET = Deno.env.get("SLACK_CLIENT_SECRET") || "589391f403f22dbc1523cb56ba0aaa36"

serve(async (req) => {
  const url = new URL(req.url)
  
  // Get query parameters from Slack callback
  const code = url.searchParams.get("code")
  const state = url.searchParams.get("state")
  const error = url.searchParams.get("error")
  
  // Build redirect URL to app
  const redirectParams = new URLSearchParams()
  
  if (error) {
    // Handle error case
    redirectParams.set("error", error)
    const errorDescription = url.searchParams.get("error_description")
    if (errorDescription) {
      redirectParams.set("error_description", errorDescription)
    }
    const appRedirectURL = `${APP_CALLBACK_SCHEME}?${redirectParams.toString()}`
    return new Response(null, {
      status: 302,
      headers: { "Location": appRedirectURL },
    })
  }
  
  if (!code) {
    redirectParams.set("error", "no_code")
    redirectParams.set("error_description", "No authorization code received")
    const appRedirectURL = `${APP_CALLBACK_SCHEME}?${redirectParams.toString()}`
    return new Response(null, {
      status: 302,
      headers: { "Location": appRedirectURL },
    })
  }
  
  try {
    // Exchange code for access token
    const tokenResponse = await fetch("https://slack.com/api/oauth.v2.access", {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        client_id: SLACK_CLIENT_ID,
        client_secret: SLACK_CLIENT_SECRET,
        code: code,
      }),
    })
    
    const tokenData = await tokenResponse.json()
    
    if (!tokenData.ok) {
      redirectParams.set("error", tokenData.error || "token_exchange_failed")
      redirectParams.set("error_description", tokenData.error || "Failed to exchange token")
      const appRedirectURL = `${APP_CALLBACK_SCHEME}?${redirectParams.toString()}`
      return new Response(null, {
        status: 302,
        headers: { "Location": appRedirectURL },
      })
    }
    
    // Success - pass token data to app
    // The app will receive: access_token, team info, incoming_webhook info
    redirectParams.set("access_token", tokenData.access_token)
    redirectParams.set("team_id", tokenData.team?.id || "")
    redirectParams.set("team_name", tokenData.team?.name || "")
    redirectParams.set("bot_user_id", tokenData.bot_user_id || "")
    
    // Include incoming webhook if available (for posting to channel)
    if (tokenData.incoming_webhook) {
      redirectParams.set("webhook_url", tokenData.incoming_webhook.url || "")
      redirectParams.set("webhook_channel", tokenData.incoming_webhook.channel || "")
      redirectParams.set("webhook_channel_id", tokenData.incoming_webhook.channel_id || "")
    }
    
    if (state) {
      redirectParams.set("state", state)
    }
    
    const appRedirectURL = `${APP_CALLBACK_SCHEME}?${redirectParams.toString()}`
    console.log(`Slack OAuth success, redirecting to app`)
    
    return new Response(null, {
      status: 302,
      headers: { "Location": appRedirectURL },
    })
    
  } catch (err) {
    console.error("Error exchanging token:", err)
    redirectParams.set("error", "server_error")
    redirectParams.set("error_description", "Failed to process OAuth callback")
    const appRedirectURL = `${APP_CALLBACK_SCHEME}?${redirectParams.toString()}`
    return new Response(null, {
      status: 302,
      headers: { "Location": appRedirectURL },
    })
  }
})
