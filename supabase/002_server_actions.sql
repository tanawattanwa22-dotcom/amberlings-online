-- Server-only API. Never GRANT EXECUTE on either function to anon/authenticated.
-- Called from the Edge Function after Supabase Auth verifies the bearer token.
BEGIN;
CREATE OR REPLACE FUNCTION public.amber_snapshot(p_user uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,public AS $fn$
DECLARE out_data jsonb; BEGIN
 SELECT jsonb_build_object(
   'character',(SELECT to_jsonb(p) FROM public.amber_players p WHERE p.user_id=p_user),
   'creatures',(SELECT coalesce(jsonb_agg(jsonb_build_object(
     'uid',c.id,'species',c.species_key,'level',c.level,'exp',c.exp,'hp',c.hp,
     'shiny',c.shiny,'slot',c.party_slot,'status',c.status)
     ORDER BY c.party_slot NULLS LAST,c.created_at),'[]'::jsonb)
     FROM public.amber_creatures c WHERE c.owner_id=p_user AND c.status='owned'),
   'inventory',(SELECT coalesce(jsonb_object_agg(i.item_key,i.quantity),'{}'::jsonb)
     FROM public.amber_inventory i WHERE i.owner_id=p_user),
   'wild',(SELECT to_jsonb(w) FROM public.amber_encounters w WHERE w.owner_id=p_user),
   'offers',(SELECT coalesce(jsonb_agg(jsonb_build_object(
       'id',m.id,'creature_id',m.creature_id,'seller',m.seller_id,'seller_name',p.display_name,
       'species',c.species_key,'level',c.level,'shiny',c.shiny,
       'price',m.price_coins,'mine',m.seller_id=p_user)
       ORDER BY m.created_at DESC),'[]'::jsonb)
     FROM public.amber_market m
     JOIN public.amber_creatures c ON c.id=m.creature_id
     JOIN public.amber_players p ON p.user_id=m.seller_id WHERE m.status='open'),
   'leaders',(SELECT coalesce(jsonb_agg(jsonb_build_array(x.display_name,x.rating,x.species,true)
       ORDER BY x.rating DESC),'[]'::jsonb)
     FROM (SELECT p.display_name,p.rating,coalesce((SELECT c.species_key FROM public.amber_creatures c
       WHERE c.owner_id=p.user_id AND c.party_slot=1 LIMIT 1),'embit') AS species
       FROM public.amber_players p WHERE p.initialized ORDER BY p.rating DESC LIMIT 25) x)
 ) INTO out_data;
 RETURN out_data;
END $fn$;
REVOKE ALL ON FUNCTION public.amber_snapshot(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.amber_snapshot(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.amber_action(p_user uuid,p_action text,p jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,public AS $fn$
DECLARE
  pl public.amber_players%ROWTYPE;
  mon public.amber_creatures%ROWTYPE;
  wild public.amber_encounters%ROWTYPE;
  sp public.amber_species%ROWTYPE;
  offer public.amber_market%ROWTYPE;
  n integer; q integer; price bigint; xp_gain bigint; dmg integer; hit_dmg integer; defn integer; lv integer;
  t text; spec text; selected uuid; target uuid; msg text:=''; ok boolean:=true;
  nowt timestamptz:=clock_timestamp(); today_th date:=(clock_timestamp() AT TIME ZONE 'Asia/Bangkok')::date;
  fcnt integer; roll numeric; rate numeric;
BEGIN
 IF p_user IS NULL OR p_action IS NULL OR p IS NULL OR jsonb_typeof(p) <> 'object'
   OR p_action NOT IN ('bootstrap','create_character','starter','state','save_view','daily',
    'shop_buy','heal','evolve','team','wild_start','wild_attack','wild_capture','wild_run',
    'market_offer','market_take','market_cancel','market_list','leaderboard','travel')
 THEN RETURN jsonb_build_object('ok',false,'error','invalid_action'); END IF;
 INSERT INTO public.amber_players(user_id) VALUES(p_user) ON CONFLICT(user_id) DO NOTHING;
 -- Initial inventory is granted only once, when account has no inventory and no creatures.
 -- bootstrap may be called repeatedly; never grant multiple starter packs.
 IF EXISTS(SELECT 1 FROM public.amber_players WHERE user_id=p_user AND NOT initialized)
   AND NOT EXISTS(SELECT 1 FROM public.amber_inventory WHERE owner_id=p_user)
 THEN
   INSERT INTO public.amber_inventory(owner_id,item_key,quantity) VALUES
    (p_user,'orb',5),(p_user,'potion',3)
   ON CONFLICT(owner_id,item_key) DO NOTHING;
 END IF;
 SELECT * INTO pl FROM public.amber_players WHERE user_id=p_user FOR UPDATE;
 IF NOT pl.initialized AND p_action NOT IN ('bootstrap','state','create_character','starter') THEN
   RETURN jsonb_build_object('ok',false,'error','create_character_first');
 END IF;
 IF p_action='create_character' THEN
   IF pl.initialized THEN RETURN jsonb_build_object('ok',false,'error','character_already_created'); END IF;
   t:=trim(coalesce(p->>'name',''));
   IF char_length(t)<2 OR char_length(t)>10 OR t !~ '^[[:alnum:]ก-๙ _-]+$'
     OR coalesce(p->>'gender','') NOT IN('m','f')
   THEN RETURN jsonb_build_object('ok',false,'error','invalid_character'); END IF;
   BEGIN n:=(p->>'uniform')::integer; q:=(p->>'hair')::integer; lv:=(p->>'skin')::integer;
   EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok',false,'error','invalid_appearance'); END;
   IF n NOT BETWEEN 0 AND 3 OR q NOT BETWEEN 0 AND 4 OR lv NOT BETWEEN 0 AND 2
   THEN RETURN jsonb_build_object('ok',false,'error','invalid_appearance'); END IF;
   UPDATE public.amber_players SET initialized=true,display_name=t,gender=p->>'gender',
    uniform=n,hair=q,skin=lv,updated_at=nowt WHERE user_id=p_user;
   msg:='character_created';
 ELSIF p_action='starter' THEN
   IF NOT pl.initialized THEN RETURN jsonb_build_object('ok',false,'error','create_character_first'); END IF;
   spec:=p->>'species';
   IF spec NOT IN ('embit','aquip','sproutle')
      OR coalesce((pl.flags->>'starter')::boolean,false)
      OR EXISTS (SELECT 1 FROM public.amber_creatures WHERE owner_id=p_user)
   THEN RETURN jsonb_build_object('ok',false,'error','starter_already_chosen_or_invalid'); END IF;
   SELECT * INTO sp FROM public.amber_species WHERE species_key=spec;
   INSERT INTO public.amber_creatures(owner_id,species_key,level,exp,hp,party_slot)
    VALUES(p_user,spec,5,125,((sp.base_hp*2*5)/100)+5+10,1);
   UPDATE public.amber_players SET flags=jsonb_set(jsonb_set(flags,'{starter}','true'::jsonb),'{starterId}',to_jsonb(spec)),
       caught=jsonb_set(caught,ARRAY[spec],'true'::jsonb),
       seen=jsonb_set(seen,ARRAY[spec],'true'::jsonb),updated_at=nowt WHERE user_id=p_user;
   msg:='starter_granted';
 ELSIF p_action='travel' THEN
   t:=p->>'map';
   IF t NOT IN ('amberton','route1','mossgate','route2','tidehaven','cave','stormpeak','summit')
     THEN RETURN jsonb_build_object('ok',false,'error','unknown_map'); END IF;
   n:=array_position(ARRAY['amberton','route1','mossgate','route2','tidehaven','cave','stormpeak','summit'],pl.map_id);
   q:=array_position(ARRAY['amberton','route1','mossgate','route2','tidehaven','cave','stormpeak','summit'],t);
   IF n IS NULL OR q IS NULL OR abs(n-q)>1 THEN
     RETURN jsonb_build_object('ok',false,'error','not_adjacent'); END IF;
   SELECT coalesce(max(level),1) INTO lv FROM public.amber_creatures
      WHERE owner_id=p_user AND status='owned';
   IF lv < (ARRAY[1,1,6,12,18,23,29,34])[q] THEN
     RETURN jsonb_build_object('ok',false,'error','level_too_low'); END IF;
   UPDATE public.amber_players SET map_id=t,pos_x=11,pos_y=9,updated_at=nowt WHERE user_id=p_user;
   msg:='map_changed';
 ELSIF p_action='save_view' THEN
   -- SAFE: never accepts coins, gems, monsters, inventory, rewards, etc.
   -- Prevent jumping to inaccessible maps by means of a browser save.
   t:=coalesce(p->>'map','amberton');
   IF t<>pl.map_id THEN RETURN jsonb_build_object('ok',false,'error','map_change_requires_server'); END IF;
   BEGIN n:=(p->>'x')::integer;q:=(p->>'y')::integer;
   EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok',false,'error','invalid_position'); END;
   IF n NOT BETWEEN 0 AND 60 OR q NOT BETWEEN 0 AND 60
     OR abs(n-pl.pos_x)>6 OR abs(q-pl.pos_y)>6
   THEN RETURN jsonb_build_object('ok',false,'error','invalid_position'); END IF;
   IF p->>'dir' NOT IN('up','down','left','right') THEN
      RETURN jsonb_build_object('ok',false,'error','invalid_direction'); END IF;
   UPDATE public.amber_players SET pos_x=n,pos_y=q,direction=p->>'dir',updated_at=nowt
     WHERE user_id=p_user;
   msg:='view_saved';
 ELSIF p_action='daily' THEN
   IF pl.last_daily=today_th THEN RETURN jsonb_build_object('ok',false,'error','already_claimed_today'); END IF;
   UPDATE public.amber_players SET last_daily=today_th,coins=coins+200,updated_at=nowt WHERE user_id=p_user;
   INSERT INTO public.amber_inventory(owner_id,item_key,quantity) VALUES(p_user,'orb',3)
     ON CONFLICT(owner_id,item_key) DO UPDATE SET quantity=public.amber_inventory.quantity+3;
   msg:='daily_claimed';
 ELSIF p_action='shop_buy' THEN
   t:=p->>'item';
   BEGIN q:=(p->>'quantity')::integer;
   EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok',false,'error','invalid_quantity'); END;
   IF q IS NULL OR q<1 OR q>20 THEN RETURN jsonb_build_object('ok',false,'error','invalid_quantity'); END IF;
   SELECT price_coins INTO price FROM public.amber_items_catalog WHERE item_key=t AND price_coins>0;
   IF price IS NULL THEN RETURN jsonb_build_object('ok',false,'error','item_not_for_sale'); END IF;
   IF pl.coins<price*q THEN RETURN jsonb_build_object('ok',false,'error','insufficient_coins'); END IF;
   UPDATE public.amber_players SET coins=coins-price*q,updated_at=nowt WHERE user_id=p_user;
   INSERT INTO public.amber_inventory(owner_id,item_key,quantity) VALUES(p_user,t,q)
    ON CONFLICT(owner_id,item_key) DO UPDATE SET quantity=public.amber_inventory.quantity+excluded.quantity;
   msg:='item_purchased';
 ELSIF p_action='heal' THEN
   BEGIN selected=(p->>'creature')::uuid;
   EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok',false,'error','invalid_creature'); END;
   SELECT * INTO mon FROM public.amber_creatures
     WHERE id=selected AND owner_id=p_user AND status='owned' FOR UPDATE;
   IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','not_your_creature'); END IF;
   SELECT * INTO sp FROM public.amber_species WHERE species_key=mon.species_key;
   lv:=floor(sp.base_hp*2*mon.level/100.0)::integer+mon.level+10;
   IF mon.hp>=lv THEN RETURN jsonb_build_object('ok',false,'error','already_full_hp'); END IF;
   UPDATE public.amber_inventory SET quantity=quantity-1
     WHERE owner_id=p_user AND item_key='potion' AND quantity>0;
   IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','no_potion'); END IF;
   UPDATE public.amber_creatures SET hp=least(lv,hp+25),updated_at=nowt WHERE id=selected;
   msg:='creature_healed';
 ELSIF p_action='team' THEN
   BEGIN selected=(p->>'creature')::uuid; n=(p->>'slot')::integer;
   EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok',false,'error','invalid_team_selection'); END;
   IF n NOT BETWEEN 0 AND 6 THEN RETURN jsonb_build_object('ok',false,'error','invalid_slot'); END IF;
   SELECT * INTO mon FROM public.amber_creatures WHERE id=selected AND owner_id=p_user AND status='owned' FOR UPDATE;
   IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','not_your_creature'); END IF;
   UPDATE public.amber_creatures SET party_slot=NULL WHERE owner_id=p_user AND party_slot=n AND id<>selected;
   UPDATE public.amber_creatures SET party_slot=NULLIF(n,0),updated_at=nowt WHERE id=selected;
   msg:='team_updated';
 ELSIF p_action='evolve' THEN
   BEGIN selected=(p->>'creature')::uuid;
   EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok',false,'error','invalid_creature'); END;
   SELECT * INTO mon FROM public.amber_creatures WHERE id=selected AND owner_id=p_user AND status='owned' FOR UPDATE;
   IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','not_your_creature'); END IF;
   SELECT * INTO sp FROM public.amber_species WHERE species_key=mon.species_key;
   IF sp.evolves_to IS NULL OR mon.level<sp.evolve_at
   THEN RETURN jsonb_build_object('ok',false,'error','evolution_locked'); END IF;
   SELECT * INTO sp FROM public.amber_species WHERE species_key=sp.evolves_to;
   n:=floor(sp.base_hp*2*mon.level/100.0)::integer+mon.level+10;
   UPDATE public.amber_creatures SET species_key=sp.species_key,hp=least(n,mon.hp+10),updated_at=nowt WHERE id=selected;
   UPDATE public.amber_players SET caught=jsonb_set(caught,ARRAY[sp.species_key],'true'::jsonb),
     seen=jsonb_set(seen,ARRAY[sp.species_key],'true'::jsonb) WHERE user_id=p_user;
   msg:='evolution_complete';
 ELSIF p_action='wild_start' THEN
   IF NOT pl.initialized OR NOT EXISTS(SELECT 1 FROM public.amber_creatures
     WHERE owner_id=p_user AND status='owned' AND hp>0 AND party_slot IS NOT NULL)
   THEN RETURN jsonb_build_object('ok',false,'error','active_creature_required'); END IF;
   IF EXISTS(SELECT 1 FROM public.amber_encounters WHERE owner_id=p_user)
   THEN RETURN jsonb_build_object('ok',false,'error','encounter_already_active'); END IF;
   -- CBT map: only starter town/route 1. Additional maps need server transition rules.
   IF pl.map_id NOT IN('amberton','route1') THEN RETURN jsonb_build_object('ok',false,'error','region_not_ready'); END IF;
   SELECT species_key INTO spec FROM public.amber_species
     WHERE species_key IN ('fluffo','fluttr','zipbat','pebblo')
     ORDER BY random() LIMIT 1;
   lv:=2+floor(random()*4)::integer;
   SELECT * INTO sp FROM public.amber_species WHERE species_key=spec;
   n:=floor(sp.base_hp*2*lv/100.0)::integer+lv+10;
   INSERT INTO public.amber_encounters(owner_id,species_key,level,max_hp,hp)
     VALUES(p_user,spec,lv,n,n);
   UPDATE public.amber_players SET seen=jsonb_set(seen,ARRAY[spec],'true'::jsonb) WHERE user_id=p_user;
   msg:='wild_encounter_started';
 ELSIF p_action='wild_run' THEN
   DELETE FROM public.amber_encounters WHERE owner_id=p_user;
   msg:='wild_encounter_ended';
 ELSIF p_action IN('wild_attack','wild_capture') THEN
   SELECT * INTO wild FROM public.amber_encounters WHERE owner_id=p_user FOR UPDATE;
   IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','no_wild_encounter'); END IF;
   IF nowt-wild.last_turn<interval '0.45 seconds'
   THEN RETURN jsonb_build_object('ok',false,'error','turn_cooldown'); END IF;
   SELECT * INTO mon FROM public.amber_creatures
     WHERE owner_id=p_user AND party_slot IS NOT NULL AND hp>0 AND status='owned'
     ORDER BY party_slot LIMIT 1 FOR UPDATE;
   IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','team_fainted'); END IF;
   SELECT * INTO sp FROM public.amber_species WHERE species_key=wild.species_key;
   IF p_action='wild_capture' THEN
     t:=p->>'orb';
     IF t NOT IN('orb','silver','gold') THEN RETURN jsonb_build_object('ok',false,'error','invalid_orb'); END IF;
     UPDATE public.amber_inventory SET quantity=quantity-1 WHERE owner_id=p_user AND item_key=t AND quantity>0;
     IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','orb_out_of_stock'); END IF;
     SELECT capture_multiplier INTO rate FROM public.amber_items_catalog WHERE item_key=t;
     roll:=least(0.96,(3*wild.max_hp-2*wild.hp)*sp.capture_rate*rate/(3*wild.max_hp*255.0));
     IF random()<roll THEN
       SELECT g INTO n FROM generate_series(1,6) g WHERE NOT EXISTS (
         SELECT 1 FROM public.amber_creatures x WHERE x.owner_id=p_user AND x.party_slot=g) LIMIT 1;
       INSERT INTO public.amber_creatures(owner_id,species_key,level,exp,hp,shiny,party_slot)
         VALUES(p_user,wild.species_key,wild.level,(wild.level::bigint)^3,greatest(1,wild.hp),random()<0.0156,n);
       UPDATE public.amber_players SET caught=jsonb_set(caught,ARRAY[wild.species_key],'true'::jsonb) WHERE user_id=p_user;
       DELETE FROM public.amber_encounters WHERE owner_id=p_user;
       msg:='capture_success';
     ELSE
       UPDATE public.amber_encounters SET turns=turns+1,last_turn=nowt WHERE owner_id=p_user;
       msg:='capture_failed';
     END IF;
   ELSE
     t:=coalesce(p->>'move','tackle');
     -- Validate the move against server-known element / trainer level.
     SELECT element INTO spec FROM public.amber_species WHERE species_key=mon.species_key;
     IF t='tackle' THEN n:=40;
     ELSIF t IN('scratch','bite') THEN n:=CASE WHEN mon.level>=9 THEN 60 ELSE 40 END;
     ELSIF t IN('ember','bubble','vine','spark','mud','shade')
       AND t=CASE spec WHEN 'fire' THEN 'ember' WHEN 'water' THEN 'bubble'
          WHEN 'leaf' THEN 'vine' WHEN 'bolt' THEN 'spark' WHEN 'earth' THEN 'mud'
          WHEN 'spirit' THEN 'shade' ELSE '__none' END THEN n:=40;
     ELSE RETURN jsonb_build_object('ok',false,'error','move_not_unlocked'); END IF;
     SELECT base_def INTO defn FROM public.amber_species WHERE species_key=wild.species_key;
     hit_dmg:=greatest(1,floor((n*(mon.level+3)/12.0)*(0.86+random()*0.24)-defn/6.0)::integer);
     IF wild.hp<=hit_dmg THEN
       xp_gain:=sp.exp_yield*wild.level/5;
       SELECT * INTO sp FROM public.amber_species WHERE species_key=mon.species_key;
       xp_gain:=greatest(15,xp_gain);
       UPDATE public.amber_creatures SET exp=exp+xp_gain WHERE id=mon.id;
       SELECT * INTO mon FROM public.amber_creatures WHERE id=mon.id FOR UPDATE;
       WHILE mon.level<100 AND mon.exp >= (mon.level+1)::bigint^3 LOOP
         UPDATE public.amber_creatures SET level=level+1,hp=hp+2 WHERE id=mon.id;
         SELECT * INTO mon FROM public.amber_creatures WHERE id=mon.id FOR UPDATE;
       END LOOP;
       UPDATE public.amber_players SET coins=coins+greatest(20,wild.level*12) WHERE user_id=p_user;
       DELETE FROM public.amber_encounters WHERE owner_id=p_user;
       msg:='battle_win';
     ELSE
       dmg:=greatest(1,ceil((sp.base_atk+wild.level)/13.0)::integer);
       UPDATE public.amber_creatures SET hp=greatest(0,hp-dmg),updated_at=nowt WHERE id=mon.id;
       UPDATE public.amber_encounters SET hp=greatest(0,wild.hp-hit_dmg),
         turns=turns+1,last_turn=nowt WHERE owner_id=p_user;
       msg:='battle_turn';
     END IF;
   END IF;
 ELSIF p_action='market_offer' THEN
   BEGIN selected=(p->>'creature')::uuid;price=(p->>'price')::bigint;
   EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok',false,'error','invalid_offer'); END;
   IF price NOT BETWEEN 1 AND 100000000 THEN RETURN jsonb_build_object('ok',false,'error','invalid_price'); END IF;
   SELECT * INTO mon FROM public.amber_creatures WHERE id=selected AND owner_id=p_user AND status='owned' FOR UPDATE;
   IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','not_your_creature'); END IF;
   IF (SELECT count(*) FROM public.amber_creatures WHERE owner_id=p_user AND status='owned')<=1
      THEN RETURN jsonb_build_object('ok',false,'error','must_keep_one_creature'); END IF;
   UPDATE public.amber_creatures SET status='market',party_slot=NULL,updated_at=nowt WHERE id=selected;
   INSERT INTO public.amber_market(seller_id,creature_id,price_coins) VALUES(p_user,selected,price);
   msg:='offer_created';
 ELSIF p_action='market_take' THEN
   BEGIN target=(p->>'offer')::uuid; EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok',false,'error','invalid_offer'); END;
   SELECT * INTO offer FROM public.amber_market WHERE id=target AND status='open' FOR UPDATE;
   IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','offer_unavailable'); END IF;
   IF offer.seller_id=p_user THEN RETURN jsonb_build_object('ok',false,'error','cannot_buy_own_offer'); END IF;
   -- Acquire player locks in stable UUID order to avoid buyer/seller deadlocks.
   PERFORM 1 FROM public.amber_players WHERE user_id IN (offer.seller_id,p_user) ORDER BY user_id FOR UPDATE;
   SELECT * INTO pl FROM public.amber_players WHERE user_id=p_user FOR UPDATE;
   IF pl.coins<offer.price_coins THEN RETURN jsonb_build_object('ok',false,'error','insufficient_coins'); END IF;
   SELECT * INTO mon FROM public.amber_creatures WHERE id=offer.creature_id AND owner_id=offer.seller_id AND status='market' FOR UPDATE;
   IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','escrow_missing'); END IF;
   UPDATE public.amber_players SET coins=coins-offer.price_coins WHERE user_id=p_user;
   UPDATE public.amber_players SET coins=coins+offer.price_coins WHERE user_id=offer.seller_id;
   UPDATE public.amber_creatures SET owner_id=p_user,status='owned',party_slot=NULL,updated_at=nowt WHERE id=mon.id;
   UPDATE public.amber_market SET status='sold',buyer_id=p_user,closed_at=nowt WHERE id=offer.id;
   UPDATE public.amber_players SET caught=jsonb_set(caught,ARRAY[mon.species_key],'true'::jsonb),
      seen=jsonb_set(seen,ARRAY[mon.species_key],'true'::jsonb) WHERE user_id=p_user;
   msg:='market_purchase_complete';
 ELSIF p_action='market_cancel' THEN
   BEGIN target=(p->>'offer')::uuid; EXCEPTION WHEN others THEN RETURN jsonb_build_object('ok',false,'error','invalid_offer'); END;
   SELECT * INTO offer FROM public.amber_market WHERE id=target AND seller_id=p_user AND status='open' FOR UPDATE;
   IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','not_your_offer'); END IF;
   UPDATE public.amber_market SET status='cancelled',closed_at=nowt WHERE id=offer.id;
   UPDATE public.amber_creatures SET status='owned',updated_at=nowt WHERE id=offer.creature_id AND owner_id=p_user;
   msg:='offer_cancelled';
 END IF;
 UPDATE public.amber_players SET last_active=nowt WHERE user_id=p_user AND last_active<nowt-interval '30 seconds';
 IF p_action NOT IN ('bootstrap','state','market_list','leaderboard') THEN
   INSERT INTO public.amber_event_log(actor_id,event_kind,details)
     VALUES(p_user,p_action,jsonb_build_object('status',msg));
 END IF;
 RETURN jsonb_build_object('ok',true,'message',msg,'data',public.amber_snapshot(p_user));
END $fn$;
REVOKE ALL ON FUNCTION public.amber_action(uuid,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.amber_action(uuid,text,jsonb) TO service_role;
COMMIT;
