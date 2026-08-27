
const SUPABASE_URL='https://fbmkrbmhacvxhduqkvzc.supabase.co';
const SUPABASE_PUBLISHABLE_KEY='sb_publishable_jKpCWh2e_B2FVDcGXpLC7A_YJlYi-J6';
const CLOUD_QUEUE_KEY='fcc_v12_cloud_queue';

const sb=(window.supabase&&window.supabase.createClient)
  ? window.supabase.createClient(SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY,{
      auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}
    })
  : null;

let cloudUser=null;
let householdId=null;
let cloudReady=false;
let cloudLoading=false;
let realtimeChannel=null;
let reloadTimer=null;

function cloudQueue(){try{return JSON.parse(localStorage.getItem(CLOUD_QUEUE_KEY)||'[]')}catch(e){return []}}
function saveCloudQueue(q){localStorage.setItem(CLOUD_QUEUE_KEY,JSON.stringify(q))}
function setCloudStatus(mode,text){
  const p=document.getElementById('cloudPill'),t=document.getElementById('cloudStatus');
  if(!p||!t)return;
  p.className='cloud-pill'+(mode?' '+mode:'');
  t.textContent=text;
}
function showCloudBanner(text=''){
  const b=document.getElementById('cloudBanner'); if(!b)return;
  b.textContent=text; b.classList.toggle('show',!!text);
}
function setAuthUI(){
  const b=document.getElementById('authButton'); if(!b)return;
  if(cloudUser){b.textContent='חשבון / סנכרון';b.onclick=openCloudAccount}
  else{b.textContent='כניסה לענן';b.onclick=openAuth}
}
function cloudErrorText(e){
  const m=String(e?.message||e||'');
  if(/table|relation|schema cache|PGRST205/i.test(m))
    return 'החיבור ל‑Supabase קיים, אבל טבלאות המערכת עדיין לא הוקמו. הרץ פעם אחת את supabase_schema_v12.sql ב‑SQL Editor של הפרויקט.';
  return m||'שגיאת Supabase לא ידועה';
}
function hasLocalData(){
  return ['transactions','accounts','holdings','watchlist','retirement','goals']
    .some(k=>Array.isArray(state[k])&&state[k].length);
}
function remoteHasData(x){
  return ['transactions','accounts','holdings','watchlist','retirement','goals']
    .some(k=>Array.isArray(x[k])&&x[k].length);
}

const cloudMap={
 transactions:{
  table:'transactions',
  toDb:x=>({id:x.id,household_id:householdId,txn_date:x.date,kind:x.kind,amount:Number(x.amount||0),description:x.desc,category:x.category||'אחר',nature:x.nature||'variable',is_saving:!!x.saving,status:x.status||'actual'}),
  fromDb:x=>({id:x.id,date:x.txn_date,kind:x.kind,amount:Number(x.amount),desc:x.description,category:x.category,nature:x.nature,saving:x.is_saving,status:x.status})
 },
 accounts:{
  table:'accounts',
  toDb:x=>({id:x.id,household_id:householdId,name:x.name,type:x.type,value:Number(x.value||0),owner_name:x.owner||'',provider:x.provider||'',note:x.note||'',monthly_payment:Number(x.monthlyPayment||0),interest_rate:Number(x.interest||0)}),
  fromDb:x=>({id:x.id,name:x.name,type:x.type,value:Number(x.value),owner:x.owner_name||'',provider:x.provider||'',note:x.note||'',monthlyPayment:Number(x.monthly_payment||0),interest:Number(x.interest_rate||0)})
 },
 holdings:{
  table:'holdings',
  toDb:x=>({id:x.id,household_id:householdId,ticker:x.ticker,name:x.name||'',units:Number(x.units||0),avg_cost:Number(x.avgCost||0),current_price:Number(x.price||0),currency:x.currency||'USD',fx_to_ils:Number(x.fx||1),asset_class:x.assetClass||'',region:x.region||'',sector:x.sector||''}),
  fromDb:x=>({id:x.id,ticker:x.ticker,name:x.name||'',units:Number(x.units),avgCost:Number(x.avg_cost),price:Number(x.current_price),currency:x.currency,fx:Number(x.fx_to_ils||1),assetClass:x.asset_class||'',region:x.region||'',sector:x.sector||''})
 },
 watchlist:{
  table:'watchlist',
  toDb:x=>({id:x.id,household_id:householdId,ticker:x.ticker,name:x.name||'',current_price:Number(x.current||0),target_price:Number(x.target||0),status:x.status||'מחקר',thesis:x.thesis||'',quality_score:Number(x.qualityScore||0),growth_score:Number(x.growthScore||0),valuation_score:Number(x.valuationScore||0)}),
  fromDb:x=>({id:x.id,ticker:x.ticker,name:x.name||'',current:Number(x.current_price),target:Number(x.target_price),status:x.status,thesis:x.thesis||'',qualityScore:Number(x.quality_score||0),growthScore:Number(x.growth_score||0),valuationScore:Number(x.valuation_score||0)})
 },
 retirement:{
  table:'retirement_products',
  toDb:x=>({id:x.id,household_id:householdId,name:x.name,owner_name:x.owner||'',provider:x.provider||'',balance:Number(x.balance||0),monthly_deposit:Number(x.monthlyDeposit||0),fee_assets:Number(x.feeAssets||0),fee_deposit:Number(x.feeDeposit||0),track:x.track||'',expected_return:Number(x.expectedReturn||state.settings.baseReturn)}),
  fromDb:x=>({id:x.id,name:x.name,owner:x.owner_name||'',provider:x.provider||'',balance:Number(x.balance),monthlyDeposit:Number(x.monthly_deposit),feeAssets:Number(x.fee_assets),feeDeposit:Number(x.fee_deposit),track:x.track||'',expectedReturn:Number(x.expected_return||state.settings.baseReturn)})
 },
 goals:{
  table:'goals',
  toDb:x=>({id:x.id,household_id:householdId,name:x.name,icon:x.icon||'🎯',target_amount:Number(x.target||0),saved_amount:Number(x.saved||0),target_date:x.date,priority:x.priority||'בינונית'}),
  fromDb:x=>({id:x.id,name:x.name,icon:x.icon||'🎯',target:Number(x.target_amount),saved:Number(x.saved_amount),date:x.target_date,priority:x.priority})
 }
};

