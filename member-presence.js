/* The Match — record real app presence without changing sign-in or sign-up flows. */
(function(){
 "use strict";
 const db=window.db;
 if(!db)return;
 const PRESENCE_INTERVAL_MS=10*60*1000;
 let lastAttemptAt=0;
 let inFlight=false;

 async function recordPresence(){
  if(inFlight||document.visibilityState==="hidden"||Date.now()-lastAttemptAt<PRESENCE_INTERVAL_MS)return;
  inFlight=true;
  try{
   const {data,error:sessionError}=await db.auth.getSession();
   if(sessionError||!data?.session?.user)return;
   lastAttemptAt=Date.now();
   const {error}=await db.rpc("record_member_presence");
   if(error){
    console.warn("Member presence could not be recorded.",error.message);
   }
  }catch(error){
   console.warn("Member presence could not be recorded.",error?.message||error);
  }finally{
   inFlight=false;
  }
 }

 db.auth.onAuthStateChange((event,session)=>{
  if(session?.user&&(event==="SIGNED_IN"||event==="INITIAL_SESSION")){
   lastAttemptAt=0;
   Promise.resolve().then(recordPresence);
  }
 });
 document.addEventListener("visibilitychange",()=>{if(document.visibilityState==="visible")recordPresence();});
 window.addEventListener("focus",recordPresence);
 document.addEventListener("pointerdown",recordPresence,{passive:true});
 document.addEventListener("keydown",recordPresence);
 recordPresence();
})();
