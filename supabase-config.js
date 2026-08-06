// Shared Supabase client for all VALENCE pages.
// Loaded after the Supabase JS CDN script, before any page-specific script.
const SUPABASE_URL = 'https://hqvjrsyhnxmmdczqdfem.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_IjTIpeT3hVB0BWoK8LsIuA_rg0kNS1f';

const supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

/**
 * Redirects to login.html (preserving the current page so login can send
 * the user back) if there is no active session. Resolves with the session
 * if one exists, otherwise redirects and never resolves.
 */
async function requireAuth() {
  const { data: { session } } = await supabaseClient.auth.getSession();
  if (!session) {
    const here = window.location.pathname.split('/').pop();
    window.location.replace('login.html?redirect=' + encodeURIComponent(here));
    return null;
  }
  document.documentElement.style.visibility = 'visible';
  return session;
}

/** Signs the current user out and sends them home. */
async function signOutAndRedirect() {
  await supabaseClient.auth.signOut();
  window.location.href = 'index.html';
}
