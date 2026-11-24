/* The Match — audited administrator chat review. */
(function(){
 "use strict";
 const db=window.db;
 if(!db)return;
 const style=document.createElement("style");
 style.textContent=`
 #tmAdminChatDialog{position:fixed;inset:0;z-index:200000;display:none;align-items:center;justify-content:center;padding:12px;background:rgba(0,0,0,.78)}
 #tmAdminChatDialog.open{display:flex}
 #tmAdminChatDialog .tm-chat-shell{width:min(100%,900px);max-height:92dvh;display:flex;flex-direction:column;overflow:hidden;border:1px solid #8c7040;border-radius:20px;background:#101014;color:#f8f5ef;box-shadow:0 24px 80px #0009}
 #tmAdminChatDialog .tm-chat-head{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:16px;border-bottom:1px solid #343039}
 #tmAdminChatDialog h2{margin:0;font-size:20px}
 #tmAdminChatDialog .tm-chat-tools{display:flex;flex-wrap:wrap;gap:8px;padding:12px 16px}
 #tmAdminChatDialog input{flex:1;min-width:180px;padding:12px;border-radius:10px;border:1px solid #5b5660;background:#1d1b22;color:#fff}
 #tmAdminChatDialog select{min-width:170px;max-width:100%;padding:12px;border-radius:10px;border:1px solid #5b5660;background:#1d1b22;color:#fff}
 #tmAdminChatDialog button{padding:10px 14px;border:1px solid #7c6743;border-radius:10px;background:#25222a;color:#fff}
 #tmAdminChatDialog .tm-chat-notice{margin:0;padding:0 16px 12px;color:#d7c8a8;font-size:12px;line-height:1.5}
 #tmAdminChatDialog .tm-chat-results{overflow:auto;padding:0 16px 16px}
 #tmAdminChatDialog .tm-chat-message{padding:12px 0;border-top:1px solid #302d34}
 #tmAdminChatDialog .tm-chat-message strong{display:block;color:#f0d18d;font-size:14px}
 #tmAdminChatDialog .tm-chat-message time{display:block;margin:4px 0;color:#a9a3ad;font-size:11px}
 #tmAdminChatDialog .tm-chat-message p{margin:0;white-space:pre-wrap;overflow-wrap:anywhere;line-height:1.5}
 body.light-theme #tmAdminChatDialog .tm-chat-shell{background:#fff;color:#24202a}
 body.light-theme #tmAdminChatDialog .tm-chat-message p{color:#24202a}
 `;
 document.head.appendChild(style);
 let dialog=null,search=null,reason=null,results=null,before=null,loading=false,adminCheckInProgress=false,adminCheckAttempted=false;
 function makeDialog(){
  if(dialog)return;
  dialog=document.createElement("div");dialog.id="tmAdminChatDialog";
  dialog.innerHTML='<section class="tm-chat-shell" role="dialog" aria-modal="true" aria-labelledby="tmAdminChatTitle"><header class="tm-chat-head"><h2 id="tmAdminChatTitle">Private chat review</h2><button type="button" data-close>Close</button></header><div class="tm-chat-tools"><input type="search" maxlength="200" placeholder="Search names, member IDs or message text" aria-label="Search all chats"><select aria-label="Reason for chat review"><option value="routine_safety_review">Routine safety review</option><option value="member_report">Member report</option><option value="support_request">Member support</option><option value="moderation_investigation">Moderation investigation</option><option value="compliance_review">Compliance review</option></select><button type="button" data-search>Search</button></div><p class="tm-chat-notice">Restricted administrator access. Choose a review purpose before searching; every request and its purpose are recorded in the audit log. Members are informed in the privacy notice that authorised administrators may review chats. These chats are not end-to-end encrypted.</p><div class="tm-chat-results" aria-live="polite">Search or load recent messages.</div><div style="padding:12px 16px;border-top:1px solid #343039"><button type="button" data-more>Load older messages</button></div></section>';
  document.body.appendChild(dialog);
  search=dialog.querySelector("input");reason=dialog.querySelector("select");results=dialog.querySelector(".tm-chat-results");
  dialog.querySelector("[data-close]").onclick=()=>dialog.classList.remove("open");
  document.addEventListener("keydown",e=>{if(e.key==="Escape")dialog.classList.remove("open");});
  dialog.addEventListener("click",e=>{if(e.target===dialog)dialog.classList.remove("open");});
  dialog.querySelector("[data-search]").onclick=()=>{before=null;load(true);};
  dialog.querySelector("[data-more]").onclick=()=>load(false);
 }
 async function load(reset){
  if(loading)return;loading=true;
  if(reset)before=null;
  const button=dialog.querySelector("[data-more]");button.disabled=true;
  if(reset)results.textContent="Loading private messages…";
  try{
   const {data,error}=await db.rpc("admin_list_chat_messages",{p_search:search.value.trim()||null,p_before:before?.created_at||null,p_before_id:before?.id||null,p_limit:50,p_reason:reason.value});
   if(error)throw error;
   const rows=data||[];
   if(reset)results.replaceChildren();
   if(!rows.length&&reset){results.textContent="No messages found.";button.hidden=true;return;}
   rows.forEach(row=>{
    const item=document.createElement("article");item.className="tm-chat-message";
    const heading=document.createElement("strong");heading.textContent=row.sender_name+" → "+row.receiver_name;
    const time=document.createElement("time");time.textContent=new Date(row.created_at).toLocaleString();
    const body=document.createElement("p");body.textContent=row.message_body||"[No text content]";
    item.append(heading,time,body);results.appendChild(item);
   });
   if(rows.length)before={created_at:rows[rows.length-1].created_at,id:rows[rows.length-1].message_id};
   button.hidden=rows.length<50;
  }catch(error){results.textContent="Chat review unavailable: "+(error?.message||"Please try again.");button.hidden=true;}
  finally{loading=false;button.disabled=false;}
 }
 async function attachAdminControl(){
  const panel=document.getElementById("adminPanel");
  if(!panel||panel.querySelector("[data-open-admin-chat-review]")||adminCheckInProgress||adminCheckAttempted)return;
  adminCheckInProgress=true;
  try{
   const {data,error}=await db.rpc("is_match_admin");
   adminCheckAttempted=true;
   if(error||data!==true)return;
   const actions=panel.querySelector(".admin-top-actions")||panel.querySelector(".admin-topbar");
   if(!actions)return;
   makeDialog();
   const button=document.createElement("button");button.type="button";button.dataset.openAdminChatReview="true";
   button.textContent="Chat review";button.className="admin-refresh-button";
   button.addEventListener("click",()=>{dialog.classList.add("open");before=null;load(true);});
   actions.appendChild(button);
  }catch(error){
   adminCheckAttempted=true;
   console.warn("Admin chat review access check unavailable",error);
  }finally{
   adminCheckInProgress=false;
  }
 }
 function watch(){
  attachAdminControl().catch(error=>console.warn("Admin chat review control unavailable",error));
 }
 if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",watch,{once:true});else watch();
 const observer=new MutationObserver(watch);observer.observe(document.documentElement,{childList:true,subtree:true});
 db.auth.onAuthStateChange((event,session)=>{
  if(event==="SIGNED_IN"&&session?.user){
   adminCheckAttempted=false;
   watch();
  }
 });
})();
