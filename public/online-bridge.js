/* Amberlings Online Bridge V0.1
 * Google's OAuth session must be verified by Supabase. No fake Google accounts.
 * Online economy and ownership are SERVER ONLY. Local guest demo remains separate.
 */
(function () {
 'use strict';
 const cfg=window.AMBERLINGS_CONFIG||{};
 const valid=()=>/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(String(cfg.supabaseUrl||''))
   && String(cfg.supabasePublishableKey||'').length>=24;
 let supabase=null,api=null,context=null,lastSnapshot=null;
 let verifiedUser=null;
 function fail(reason){throw new Error(reason)}
 function getSdk(){
   if(!valid())fail('ยังไม่ได้ตั้งค่า Supabase ของโปรเจกต์ Amberlings ใหม่');
   if(!window.supabase?.createClient)fail('โหลด Supabase SDK ไม่สำเร็จ ตรวจอินเทอร์เน็ต');
   if(!supabase){
     supabase=window.supabase.createClient(cfg.supabaseUrl,cfg.supabasePublishableKey,{
       auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}
     });
   }
   return supabase;
 }
 async function apiCall(action,data={}){
   const s=getSdk();
   const session=(await s.auth.getSession()).data.session;
   if(!session?.access_token)fail('ต้องเข้าสู่ระบบ Google ก่อน');
   const response=await fetch(cfg.supabaseUrl+'/functions/v1/'+(cfg.apiFunction||'amberlings-api'),{
     method:'POST',headers:{'Content-Type':'application/json','apikey':cfg.supabasePublishableKey,
       'Authorization':'Bearer '+session.access_token},
     body:JSON.stringify({action,data}),cache:'no-store'
   });
   let body;try{body=await response.json()}catch(_){fail('เซิร์ฟเวอร์ไม่ตอบ JSON')}
   if(!response.ok||!body.ok)fail('เซิร์ฟเวอร์ไม่รับคำสั่ง: '+String(body.error||response.status));
   lastSnapshot=body.data;
   return body;
 }
 function buildMon(c){
   const m={id:c.species,lv:c.level,exp:Number(c.exp),hp:c.hp,st:null,uid:c.uid,
     shiny:c.shiny?1:0,skin:0};
   m.moves=context.movesAt(m.id,m.lv);
   return m;
 }
 function toSave(data){
   if(!data?.character?.initialized)return null;
   const ch=data.character,s=context.newState({name:ch.display_name,g:ch.gender,uni:ch.uniform,
      hair:ch.hair,skin:ch.skin,map:ch.map_id,x:ch.pos_x,y:ch.pos_y,dir:ch.direction,
      money:Number(ch.coins),gems:Number(ch.gems),rating:ch.rating,
      flags:ch.flags||{},caught:ch.caught||{},seen:ch.seen||{}});
   for(const c of data.creatures||[]){const m=buildMon(c);if(c.slot){m._slot=c.slot;s.party.push(m)}else s.box.push(m)}
   s.party.sort((a,b)=>(a._slot||7)-(b._slot||7));
   for(const m of s.party)delete m._slot;
   s.bag=data.inventory||{};
   return s;
 }
 function adopt(data){const save=toSave(data);if(save)context.setState(save);return save}
 async function reload(){const r=await apiCall('state');return adopt(r.data)}
 function adapter(){return {
   async cloudLoad(){const r=await apiCall('state');const s=toSave(r.data);if(!s)throw new Error('ยังไม่มีตัวละครออนไลน์');return {save:JSON.stringify(s)}},
   async cloudSave({save}){
     // We explicitly ignore all money, creature, and item values in the input.
     const cur=context.getState();
     if(!cur)return {ok:true,visualOnly:true};
     try{await apiCall('save_view',{map:cur.map,x:cur.x,y:cur.y,dir:cur.dir});}
     catch(e){console.info('Visual checkpoint was not accepted by the authoritative server',String(e))}
     return {ok:true,visualOnly:true};
   },
   async leaderboard(){const r=await apiCall('leaderboard');return r.data.leaders||[]},
   async tradeList(){const r=await apiCall('market_list');return (r.data.offers||[]).map(o=>({id:o.id,who:o.seller_name,mine:o.mine,price:o.price,
       mon:{id:o.species,lv:o.level,shiny:o.shiny,uid:o.creature_id}}))},
   async tradeOffer({mon,price}){return apiCall('market_offer',{creature:mon.uid,price:price||500})},
   async tradeTake({id}){return apiCall('market_take',{offer:id})},
   async tradeCancel({id}){return apiCall('market_cancel',{offer:id})},
   async createCharacter(data){return apiCall('create_character',data)},
   async travel({map}){return apiCall('travel',{map})},
   async grantStarter({species}){return apiCall('starter',{species})},
   async buy({item,quantity}){return apiCall('shop_buy',{item,quantity})},
   async daily(){return apiCall('daily')},
   async heal({creature}){return apiCall('heal',{creature})},
   async evolve({creature}){return apiCall('evolve',{creature})},
   async team({creature,slot}){return apiCall('team',{creature,slot})},
   async wildStart(){return apiCall('wild_start')},
   async wildAttack({move}){return apiCall('wild_attack',{move})},
   async wildCapture({orb}){return apiCall('wild_capture',{orb})},
   async wildRun(){return apiCall('wild_run')}
 }}
 async function login(){
   const s=getSdk();
   const callback=window.location.origin+window.location.pathname;
   const {data,error}=await s.auth.signInWithOAuth({provider:'google',
     options:{redirectTo:callback,skipBrowserRedirect:false}});
   if(error)throw error;
   if(data?.url)window.location.assign(data.url);
   // Navigation is now underway. Do not create a temporary fake account.
   return new Promise(()=>{});
 }
 async function logout(){const s=getSdk();const {error}=await s.auth.signOut();if(error)throw error;verifiedUser=null;lastSnapshot=null}
 async function install(c){
   context=c;
   const {Auth,Net,Pay}=c;
   // This adapter is present even if setup is missing, to prevent the old fake-Google path.
   Auth.adapter={signIn:login,signOut:logout};
   if(!valid()){
     console.info('Amberlings: NEW Supabase project is not configured. Guest demo is available.');
     return false;
   }
   try{
     const s=getSdk();
     const {data,error}=await s.auth.getUser();
     if(error||!data?.user){
       if(Auth.acct?.mode==='google'){
         Auth.acct=null;try{localStorage.removeItem('amberlings_auth')}catch(_){}
       }
       return false;
     }
     verifiedUser=data.user;
     if(Pay)Pay.adapter={charge:async()=>fail('ยังไม่เปิดรับชำระเงินจริงใน Amberlings Online')};
     const {data:serverData}=await apiCall('bootstrap');
     const a={mode:'google',id:verifiedUser.id,name:serverData.character?.display_name||'นักเดินทาง',
       email:verifiedUser.email};
     Auth.set(a,true);
     api=adapter();Net.use(api);Net.sim=false;
     Net.auto=false; // No arbitrary browser save is EVER uploaded to the database.
     const save=toSave(serverData);
     c.setReadSave(()=>toSave(lastSnapshot)||null);
     if(save)c.setState(save);
     return true;
   }catch(e){
     console.warn('Amberlings sign in/configuration failure:',String(e));
     return false;
   }
 }
 async function createCharacter(o){
   const r=await apiCall('create_character',{name:o.name,gender:o.g,uniform:o.uni,hair:o.hair,skin:o.skin});
   const save=toSave(r.data);if(save)context.setState(save);
   context.setReadSave(()=>toSave(lastSnapshot)||null);
   return save;
 }
 async function starter(species){
   const r=await apiCall('starter',{species});const save=toSave(r.data);if(save)context.setState(save);
   context.setReadSave(()=>toSave(lastSnapshot)||null);return save;
 }
 async function shopUI(){
   if(!verifiedUser)return false;
   const c=context;
   for(;;){
     const item=await c.listMenu([
       {label:'ออร์บอำพัน',sub:'100 เหรียญ',val:'orb'},
       {label:'ออร์บเงิน',sub:'250 เหรียญ',val:'silver'},
       {label:'ออร์บทอง',sub:'600 เหรียญ',val:'gold'},
       {label:'ยาฟื้นฟู',sub:'80 เหรียญ',val:'potion'},
       {label:'ยาฟื้นฟูพิเศษ',sub:'200 เหรียญ',val:'super'}
     ],{title:'ร้านค้าของเซิร์ฟเวอร์',style:{left:'8px',right:'8px',top:'8px'}});
     if(!item)return;
     const quantity=await c.listMenu([1,5,10].map(n=>({label:'×'+n,val:n})),{
       title:'เลือกจำนวน',style:{right:'8px',top:'30px',width:'85px'}});
     if(!quantity)continue;
     try{const r=await apiCall('shop_buy',{item,quantity});adopt(r.data);await c.talk(['ซื้อจากเซิร์ฟเวอร์สำเร็จ'])}
     catch(e){await c.talk([String(e.message)])}
   }
 }
 async function marketUI(){
   if(!verifiedUser)return false;
   const c=context;
   for(;;){
     const op=await c.listMenu([
       {label:'ดูรายการขายมอน',val:'list'},
       {label:'ฝากมอนของฉันขาย',val:'offer'},
       {label:'ยกเลิกรายการของฉัน',val:'cancel'},
       {label:'รับรางวัลรายวันจากเซิร์ฟเวอร์',val:'daily'}
     ],{title:'ตลาดแลกมอนออนไลน์จริง',style:{left:'8px',right:'8px',top:'8px'}});
     if(!op)return;
     try{
       if(op==='daily'){const r=await apiCall('daily');adopt(r.data);await c.talk(['รับเหรียญและออร์บรายวันจากเซิร์ฟเวอร์แล้ว']);continue;}
       if(op==='offer'){
         const available=(lastSnapshot?.creatures||[]).filter(x=>x.status==='owned');
         if(available.length<=1){await c.talk(['ต้องมีมอนมากกว่า 1 ตัวจึงจะฝากขายได้']);continue}
         const i=await c.listMenu(available.map(x=>({label:c.species[x.species]?.[0]+' Lv'+x.level,
           sub:x.slot?'ทีม':'กล่อง',val:x.uid})),{title:'เลือกมอนเพื่อขาย',style:{left:'8px',right:'8px',top:'8px'}});
         if(!i)continue;
         const price=await c.listMenu([100,250,500,1000,2500,5000,10000].map(n=>({label:n+' เหรียญ',val:n})),
           {title:'ราคาขาย',style:{left:'8px',right:'8px',top:'8px'}});
         if(!price)continue;
         const r=await apiCall('market_offer',{creature:i,price});adopt(r.data);
         await c.talk(['ลงขายแล้ว มอนถูกเก็บไว้ใน Escrow ของเซิร์ฟเวอร์']);
       }else{
         const r=await apiCall('market_list');
         const offers=(r.data.offers||[]).filter(x=>op==='cancel'?x.mine:!x.mine);
         if(!offers.length){await c.talk(['ยังไม่มีรายการที่เลือก']);continue}
         const id=await c.listMenu(offers.map(x=>({label:(c.species[x.species]?.[0]||x.species)+' Lv'+x.level,
           sub:x.price+' เหรียญ · '+x.seller_name,val:x.id})),
           {title:op==='cancel'?'ยกเลิกประกาศของฉัน':'ซื้อขายกับผู้เล่น',style:{left:'8px',right:'8px',top:'8px'},max:140});
         if(!id)continue;
         const offer=offers.find(x=>x.id===id);
         if(!await c.confirm(offer))continue;
         const end=await apiCall(op==='cancel'?'market_cancel':'market_take',{offer:id});
         adopt(end.data);
         await c.talk([op==='cancel'?'ยกเลิกและคืนมอนแล้ว':'ซื้อสำเร็จ โอนเจ้าของมอนกับเหรียญผ่านเซิร์ฟเวอร์แล้ว']);
       }
     }catch(e){await c.talk([String(e.message)])}
   }
 }
 async function teamUI(){
   const c=context;
   for(;;){
     const owned=(lastSnapshot?.creatures||[]).filter(x=>x.status==='owned');
     if(!owned.length){await c.talk(['ยังไม่มีมอนในบัญชีออนไลน์']);return}
     const uid=await c.listMenu(owned.map(m=>({label:(c.species[m.species]?.[0]||m.species)+' Lv'+m.level,
       sub:m.slot?'ช่องทีม '+m.slot:'กล่อง',val:m.uid})),{title:'ทีมมอนบนเซิร์ฟเวอร์',style:{left:'8px',right:'8px',top:'8px'}});
     if(!uid)return;
     const slot=await c.listMenu([{label:'ส่งเข้ากล่อง',val:0},...Array.from({length:6},(_,i)=>({label:'ช่องทีม '+(i+1),val:i+1}))],
       {title:'จัดตำแหน่งทีม',style:{left:'8px',right:'8px',top:'8px'}});
     if(slot===null)return;
     try{const r=await apiCall('team',{creature:uid,slot});adopt(r.data);await c.talk(['บันทึกทีมบนเซิร์ฟเวอร์แล้ว']);}
     catch(e){await c.talk([String(e.message)])}
   }
 }
 async function bagUI(){
   const c=context;
   const inv=lastSnapshot?.inventory||{};
   const items=Object.entries(inv).filter(([,n])=>Number(n)>0);
   if(!items.length){await c.talk(['ยังไม่มีไอเทมในกระเป๋าออนไลน์']);return}
   const pick=await c.listMenu(items.map(([k,n])=>({label:c.items[k]?.n||k,sub:'×'+n,val:k})),
     {title:'กระเป๋าออนไลน์',style:{left:'8px',right:'8px',top:'8px'}});
   if(!pick)return;
   if(pick!=='potion'){await c.talk(['ไอเทมนี้ยังไม่มีคำสั่งใช้บนเซิร์ฟเวอร์ จึงไม่หักของจากมือถือ']);return}
   const mons=(lastSnapshot?.creatures||[]).filter(x=>x.status==='owned'&&x.slot);
   const uid=await c.listMenu(mons.map(x=>({label:(c.species[x.species]?.[0]||x.species)+' Lv'+x.level,
     sub:'HP '+x.hp,val:x.uid})),{title:'รักษามอนตัวไหน?',style:{left:'8px',right:'8px',top:'8px'}});
   if(!uid)return;
   try{const r=await apiCall('heal',{creature:uid});adopt(r.data);await c.talk(['ใช้ยาจากเซิร์ฟเวอร์สำเร็จ']);}
   catch(e){await c.talk([String(e.message)])}
 }
 async function daily(){const r=await apiCall('daily');adopt(r.data);return r}
 // Wild encounters are currently enabled through a secure, menu-based flow;
 // the original client-calculated battle must NEVER be trusted for persistent loot.
 async function onlineWildBattle(){
   const c=context;
   try{
     let r=await apiCall('wild_start');
     await c.talk(['พบมอนป่า '+(c.species[r.data.wild.species_key]?.[0]||r.data.wild.species_key)+' Lv'+r.data.wild.level]);
     while(r.data.wild){
       const w=r.data.wild;
       const sel=await c.listMenu([
         {label:'⚔️ โจมตี',sub:'HP '+w.hp+'/'+w.max_hp,val:'tackle'},
         {label:'🔥 ท่าธาตุ',val:c.elementMove()},
         {label:'🟠 ออร์บอำพัน',val:'orb'},
         {label:'◀ หนี',val:'run'}
       ],{title:'ต่อสู้บนเซิร์ฟเวอร์',style:{left:'8px',right:'8px',bottom:'8px'}});
       if(!sel||sel==='run'){r=await apiCall('wild_run');break}
       if(sel==='orb')r=await apiCall('wild_capture',{orb:'orb'});
       else r=await apiCall('wild_attack',{move:sel});
       adopt(r.data);
       if(r.message==='capture_success')await c.talk(['จับมอนสำเร็จแล้ว! บันทึกลงฐานข้อมูลจริง']);
       else if(r.message==='battle_win')await c.talk(['ชนะการต่อสู้! ได้ EXP และเหรียญจากเซิร์ฟเวอร์']);
       else if(r.message==='capture_failed')await c.talk(['มอนดิ้นหลุด!']);
       if(r.message==='battle_turn' && !(r.data.creatures||[]).some(x=>x.hp>0&&x.slot)){
         await c.talk(['มอนหมดแรงแล้ว ต้องรักษาก่อน']);
         await apiCall('wild_run');break;
       }
     }
     adopt(r.data);
   }catch(e){await c.talk(['การต่อสู้ไม่สำเร็จ: '+String(e.message)])}
   return 'online';
 }
 window.AmberlingsOnline={install,createCharacter,starter,reload,shopUI,marketUI,teamUI,bagUI,daily,onlineWildBattle,
   get online(){return !!verifiedUser},get configured(){return valid()},get snapshot(){return lastSnapshot}};
})();
