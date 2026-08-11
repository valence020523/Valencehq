// supabase/functions/verify-order-payment/index.ts
//
// Deploy: supabase functions deploy verify-order-payment
// Uses the same secrets as verify-paystack-payment — if you already set
// PAYSTACK_SECRET_KEY, SUPABASE_URL, and SUPABASE_SERVICE_ROLE_KEY for
// that function, this one is ready to go with no extra setup.
//
// Same principle as verify-paystack-payment: verifies the transaction
// directly with Paystack's secret key server-side, then writes the order
// using the service role — the client never creates a "paid" order itself.

import { serve } from 'https://deno.land/std@0.203.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function generateTrackingNumber(): string {
  const time = Date.now().toString(36).toUpperCase();
  const rand = Math.random().toString(36).slice(2, 6).toUpperCase();
  return `VLC-${time}-${rand}`;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      console.error('REJECTED: no_auth_header');
      return json({ ok: false, error: 'not_authenticated' }, 401);
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const paystackSecretKey = Deno.env.get('PAYSTACK_SECRET_KEY')!;

    const callerClient = createClient(supabaseUrl, serviceRoleKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await callerClient.auth.getUser();
    if (userError || !userData?.user) {
      console.error('REJECTED: not_authenticated', userError);
      return json({ ok: false, error: 'not_authenticated' }, 401);
    }
    const userId = userData.user.id;

    const {
      reference,
      listing_id,
      full_name,
      phone,
      address_line1,
      address_line2,
      city,
      state,
      postal_code,
      country,
      expected_amount_cents,
    } = await req.json();

    if (!reference || !listing_id || !full_name || !phone || !address_line1 || !city || !state || !expected_amount_cents) {
      console.error('REJECTED: missing_fields');
      return json({ ok: false, error: 'missing_fields' }, 400);
    }

    // ---- Verify the transaction directly with Paystack ----
    const verifyRes = await fetch(`https://api.paystack.co/transaction/verify/${encodeURIComponent(reference)}`, {
      headers: { Authorization: `Bearer ${paystackSecretKey}` },
    });
    const verifyJson = await verifyRes.json();
    console.log('Paystack verify response:', JSON.stringify(verifyJson));

    if (!verifyRes.ok || !verifyJson.status || verifyJson.data?.status !== 'success') {
      console.error('REJECTED: payment_not_successful', { paystackStatus: verifyJson.data?.status });
      return json({ ok: false, error: 'payment_not_successful' }, 402);
    }

    const paidAmount = verifyJson.data.amount;
    if (paidAmount < expected_amount_cents) {
      console.error('REJECTED: amount_mismatch', { paidAmount, expected_amount_cents });
      return json({ ok: false, error: 'amount_mismatch' }, 402);
    }

    const metaUserId = verifyJson.data.metadata?.user_id;
    if (metaUserId && metaUserId !== userId) {
      console.error('REJECTED: user_mismatch', { metaUserId, userId });
      return json({ ok: false, error: 'user_mismatch' }, 403);
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    // Idempotency: if this reference was already processed (e.g. the
    // browser retried after a network hiccup), return the existing order
    // instead of creating a duplicate.
    const { data: existing } = await adminClient
      .from('orders')
      .select('tracking_number')
      .eq('paystack_reference', reference)
      .maybeSingle();

    if (existing) {
      return json({ ok: true, tracking_number: existing.tracking_number });
    }

    const trackingNumber = generateTrackingNumber();

    const { data: inserted, error: insertError } = await adminClient
      .from('orders')
      .insert([{
        user_id: userId,
        listing_id,
        full_name,
        phone,
        address_line1,
        address_line2: address_line2 || null,
        city,
        state,
        postal_code: postal_code || null,
        country: country || 'Nigeria',
        amount_paid_cents: paidAmount,
        payment_method: 'paystack',
        paystack_reference: reference,
        tracking_number: trackingNumber,
        status: 'paid',
      }])
      .select('tracking_number')
      .single();

    if (insertError) {
      console.error('REJECTED: db_write_failed', insertError);
      return json({ ok: false, error: 'db_write_failed' }, 500);
    }

    console.log('SUCCESS: order created', { userId, listing_id, reference, trackingNumber });
    return json({ ok: true, tracking_number: inserted.tracking_number });
  } catch (err) {
    console.error('REJECTED: internal_error', err);
    return json({ ok: false, error: 'internal_error' }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
