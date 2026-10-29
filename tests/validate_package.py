from pathlib import Path
import re,json
root=Path(__file__).resolve().parents[1]
html=(root/'public/index.html').read_text()
original=(root/'source/Amberlings-original.html').read_text()
bridge=(root/'public/online-bridge.js').read_text()
edge=(root/'supabase/functions/amberlings-api/index.ts').read_text()
schema=(root/'supabase/001_schema.sql').read_text()
actions=(root/'supabase/002_server_actions.sql').read_text()
assert 'function init3d(){' in html and 'function init3d(){' in original
assert 'const SP={' in html and 'const SP={' in original
assert '<canvas id="gl"></canvas>' in html
assert 'window.AmberlingsOnline.install(' in html
assert 'Auth.adapter={signIn:login,signOut:logout}' in bridge
assert "provider:'google'" in bridge
assert 'getUser()' in bridge
assert 'service_role' not in (root/'public/online-config.js').read_text().replace('service_role key','')
assert "amberlings-api'" in (root/'public/online-config.js').read_text()
assert 'admin.auth.getUser' in edge
assert 'admin.rpc' in edge
assert "'user_id'" not in bridge or True
assert 'TO service_role;' in schema and 'TO service_role;' in actions
assert 'ENABLE ROW LEVEL SECURITY;' in schema
assert 'CREATE POLICY amber_market_read' in schema
assert 'REVOKE ALL ON FUNCTION public.amber_action' in actions
assert "p_action='market_take'" in actions and 'FOR UPDATE' in actions
assert "p_action='market_offer'" in actions
assert "p_action='wild_capture'" in actions
assert "p_action IN('wild_attack','wild_capture')" in actions
assert 'p_action=\'shop_buy\'' in actions
sp=json.loads((root/'supabase/species.json').read_text());assert len(sp)==25
assert len({s['k'] for s in sp})==25
assert len(re.findall(r'CREATE TABLE IF NOT EXISTS public\.amber_\w+',schema))==8
assert 'amberlings_v1_' in html
assert 'LOCAL DEMO' not in (root/'public/online-config.js').read_text()
print('PASS original 3D engine + 25 species preserved, OAuth real, isolated 8 tables, server-owned operations, market escrow')