function settingsToDb(x){
 return {household_id:householdId,target_savings_rate:Number(x.targetSavingsRate),emergency_months:Number(x.emergencyMonths),current_age:Number(x.currentAge),retirement_age:Number(x.retirementAge),low_return:Number(x.lowReturn),base_return:Number(x.baseReturn),high_return:Number(x.highReturn),inflation:Number(x.inflation)}
}
function settingsFromDb(x){
 return {...defaults.settings,targetSavingsRate:Number(x.target_savings_rate),emergencyMonths:Number(x.emergency_months),currentAge:Number(x.current_age),retirementAge:Number(x.retirement_age),lowReturn:Number(x.low_return),baseReturn:Number(x.base_return),highReturn:Number(x.high_return),inflation:Number(x.inflation)}
}

function queueCloud(op){
  const q=cloudQueue();
  if(op.op==='upsert'){
    for(let i=q.length-1;i>=0;i--){
      if(q[i].op==='upsert'&&q[i].key===op.key&&q[i].item?.id===op.item?.id){q.splice(i,1);break}
    }
  }
  q.push(op); saveCloudQueue(q);
  if(cloudReady&&navigator.onLine)flushCloudQueue().catch(()=>{});
}

/* Wrap the existing local-first functions. */
const localUpsert=upsert;
upsert=function(key,item){
  localUpsert(key,item);
  queueCloud({op:'upsert',key,item:structuredClone(item)});
};

const localDel=del;
del=function(key,id){
  const before=state[key]?.length||0;
  localDel(key,id);
  if((state[key]?.length||0)<before)queueCloud({op:'delete',key,id});
};

const localSaveSettings=saveSettings;
saveSettings=function(){
  localSaveSettings();
  queueCloud({op:'settings',item:structuredClone(state.settings)});
};

const localResetAll=resetAll;
resetAll=async function(){
  if(cloudReady){
    if(!confirm('למחוק את כל הנתונים גם מהמכשיר וגם מהענן?'))return;
    try{await clearRemoteState()}catch(e){alert('מחיקת הענן נכשלה: '+cloudErrorText(e));return}
    state=structuredClone(defaults); saveCloudQueue([]); persist(); closeModal(); render();
  }else{
    localResetAll();
  }
};

