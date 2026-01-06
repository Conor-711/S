// Supabase Edge Function: notion-oauth-callback
// This function acts as a proxy for Notion OAuth callback
// It receives the authorization code from Notion and redirects to the app

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const APP_CALLBACK_SCHEME = "s-navigator://notion/callback"

serve(async (req) => {
  const url = new URL(req.url)
  
  // Get query parameters from Notion callback
  const code = url.searchParams.get("code")
  const state = url.searchParams.get("state")
  const error = url.searchParams.get("error")
  
  // Build redirect URL to app
  const redirectParams = new URLSearchParams()
  
  if (code) {
    redirectParams.set("code", code)
  }
  if (state) {
    redirectParams.set("state", state)
  }
  if (error) {
    redirectParams.set("error", error)
    const errorDescription = url.searchParams.get("error_description")
    if (errorDescription) {
      redirectParams.set("error_description", errorDescription)
    }
  }
  
  const appRedirectURL = `${APP_CALLBACK_SCHEME}?${redirectParams.toString()}`
  
  console.log(`Redirecting to app: ${appRedirectURL}`)
  
  // Redirect to the app's custom URL scheme
  return new Response(null, {
    status: 302,
    headers: {
      "Location": appRedirectURL,
    },
  })
})
