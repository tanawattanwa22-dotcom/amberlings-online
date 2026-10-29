'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const actions=[];
const auth={async getUser(){return{data:{user:{id:'10000000-0000-4000-8000-000000000001',email:'tester@example.invalid'}},error:null}},
 async getSession(){return{data:{session:{access_token:'VALID_TEST_JWT'}}}},
 async signInWithOAuth(){return{data:{url:'https://example.invalid/oauth'},error:null}},
 async signOut(){return{error:null}}};
const snapshot={character:{initialized:true,display_name:'ทดสอบ',gender:'m',uniform:0,hair:0,skin:0,
 map_id:'amberton',pos_x:11,pos_y:9,direction:'down',coins:500,gems:60,rating:1000,flags:{starter:true},caught:{embit:true},seen:{embit:true}},
 creatures:[{uid:'20000000-0000-4000-8000-000000000001',species:'embit',level:5,exp:125,hp:20,shiny:false,slot:1,status:'owned'}],
 inventory:{orb:5,potion:3},wild:null,offers:[],leaders:[]};
const win={location:{origin:'https://example.github.io',pathname:'/amberlings-online/'},
 AMBERLINGS_CONFIG:{supabaseUrl:'https://abcdefghijabcdefghij.supabase.co',supabasePublishableKey:'sb_publishable_ABCDEFGHIJKLMNOPQRSTUVWXYZ',apiFunction:'amberlings-api'},
 supabase:{createClient(){return {auth}}}};
const context=vm.createContext({window:win,console,localStorage:{removeItem(){}},fetch:async(url,req)=>{
 const body=JSON.parse(req.body);actions.push({url,req,body});assert.equal(req.headers.Authorization,'Bearer VALID_TEST_JWT');
 return {ok:true,async json(){return {ok:true,message:'ok',data:snapshot}}}
 }});
vm.runInContext(fs.readFileSync('public/online-bridge.js','utf8'),context);
let savefn=null,adopted=null,usedNet=null;
const c={Auth:{acct:null,set(a){this.acct=a}},Net:{use(a){usedNet=a},sim:true},Pay:{},
 newState(o={}){return{party:[],box:[],bag:{},map:'amberton',x:11,y:9,dir:'down',...o}},
 movesAt(){return [{k:'tackle',pp:35}]},species:{embit:['เอมบิท']},items:{orb:{n:'บอล'}},
 getState(){return adopted},setState(s){adopted=s},setReadSave(fn){savefn=fn},
 talk:async()=>{},listMenu:async()=>null,confirm:async()=>false,elementMove:()=> 'ember'};
(async()=>{
 assert.equal(await win.AmberlingsOnline.install(c),true);
 assert.equal(c.Auth.acct.mode,'google');assert.equal(c.Auth.acct.id,'10000000-0000-4000-8000-000000000001');
 assert.equal(adopted.money,500);assert.equal(adopted.party.length,1);assert.equal(adopted.party[0].id,'embit');
 assert.equal(JSON.parse(JSON.stringify(savefn())).money,500);
 adopted.money=999999;adopted.bag.orb=99999;adopted.party[0].lv=100;
 await usedNet.cloudSave({save:'{"money":999999,"gems":999999,"party":[{"id":"amberon"}]}' });
 const request=actions.at(-1).body;
 assert.equal(request.action,'save_view');assert.deepEqual(Object.keys(request.data).sort(),['dir','map','x','y']);
 assert.equal(JSON.stringify(request).includes('999999'),false,'Client forged coins or items were transmitted');
 await usedNet.tradeOffer({mon:{uid:'20000000-0000-4000-8000-000000000001'},price:500});
 assert.equal(actions.at(-1).body.action,'market_offer');
 assert.equal(actions.at(-1).body.data.creature,'20000000-0000-4000-8000-000000000001');
 await usedNet.tradeCancel({id:'30000000-0000-4000-8000-000000000001'});
 assert.equal(actions.at(-1).body.action,'market_cancel');
 assert.equal(c.Pay.adapter!=null,true,'Real-money demo fallback should be disabled online');
 console.log('PASS verified Google account, owner-state hydration, secure cloudSave, market RPC and payment guard');
})().catch(e=>{console.error(e);process.exit(1)});