async function openAuth(){
 if(!sb)return alert('ספריית Supabase לא נטענה. בדוק חיבור לאינטרנט.');
 openModal('כניסה ל‑Financial Control Center',`
 <div class="auth-card">
  <div class="auth-switch">
   <button id="loginTab" class="active" onclick="switchAuth('login')">כניסה</button>
   <button id="signupTab" onclick="switchAuth('signup')">יצירת חשבון</button>
  </div>
  <div class="field"><label>אימייל</label><input id="authEmail" type="email" autocomplete="email" placeholder="name@example.com"></div>
  <div class="field"><label>סיסמה</label><input id="authPassword" type="password" autocomplete="current-password" placeholder="לפחות 8 תווים"></div>
  <input id="authMode" type="hidden" value="login">
  <button id="authSubmit" class="btn primary" onclick="submitAuth()">כניסה</button>
  <div class="auth-note">החשבון משמש לסנכרון בין מכשירים. האפליקציה משתמשת רק ב‑Publishable Key הציבורי וב‑RLS כדי להגביל את הנתונים למשתמש/משפחה המחוברים.</div>
 </div>`);
}
function switchAuth(mode){
 document.getElementById('authMode').value=mode;
 document.getElementById('loginTab').classList.toggle('active',mode==='login');
 document.getElementById('signupTab').classList.toggle('active',mode==='signup');
 document.getElementById('authSubmit').textContent=mode==='login'?'כניסה':'יצירת חשבון';
}
async function submitAuth(){
 const email=document.getElementById('authEmail').value.trim();
 const password=document.getElementById('authPassword').value;
 const mode=document.getElementById('authMode').value;
 if(!email||password.length<8)return alert('יש להזין אימייל וסיסמה של לפחות 8 תווים.');
 const b=document.getElementById('authSubmit'); b.disabled=true; b.textContent='מתחבר...';
 try{
  const r=mode==='signup'
    ? await sb.auth.signUp({email,password})
    : await sb.auth.signInWithPassword({email,password});
  if(r.error)throw r.error;
  if(mode==='signup'&&!r.data.session){
   alert('החשבון נוצר. אם אישור אימייל פעיל ב‑Supabase, אשר את ההודעה שקיבלת ואז חזור לאפליקציה ובצע כניסה.');
   closeModal();
  }else closeModal();
 }catch(e){alert('הפעולה נכשלה: '+cloudErrorText(e))}
 finally{if(document.getElementById('authSubmit')){b.disabled=false;b.textContent=mode==='login'?'כניסה':'יצירת חשבון'}}
}
function openCloudAccount(){
 openModal('חשבון וסנכרון',`
 <div class="auth-card">
  <div class="color-stat green"><b>${esc(cloudUser?.email||'')}</b><div class="small muted">מחובר ל‑Supabase</div></div>
  <div class="sync-row"><span>סטטוס</span><b>${cloudReady?'☁️ מסונכרן':'🔄 מתחבר'}</b></div>
  <div class="actions">
   <button class="btn primary" onclick="manualCloudSync()">סנכרון עכשיו</button>
   <button class="btn" onclick="uploadLocalSnapshot()">העלה נתונים מקומיים לענן</button>
   <button class="btn" onclick="logoutCloud()">יציאה</button>
  </div>
 </div>`);
}
async function logoutCloud(){closeModal();await sb.auth.signOut()}
async function manualCloudSync(){
 try{
  setCloudStatus('syncing','מסנכרן...');
  await flushCloudQueue(); await loadCloudState({silent:true});
  setCloudStatus('online','מסונכרן · '+(cloudUser?.email||'')); closeModal();
 }catch(e){setCloudStatus('error','שגיאת סנכרון');alert(cloudErrorText(e))}
}
async function uploadLocalSnapshot(){
 if(!cloudReady)return;
 if(!confirm('להחליף את הנתונים הקיימים בענן בנתונים שנמצאים כרגע במכשיר?'))return;
 try{await pushSnapshotToCloud(state,true);saveCloudQueue([]);setCloudStatus('online','מסונכרן · '+cloudUser.email);closeModal()}
 catch(e){alert(cloudErrorText(e))}
}

async function ensureHousehold(){
 let r=await sb.from('households').select('id,name').limit(1);
 if(r.error)throw r.error;
 if(r.data?.length){householdId=r.data[0].id;return}
 r=await sb.from('households').insert({name:'המשפחה שלי'}).select('id,name').single();
 if(r.error)throw r.error;
 householdId=r.data.id;
 const sr=await sb.from('financial_settings').upsert(settingsToDb(state.settings),{onConflict:'household_id'});
 if(sr.error)throw sr.error;
}

