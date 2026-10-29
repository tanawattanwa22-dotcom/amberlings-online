// Server-only authenticated actions. This function owns the authority boundary.
// Deploy to the NEW Amberlings Supabase project only. Never commit service role keys.
import { createClient } from 'npm:@supabase/supabase-js@2.57.0';
const url = Deno.env.get('SUPABASE_URL') || '';
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
if (!url || !serviceKey) throw new Error('Missing Supabase environment secrets');
const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
const actions = new Set([
  'bootstrap', 'create_character', 'starter', 'state', 'save_view', 'daily',
  'shop_buy', 'heal', 'evolve', 'team', 'wild_start', 'wild_attack',
  'wild_capture', 'wild_run', 'market_offer', 'market_take',
  'market_cancel', 'market_list', 'leaderboard', 'travel'
]);
const originFromEnv=(Deno.env.get('AMBERLINGS_ALLOWED_ORIGIN') || '').replace(/\/$/, '');
function cors(origin: string) {
  const trusted = originFromEnv && origin === originFromEnv;
  return {
    'Access-Control-Allow-Origin': trusted ? originFromEnv : originFromEnv || 'null',
    'Access-Control-Allow-Headers': 'authorization,apikey,content-type,x-client-info',
    'Access-Control-Allow-Methods': 'POST,OPTIONS',
    'Vary': 'Origin',
    'Cache-Control': 'no-store, max-age=0'
  };
}
function json(body: unknown, status: number, origin: string) {
  return new Response(JSON.stringify(body), {
    status, headers: { ...cors(origin), 'Content-Type': 'application/json;charset=UTF-8' }
  });
}
Deno.serve(async (request: Request) => {
  const origin = request.headers.get('Origin') || '';
  if (request.method === 'OPTIONS') return new Response(null, {status: 204, headers: cors(origin)});
  if (request.method !== 'POST') return json({ok:false,error:'method_not_allowed'},405,origin);
  if (originFromEnv && origin && origin !== originFromEnv) return json({ok:false,error:'origin_forbidden'},403,origin);
  if (Number(request.headers.get('Content-Length') || 0) > 8192) return json({ok:false,error:'too_large'},413,origin);
  const header = request.headers.get('Authorization') || '';
  if (!header.startsWith('Bearer ') || header.length > 8192) return json({ok:false,error:'sign_in_required'},401,origin);
  try {
    // The browser's claimed user id / monster id never counts as authentication.
    const {data: {user}, error: authError} = await admin.auth.getUser(header.slice(7));
    if (authError || !user?.id) return json({ok:false,error:'invalid_session'},401,origin);
    const req = await request.json();
    if (!req || Array.isArray(req) || typeof req !== 'object') return json({ok:false,error:'invalid_body'},400,origin);
    const {action, data} = req as {action?: unknown, data?: unknown};
    if (typeof action !== 'string' || !actions.has(action) || !data || Array.isArray(data) || typeof data !== 'object')
      return json({ok:false,error:'invalid_action'},400,origin);
    const payload: Record<string, unknown> = {};
    const allow = new Set(['name','gender','uniform','hair','skin','map','x','y','dir',
      'species','creature','slot','item','quantity','move','orb','offer','price']);
    for (const [k,v] of Object.entries(data as Record<string,unknown>)) {
      if (allow.has(k)) payload[k] = v;
    }
    const {data: result, error} = await admin.rpc('amber_action',{
      p_user:user.id, p_action:action, p:payload
    });
    if (error) {
      console.error('amber_action failed',error.code,error.message);
      return json({ok:false,error:'server_action_rejected'},500,origin);
    }
    return json(result ?? {ok:false,error:'empty_result'},200,origin);
  } catch(e) {
    console.error('invalid request',String(e));
    return json({ok:false,error:'invalid_request'},400,origin);
  }
});
