// paystack-config.js
// Upload this file alongside supabase-config.js on your site.
// Paystack's PUBLIC key is safe to expose in client-side code — it can
// only start a checkout, never move money or read your account.
// Never put your Paystack SECRET key in this file or anywhere in the
// browser; it belongs only in the Edge Function's environment variables.

// Swap this for your LIVE public key when you're ready to take real
// payments (Paystack dashboard → Settings → API Keys & Webhooks →
// switch to Live Mode → copy "Public Key"). Until then, a pk_test_ key
// is fine for testing with Paystack's test cards.
window.PAYSTACK_PUBLIC_KEY = 'pk_test_133fdccbca033fe75b6ef193fb1b02b9abdf14d9';

// Currency your Paystack account is set up to charge in. This app is
// configured for Nigerian Naira across all pages, so leave this as 'NGN'.
window.PAYSTACK_CURRENCY = 'NGN';