async function fetchRemoteState(){
 const remote={...structuredClone(defaults)};
 await Promise.all(Object.entries(cloudMap).map(async([key,cfg])=>{
  const r=await sb.from(cfg.table).select('*').eq('household_id',householdId);
  if(r.error)throw r.error;
  remote[key]=(r.data||[]).map(cfg.fromDb);
 }));
 const sr=await sb.from('financial_settings').select('*').eq('household_id',householdId).maybeSingle();
 if(sr.error)throw sr.error;
 if(sr.data)remote.settings=settingsFromDb(sr.data);
 return remote;
}
async function loadCloudState(){
 if(!cloudReady||cloudLoading)return;
 cloudLoading=true;
 try{
  const remote=await fetchRemoteState();
  if(!remoteHasData(remote)&&hasLocalData()){
   if(confirm('בענן עדיין אין נתונים, אבל במכשיר קיימים נתונים מקומיים. להעלות אותם עכשיו?')){
    await pushSnapshotToCloud(state,false);
    const fresh=await fetchRemoteState();
    state={...structuredClone(defaults),...fresh,settings:{...defaults.settings,...fresh.settings}};
    persist();render();return;
   }
  }
  if(remoteHasData(remote)||!hasLocalData()){
   state={...structuredClone(defaults),...remote,settings:{...defaults.settings,...remote.settings}};
   persist();render();
  }
 }finally{cloudLoading=false}
}
async function applyCloudOp(op){
 if(op.op==='settings'){
  const r=await sb.from('financial_settings').upsert(settingsToDb(op.item),{onConflict:'household_id'});
  if(r.error)throw r.error; return;
 }
 const cfg=cloudMap[op.key]; if(!cfg)return;
 if(op.op==='upsert'){
  const r=await sb.from(cfg.table).upsert(cfg.toDb(op.item),{onConflict:'id'});
  if(r.error)throw r.error;
 }else if(op.op==='delete'){
  const r=await sb.from(cfg.table).delete().eq('id',op.id).eq('household_id',householdId);
  if(r.error)throw r.error;
 }
}
async function flushCloudQueue(){
 if(!cloudReady||!navigator.onLine)return;
 let q=cloudQueue(); if(!q.length)return;
 setCloudStatus('syncing','מסנכרן...');
 while(q.length){
  await applyCloudOp(q[0]);
  q.shift(); saveCloudQueue(q);
 }
 setCloudStatus('online','מסונכרן · '+cloudUser.email);
}
async function clearRemoteState(){
 if(!cloudReady)return;
 for(const cfg of Object.values(cloudMap)){
  const r=await sb.from(cfg.table).delete().eq('household_id',householdId);
  if(r.error)throw r.error;
 }
}
async function pushSnapshotToCloud(snapshot,replace=false){
 if(replace)await clearRemoteState();
 for(const [key,cfg] of Object.entries(cloudMap)){
  const rows=(snapshot[key]||[]).map(cfg.toDb);
  if(rows.length){
   const r=await sb.from(cfg.table).upsert(rows,{onConflict:'id'});
   if(r.error)throw r.error;
  }
 }
 const sr=await sb.from('financial_settings').upsert(settingsToDb(snapshot.settings||defaults.settings),{onConflict:'household_id'});
 if(sr.error)throw sr.error;
}
function scheduleReload(){
 clearTimeout(reloadTimer);
 reloadTimer=setTimeout(()=>{if(!cloudQueue().length)loadCloudState().catch(()=>{})},700);
}
function subscribeRealtime(){
 if(!sb||!householdId)return;
 if(realtimeChannel)sb.removeChannel(realtimeChannel);
 realtimeChannel=sb.channel('fcc-'+householdId);
 for(const cfg of Object.values(cloudMap)){
  realtimeChannel.on('postgres_changes',{event:'*',schema:'public',table:cfg.table,filter:`household_id=eq.${householdId}`},scheduleReload);
 }
 realtimeChannel.on('postgres_changes',{event:'*',schema:'public',table:'financial_settings',filter:`household_id=eq.${householdId}`},scheduleReload).subscribe();
}
async function handleSession(session){
 cloudUser=session?.user||null; cloudReady=false; householdId=null; setAuthUI();
 if(!cloudUser){
  setCloudStatus('','מקומי · לא מחובר');
  showCloudBanner('הנתונים נשמרים כרגע במכשיר בלבד. התחבר כדי לסנכרן אותם בין המחשב והטלפון.');
  return;
 }
 setCloudStatus('syncing','מתחבר לענן...');
 try{
  await ensureHousehold();
  cloudReady=true;showCloudBanner('');
  if(cloudQueue().length)await flushCloudQueue();
  await loadCloudState();
  subscribeRealtime();
  setCloudStatus('online','מסונכרן · '+cloudUser.email);
 }catch(e){
  cloudReady=false;setCloudStatus('error','Supabase דורש הגדרה');showCloudBanner(cloudErrorText(e));
 }
}
async function initCloud(){
 if(!sb){showCloudBanner('לא ניתן לטעון את Supabase כרגע. האפליקציה ממשיכה לעבוד מקומית.');return}
 const {data,error}=await sb.auth.getSession();
 if(error){showCloudBanner(cloudErrorText(error));return}
 await handleSession(data.session);
 sb.auth.onAuthStateChange((event,session)=>setTimeout(()=>handleSession(session),0));
}
window.addEventListener('online',()=>{if(cloudReady)flushCloudQueue().then(()=>loadCloudState()).catch(()=>{})});
window.addEventListener('focus',()=>{if(cloudReady&&!cloudQueue().length)loadCloudState().catch(()=>{})});

initCloud();
