-- AMBERLINGS ONLINE / brand-new isolated Supabase project.
-- DO NOT EXECUTE AGAINST 55 AMBERLANDS OR AMBER WORLD CLASS.
-- All progression/economy tables are server-owned: web clients have SELECT-only RLS.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TABLE IF NOT EXISTS public.amber_species (
  species_key text PRIMARY KEY CHECK (species_key ~ '^[a-z]{3,30}$'),
  name_th text NOT NULL,
  element text NOT NULL CHECK (element IN ('fire','water','leaf','bolt','earth','spirit','normal')),
  base_hp smallint NOT NULL, base_atk smallint NOT NULL, base_def smallint NOT NULL, base_spd smallint NOT NULL,
  evolves_to text REFERENCES public.amber_species(species_key) DEFERRABLE INITIALLY DEFERRED,
  evolve_at smallint NOT NULL DEFAULT 0,
  capture_rate smallint NOT NULL CHECK (capture_rate BETWEEN 1 AND 255),
  exp_yield smallint NOT NULL,
  description_th text NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS public.amber_items_catalog (
  item_key text PRIMARY KEY CHECK(item_key ~ '^[a-z_]{2,40}$'),
  name_th text NOT NULL, category text NOT NULL CHECK(category IN ('orb','med','utility')),
  price_coins integer NOT NULL CHECK(price_coins>=0),
  capture_multiplier numeric(5,2),heal_amount smallint
);
CREATE TABLE IF NOT EXISTS public.amber_players (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  initialized boolean NOT NULL DEFAULT false,
  display_name text NOT NULL DEFAULT 'นักเดินทาง' CHECK(char_length(display_name) BETWEEN 2 AND 22),
  gender text NOT NULL DEFAULT 'm' CHECK(gender IN ('m','f')),
  uniform smallint NOT NULL DEFAULT 0 CHECK(uniform BETWEEN 0 AND 3),
  hair smallint NOT NULL DEFAULT 0 CHECK(hair BETWEEN 0 AND 4),
  skin smallint NOT NULL DEFAULT 0 CHECK(skin BETWEEN 0 AND 2),
  map_id text NOT NULL DEFAULT 'amberton',
  pos_x smallint NOT NULL DEFAULT 11 CHECK(pos_x BETWEEN 0 AND 60),
  pos_y smallint NOT NULL DEFAULT 9 CHECK(pos_y BETWEEN 0 AND 60),
  direction text NOT NULL DEFAULT 'down' CHECK(direction IN('down','up','left','right')),
  coins bigint NOT NULL DEFAULT 500 CHECK(coins BETWEEN 0 AND 1000000000),
  gems bigint NOT NULL DEFAULT 60 CHECK(gems BETWEEN 0 AND 1000000000),
  rating integer NOT NULL DEFAULT 1000 CHECK(rating BETWEEN 0 AND 1000000),
  flags jsonb NOT NULL DEFAULT '{}'::jsonb,
  caught jsonb NOT NULL DEFAULT '{}'::jsonb,
  seen jsonb NOT NULL DEFAULT '{}'::jsonb,
  last_daily date,
  last_active timestamptz NOT NULL DEFAULT now(),
  last_move timestamptz NOT NULL DEFAULT 'epoch',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.amber_creatures (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  species_key text NOT NULL REFERENCES public.amber_species(species_key),
  level smallint NOT NULL DEFAULT 1 CHECK(level BETWEEN 1 AND 100),
  exp bigint NOT NULL DEFAULT 1 CHECK(exp >= 0),
  hp integer NOT NULL DEFAULT 1 CHECK(hp >= 0),
  shiny boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'owned' CHECK(status IN('owned','market')),
  party_slot smallint CHECK(party_slot BETWEEN 1 AND 6),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK(status='owned' OR party_slot IS NULL)
);
CREATE UNIQUE INDEX IF NOT EXISTS amber_party_slot_unique ON public.amber_creatures(owner_id,party_slot) WHERE party_slot IS NOT NULL;
CREATE INDEX IF NOT EXISTS amber_creatures_owner ON public.amber_creatures(owner_id);
CREATE TABLE IF NOT EXISTS public.amber_inventory (
  owner_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  item_key text NOT NULL REFERENCES public.amber_items_catalog(item_key),
  quantity integer NOT NULL DEFAULT 0 CHECK(quantity BETWEEN 0 AND 1000000),
  PRIMARY KEY(owner_id,item_key)
);
CREATE TABLE IF NOT EXISTS public.amber_encounters (
  owner_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  species_key text NOT NULL REFERENCES public.amber_species(species_key),
  level smallint NOT NULL CHECK(level BETWEEN 1 AND 100),
  max_hp integer NOT NULL CHECK(max_hp >= 1),
  hp integer NOT NULL CHECK(hp >= 0),
  turns smallint NOT NULL DEFAULT 0 CHECK(turns BETWEEN 0 AND 300),
  started_at timestamptz NOT NULL DEFAULT now(),
  last_turn timestamptz NOT NULL DEFAULT 'epoch'
);
CREATE TABLE IF NOT EXISTS public.amber_market (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  buyer_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  creature_id uuid NOT NULL REFERENCES public.amber_creatures(id),
  price_coins bigint NOT NULL CHECK(price_coins BETWEEN 1 AND 100000000),
  status text NOT NULL DEFAULT 'open' CHECK(status IN('open','sold','cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  closed_at timestamptz
);
CREATE INDEX IF NOT EXISTS amber_market_open ON public.amber_market(created_at DESC) WHERE status='open';
CREATE UNIQUE INDEX IF NOT EXISTS amber_market_active_creature ON public.amber_market(creature_id) WHERE status='open';
CREATE TABLE IF NOT EXISTS public.amber_event_log (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  event_kind text NOT NULL,
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS amber_event_log_actor_time ON public.amber_event_log(actor_id,created_at DESC);
-- Prevent web clients from changing money, creatures, inventory or trades directly.
REVOKE ALL ON public.amber_species,public.amber_items_catalog,public.amber_players,public.amber_creatures,
  public.amber_inventory,public.amber_encounters,public.amber_market,public.amber_event_log FROM PUBLIC,anon,authenticated;
GRANT ALL ON public.amber_species,public.amber_items_catalog,public.amber_players,public.amber_creatures,
  public.amber_inventory,public.amber_encounters,public.amber_market,public.amber_event_log TO service_role;
GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO service_role;
GRANT SELECT ON public.amber_species,public.amber_items_catalog,public.amber_players,public.amber_creatures,
  public.amber_inventory,public.amber_encounters,public.amber_market TO authenticated;
ALTER TABLE public.amber_species ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.amber_items_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.amber_players ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.amber_creatures ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.amber_inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.amber_encounters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.amber_market ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.amber_event_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY amber_species_read ON public.amber_species FOR SELECT TO authenticated USING(true);
CREATE POLICY amber_item_catalog_read ON public.amber_items_catalog FOR SELECT TO authenticated USING(true);
CREATE POLICY amber_player_self_read ON public.amber_players FOR SELECT TO authenticated USING(user_id=(select auth.uid()));
CREATE POLICY amber_creature_self_read ON public.amber_creatures FOR SELECT TO authenticated USING(owner_id=(select auth.uid()));
CREATE POLICY amber_inventory_self_read ON public.amber_inventory FOR SELECT TO authenticated USING(owner_id=(select auth.uid()));
CREATE POLICY amber_encounter_self_read ON public.amber_encounters FOR SELECT TO authenticated USING(owner_id=(select auth.uid()));
CREATE POLICY amber_market_read ON public.amber_market FOR SELECT TO authenticated USING(status='open' OR seller_id=(select auth.uid()) OR buyer_id=(select auth.uid()));
COMMIT;

-- Original 25 Amberlings creature species; only first-generation playable content.
INSERT INTO public.amber_species(species_key,name_th,element,base_hp,base_atk,base_def,base_spd,evolves_to,evolve_at,capture_rate,exp_yield,description_th) VALUES
 ('embit','เอมบิท','fire','42','52','40','62','flarix','16','45','64','ลูกจิ้งจอกไฟ หางมีเปลวเล็กๆ ที่ลุกเมื่อดีใจ'),
 ('flarix','ฟลาริกซ์','fire','60','68','56','78','infernox','36','45','142','เปลวบนหางลุกโชนตามอารมณ์ วิ่งเร็วเหมือนลมร้อน'),
 ('infernox','อินเฟอร์น็อกซ์','fire','80','92','76','98',NULL,'0','45','240','แผงคอเพลิงเผาได้ทั้งทุ่ง แต่ใจดีกับคนที่เลี้ยงมา'),
 ('aquip','อควิป','water','48','46','48','50','tidalon','16','45','64','ซาลาแมนเดอร์น้ำ เหงือกสีชมพูโบกไหวตอนว่ายน้ำ'),
 ('tidalon','ไทดาลอน','water','66','62','64','60','leviathor','36','45','142','ครีบหลังสร้างกระแสน้ำเล็กๆ ล้อมตัวไว้'),
 ('leviathor','เลวีอาธอร์','water','88','84','90','74',NULL,'0','45','240','เจ้าแห่งอ่าว เปลือกสีคราม สะบัดครีบเกิดคลื่นยักษ์'),
 ('sproutle','สเปราต์เทิล','leaf','50','48','50','46','thornyx','16','45','64','ลูกกวางตัวน้อย ใบอ่อนบนหัวชอบอาบแดดตอนเช้า'),
 ('thornyx','ธอร์นนิกซ์','leaf','68','64','66','58','florabeast','36','45','142','หนามบนหลังงอกตามฤดู ใช้ป้องกันตัวอย่างว่องไว'),
 ('florabeast','ฟลอราบีสต์','leaf','92','82','88','68',NULL,'0','45','240','สวนดอกไม้เคลื่อนที่ ที่ใดมันเดินผ่านที่นั่นเบ่งบาน'),
 ('zipbat','ซิปแบต','bolt','36','42','36','70','voltbat','15','190','58','ค้างคาวไฟฟ้า ปีกเรืองแสงในถ้ำมืด'),
 ('voltbat','โวลต์แบต','bolt','54','60','52','92','stormbat','34','120','140','กางปีกสร้างประกายไฟฟ้าสถิต ชอบร่อนก่อนพายุมา'),
 ('stormbat','สตอร์มแบต','bolt','74','82','70','118',NULL,'0','45','230','เรียกเมฆพายุได้ด้วยเสียงร้องเดียว'),
 ('pebblo','เพบโบล','earth','46','54','64','24','boulderon','20','190','60','ก้อนหินเล็กที่ตื่นเมื่อมีคนเดินผ่าน ตาเหลืองเป็นประกาย'),
 ('boulderon','บอลเดอรอน','earth','64','76','86','34','golemaw','38','120','140','ยักษ์หินผู้ขี้อาย ถ้าตกใจจะม้วนตัวกลิ้ง'),
 ('golemaw','โกเลมอว์','earth','90','100','112','40',NULL,'0','45','235','ผลึกบนหลังเก็บพลังจากใจกลางภูเขา'),
 ('wispy','วิสปี','spirit','38','40','40','56','phantora','18','190','60','เปลวผีลอยละล่องในถ้ำ ชอบหยอกคนที่ไม่กล้า'),
 ('phantora','แฟนทอร่า','spirit','56','60','56','74','nightveil','36','120','140','เจ้าของเปลวสองมือ จุดไฟล่อให้หลงทาง'),
 ('nightveil','ไนท์เวล','spirit','72','86','70','102',NULL,'0','45','235','ผ้าคลุมแห่งราตรี ปรากฏเมื่อดวงจันทร์ดับ'),
 ('fluffo','ฟลัฟโฟ','normal','48','44','40','56','lunabun','18','255','56','กระต่ายปุยนุ่ม หางกลมเหมือนก้อนเมฆ'),
 ('lunabun','ลูนาบัน','normal','72','66','62','84',NULL,'0','120','138','ผลึกจันทร์บนหลังเรืองแสงในคืนเดือนเพ็ญ'),
 ('fluttr','ฟลัตเตอร์','leaf','40','36','40','60','mothara','14','255','52','ผีเสื้อใบไม้ ปีกบางเหมือนใบอ่อน'),
 ('mothara','โมทาร่า','leaf','62','64','60','86',NULL,'0','120','136','ลายตาบนปีกทำให้ศัตรูลังเล'),
 ('shelkrab','เชลคราบ','water','44','56','68','30','clawdor','22','190','62','ปูเกราะแดง ก้ามใหญ่กว่าตัว'),
 ('clawdor','คลอว์ดอร์','water','70','86','100','44',NULL,'0','120','142','ก้ามน้ำเงินหนักพอจะทุบหินแตก'),
 ('amberon','แอมเบอรอน','fire','100','110','90','100',NULL,'0','3','300','สัตว์ในตำนานแห่งแสงอำพัน ปีกทองส่องทั่วภูเขา')
ON CONFLICT(species_key) DO NOTHING;
INSERT INTO public.amber_items_catalog(item_key,name_th,category,price_coins,capture_multiplier,heal_amount) VALUES
 ('orb','ออร์บอำพัน','orb','100','1.0',NULL),
 ('silver','ออร์บเงิน','orb','250','1.5',NULL),
 ('gold','ออร์บทอง','orb','600','2.4',NULL),
 ('potion','ยาฟื้นฟู','med','80',NULL,'25'),
 ('super','ยาฟื้นฟูพิเศษ','med','200',NULL,'70'),
 ('hyper','ยาฟื้นฟูสูงสุด','med','500',NULL,'160'),
 ('revive','ผลึกชุบชีวิต','med','800',NULL,NULL),
 ('cure','ยาแก้สถานะ','med','150',NULL,NULL),
 ('candy','ลูกกวาดอำพัน','utility','0',NULL,NULL)
ON CONFLICT(item_key) DO NOTHING;
