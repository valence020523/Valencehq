// supabase/functions/verify-paystack-payment/index.ts
//
// Deploy with the Supabase CLI:
//   supabase functions deploy verify-paystack-payment
//
// Set these secrets first (never commit them):
//   supabase secrets set PAYSTACK_SECRET_KEY=sk_test_xxxxxxxx
//   supabase secrets set SUPABASE_URL=https://<project-ref>.supabase.co
//   supabase secrets set SUPABASE_SERVICE_ROLE_KEY=<service role key>
//
// This is the ONLY place a pre-order reservation should ever be marked
// "paid" — it verifies the transaction directly with Paystack using the
// secret key (which never touches the browser) before writing anything,
// so a customer can't fake a successful payment from the client.

import { serve } from 'https://deno.land/std@0.203.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

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

    // Client bound to the caller's JWT, used only to confirm who they are.
    const callerClient = createClient(supabaseUrl, serviceRoleKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await callerClient.auth.getUser();
    if (userError || !userData?.user) {
      console.error('REJECTED: not_authenticated', userError);
      return json({ ok: false, error: 'not_authenticated' }, 401);
    }
    const userId = userData.user.id;

    const { reference, listing_id, full_name, expected_amount_cents } = await req.json();
    if (!reference || !listing_id || !full_name || !expected_amount_cents) {
      console.error('REJECTED: missing_fields', { reference, listing_id, full_name, expected_amount_cents });
      return json({ ok: false, error: 'missing_fields' }, 400);
    }

    // ---- Verify the transaction directly with Paystack ----
    const verifyRes = await fetch(`https://api.paystack.co/transaction/verify/${encodeURIComponent(reference)}`, {
      headers: { Authorization: `Bearer ${paystackSecretKey}` },
    });
    const verifyJson = await verifyRes.json();
    console.log('Paystack verify response:', JSON.stringify(verifyJson));

    if (!verifyRes.ok || !verifyJson.status || verifyJson.data?.status !== 'success') {
      console.error('REJECTED: payment_not_successful', { httpOk: verifyRes.ok, paystackStatus: verifyJson.data?.status, message: verifyJson.message });
      return json({ ok: false, error: 'payment_not_successful' }, 402);
    }

    const paidAmount = verifyJson.data.amount; // in the smallest currency unit
    if (paidAmount < expected_amount_cents) {
      console.error('REJECTED: amount_mismatch', { paidAmount, expected_amount_cents });
      return json({ ok: false, error: 'amount_mismatch' }, 402);
    }

    // Metadata set by the client at checkout time — cross-check it matches
    // who's actually calling this function, so one user can't submit
    // another user's successful reference.
    const metaUserId = verifyJson.data.metadata?.user_id;
    if (metaUserId && metaUserId !== userId) {
      console.error('REJECTED: user_mismatch', { metaUserId, userId });
      return json({ ok: false, error: 'user_mismatch' }, 403);
    }

    // ---- Service-role client: bypasses RLS to write the paid reservation ----
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    const { error: upsertError } = await adminClient
      .from('preorder_reservations')
      .upsert(
        {
          user_id: userId,
          listing_id,
          full_name,
          deposit_amount_cents: paidAmount,
          payment_method: 'paystack',
          paystack_reference: reference,
          status: 'paid',
        },
        { onConflict: 'user_id,listing_id' }
      );

    if (upsertError) {
      console.error('REJECTED: db_write_failed', upsertError);
      return json({ ok: false, error: 'db_write_failed' }, 500);
    }

    console.log('SUCCESS: reservation marked paid', { userId, listing_id, reference });
    return json({ ok: true });
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
