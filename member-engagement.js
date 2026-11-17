/* The Match — member experience feedback and Consistency Stars. */
(function(){
  "use strict";
  const db=window.db;
  if(!db){console.warn("Member engagement module: Supabase client unavailable.");return;}
  const $=id=>document.getElementById(id);
  const questions={
    safety:"I feel safe being myself on The Match.",
    respect:"Members treat me with respect.",
    connections:"I find people I am genuinely interested in.",
    ease_of_use:"The Match is easy to use.",
    recommendation:"I would recommend The Match to a friend."
  };
  let selectedRating=0;
  let activePrompt=null;
  let activeUserId=null;
  let lastCheckinKey="";

  function lagosDate(){
    return new Intl.DateTimeFormat("en-CA",{timeZone:"Africa/Lagos",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date());
  }
  function setText(id,value){const el=$(id);if(el)el.textContent=value;}
  function safeError(error,context){
    console.warn(context,error);
  }

  function ensureConsistencyCard(){
    if($("memberConsistencyCard"))return;
    const profile=$("profile");
    const before=$("verificationSection");
    if(!profile||!before)return;
    const card=document.createElement("section");
    card.id="memberConsistencyCard";
    card.className="member-card";
    card.innerHTML=
      '<div class="mc-head"><div><p class="mc-eyebrow">THE MATCH · MEMBER MILESTONES</p><h3>Your Consistency Stars ✦</h3></div><span class="mc-streak" id="mcStreak">0-day streak</span></div>'+
      '<p class="mc-copy">Show up regularly, earn stars and unlock Match Coin rewards. One active day counts once per Lagos calendar day.</p>'+
      '<div class="mc-stars" id="mcStars" aria-label="Consistency star progress"></div>'+
      '<div class="mc-progress-track"><span id="mcProgressFill"></span></div>'+
      '<div class="mc-stats"><span id="mcProgressText">0 of 35 active days</span><span id="mcTotalDays">0 total active days</span></div>'+
      '<p class="mc-reward" id="mcReward" aria-live="polite">Earn 1 star every 7 active days. Complete 5 stars to receive 100 Match Coins.</p>';
    before.parentNode.insertBefore(card,before);
  }

  function renderConsistency(state,rewardCoins){
    ensureConsistencyCard();
    if(!$("memberConsistencyCard"))return;
    const cycle=Math.max(0,Number(state.active_days_in_cycle)||0);
    const stars=Math.max(0,Math.min(4,Number(state.stars_progress)||0));
    const visualStars=rewardCoins>0?5:stars;
    const streak=Math.max(0,Number(state.current_streak_days)||0);
    const total=Math.max(0,Number(state.total_active_days)||0);
    const starBox=$("mcStars");
    if(starBox){
      starBox.replaceChildren();
      for(let i=1;i<=5;i++){
        const star=document.createElement("span");
        star.className="mc-star"+(i<=visualStars?" earned":"");
        star.textContent="★";
        star.setAttribute("aria-label",i<=visualStars?"Star earned":"Star not yet earned");
        starBox.appendChild(star);
      }
    }
    setText("mcStreak",streak+"-day streak");
    setText("mcProgressText",cycle+" of 35 active days");
    setText("mcTotalDays",total+" total active days");
    const fill=$("mcProgressFill");
    if(fill)fill.style.width=(rewardCoins>0?100:Math.min(100,cycle/35*100))+"%";
    setText("mcReward",rewardCoins>0
      ?"Amazing consistency! You completed all 5 stars and received "+rewardCoins+" Match Coins. Your next star cycle has started."
      :"Earn 1 star every 7 active days. Complete 5 stars (35 active days) to receive 100 Match Coins.");
  }

  async function refreshConsistency(userId){
    const {data,error}=await db.from("member_consistency")
      .select("current_streak_days,total_active_days,active_days_in_cycle,stars_progress,rewards_claimed,last_active_date")
      .eq("user_id",userId).maybeSingle();
    if(error)throw error;
    if(data)renderConsistency(data,0);
  }

  function ensureFeedbackDialog(){
    if($("memberExperienceDialog"))return;
    const layer=document.createElement("div");
    layer.id="memberExperienceDialog";
    layer.className="me-dialog hidden";
    layer.setAttribute("role","dialog");
    layer.setAttribute("aria-modal","true");
    layer.setAttribute("aria-labelledby","meTitle");
    layer.innerHTML=
      '<div class="me-card">'+
        '<div class="me-mark" aria-hidden="true">♥</div>'+
        '<h2 id="meTitle">Help us make The Match better</h2>'+
        '<p class="me-intro">Please rate this statement:</p>'+
        '<p class="me-question" id="meQuestion"></p>'+
        '<div class="me-stars" id="meStars" role="group" aria-label="Rate from one to five stars"></div>'+
        '<p class="me-rating-label" id="meRatingLabel" aria-live="polite">Choose a rating</p>'+
        '<button type="button" class="me-submit" id="meSubmit" disabled>Submit</button>'+
        '<button type="button" class="me-dismiss" id="meDismiss">Not now</button>'+
        '<p class="me-privacy">Your feedback is private and helps improve the community.</p>'+
      '</div>';
    document.body.appendChild(layer);
    const stars=$("meStars");
    for(let i=1;i<=5;i++){
      const button=document.createElement("button");
      button.type="button";button.className="me-star";button.textContent="★";
      button.setAttribute("aria-label",i+" out of 5 stars");button.dataset.rating=String(i);
      button.addEventListener("click",()=>selectRating(i));
      stars.appendChild(button);
    }
    $("meSubmit").addEventListener("click",submitRating);
    $("meDismiss").addEventListener("click",dismissPrompt);
    layer.addEventListener("click",event=>{if(event.target===layer)dismissPrompt();});
  }

  function selectRating(value){
    selectedRating=value;
    document.querySelectorAll("#meStars .me-star").forEach(button=>{
      const active=Number(button.dataset.rating)<=value;
      button.classList.toggle("selected",active);
      button.setAttribute("aria-pressed",active?"true":"false");
    });
    setText("meRatingLabel",value+" out of 5 stars");
    const submit=$("meSubmit");if(submit)submit.disabled=false;
  }

  async function loadFeedbackPrompt(userId){
    const {data,error}=await db.rpc("match_get_experience_prompt");
    if(error)throw error;
    const prompt=Array.isArray(data)?data[0]:data;
    if(!prompt||!prompt.statement_key)return;
    activePrompt=prompt;
    selectedRating=0;
    ensureFeedbackDialog();
    setText("meQuestion",prompt.statement_text||questions[prompt.statement_key]||"I enjoy using The Match.");
    setText("meRatingLabel","Choose a rating");
    document.querySelectorAll("#meStars .me-star").forEach(button=>{
      button.classList.remove("selected");button.setAttribute("aria-pressed","false");
    });
    $("meSubmit").disabled=true;
    $("memberExperienceDialog").classList.remove("hidden");
  }

  async function submitRating(){
    if(!activePrompt||selectedRating<1)return;
    const button=$("meSubmit");button.disabled=true;button.textContent="Submitting…";
    try{
      const {error}=await db.rpc("match_submit_experience_rating",{
        p_statement_key:activePrompt.statement_key,p_rating:selectedRating
      });
      if(error)throw error;
      $("memberExperienceDialog").classList.add("hidden");
      activePrompt=null;
    }catch(error){
      safeError(error,"Experience feedback could not be submitted.");
      setText("meRatingLabel",error.message||"Could not submit. Please try again.");
      button.disabled=false;
    }finally{button.textContent="Submit";}
  }

  async function dismissPrompt(){
    if(!$("memberExperienceDialog")||$("memberExperienceDialog").classList.contains("hidden"))return;
    $("memberExperienceDialog").classList.add("hidden");
    activePrompt=null;
    try{const {error}=await db.rpc("match_dismiss_experience_prompt");if(error)throw error;}
    catch(error){safeError(error,"Could not save feedback prompt dismissal.");}
  }

  async function recordActivity(userId){
    const key=userId+":"+lagosDate();
    if(lastCheckinKey===key)return;
    lastCheckinKey=key;
    const {data,error}=await db.rpc("match_record_daily_activity");
    if(error){lastCheckinKey="";throw error;}
    const state=Array.isArray(data)?data[0]:data;
    if(state){
      renderConsistency(state,Number(state.reward_coins)||0);
    }else{
      await refreshConsistency(userId);
    }
    try{await loadFeedbackPrompt(userId);}
    catch(error){safeError(error,"Experience feedback prompt is not available yet. Apply the engagement migration first.");}
  }

  async function activateForCurrentUser(user){
    if(!user||!user.id){activeUserId=null;lastCheckinKey="";return;}
    if(activeUserId!==user.id){activeUserId=user.id;lastCheckinKey="";}
    try{
      await recordActivity(user.id);
    }catch(error){
      safeError(error,"Consistency Stars are not available yet. Apply the engagement migration before enabling this feature.");
    }
  }

  function addStyles(){
    if($("member-engagement-styles"))return;
    const style=document.createElement("style");style.id="member-engagement-styles";
    style.textContent=`
      #memberConsistencyCard{margin:16px 0;padding:18px;border:1px solid rgba(211,177,108,.35);border-radius:20px;background:linear-gradient(145deg,rgba(211,177,108,.09),rgba(12,12,12,.96));color:#f5f0e7}
      #memberConsistencyCard .mc-head{display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap}
      #memberConsistencyCard .mc-eyebrow{margin:0 0 5px;color:#d9b66e;font-size:10px;font-weight:850;letter-spacing:1.5px}
      #memberConsistencyCard h3{margin:0;color:#f0d18d;font-size:19px}
      #memberConsistencyCard .mc-streak{padding:7px 10px;border:1px solid rgba(217,182,110,.35);border-radius:999px;color:#f0d18d;font-size:11px;font-weight:800}
      #memberConsistencyCard .mc-copy{color:#b9b4a9;font-size:13px;line-height:1.55}
      #memberConsistencyCard .mc-stars{display:flex;justify-content:center;gap:clamp(8px,4vw,20px);margin:16px 0 12px}
      #memberConsistencyCard .mc-star{color:#4d4a43;font-size:clamp(30px,8vw,42px);line-height:1}
      #memberConsistencyCard .mc-star.earned{color:#e2bd70;text-shadow:0 0 15px rgba(226,189,112,.28)}
      #memberConsistencyCard .mc-progress-track{height:7px;overflow:hidden;border-radius:99px;background:#34312a}
      #memberConsistencyCard #mcProgressFill{display:block;width:0;height:100%;border-radius:99px;background:linear-gradient(90deg,#b88c45,#f0d18b);transition:width .3s}
      #memberConsistencyCard .mc-stats{display:flex;justify-content:space-between;gap:8px;margin-top:9px;color:#c8c1b3;font-size:11px}
      #memberConsistencyCard .mc-reward{margin:12px 0 0;color:#e7d2a7;font-size:12px;line-height:1.55}
      .me-dialog{position:fixed;inset:0;z-index:99999;display:flex;align-items:center;justify-content:center;padding:18px;background:rgba(0,0,0,.78);backdrop-filter:blur(5px)}
      .me-dialog.hidden{display:none!important}
      .me-card{box-sizing:border-box;width:min(100%,430px);padding:28px 22px 22px;border:1px solid rgba(217,182,110,.55);border-radius:23px;background:linear-gradient(155deg,#191713,#080808 65%);color:#f7f3eb;text-align:center;box-shadow:0 22px 65px rgba(0,0,0,.55)}
      .me-mark{color:#e5bd70;font-size:43px;line-height:1}
      .me-card h2{margin:14px 0 8px;color:#f0d18d;font-size:23px}
      .me-intro{margin:0;color:#bdb7ac;font-size:14px}
      .me-question{margin:18px 0 18px;color:#fff8e9;font-size:20px;font-weight:650;line-height:1.4}
      .me-stars{display:flex;justify-content:center;gap:clamp(7px,3vw,14px);margin:10px 0}
      .me-star{padding:0;border:0;background:transparent;color:#56524b;font-size:clamp(39px,10vw,48px);line-height:1;cursor:pointer}
      .me-star.selected{color:#e2bd70;text-shadow:0 0 16px rgba(226,189,112,.25)}
      .me-rating-label{min-height:18px;margin:8px 0 16px;color:#d9bd83;font-size:12px}
      .me-submit{width:100%;min-height:52px;border:0;border-radius:999px;background:linear-gradient(120deg,#f0d89d,#c69a52);color:#21190d;font-size:16px;font-weight:800}
      .me-submit:disabled{opacity:.42;cursor:not-allowed}
      .me-dismiss{margin:14px auto 0;padding:10px 18px;border:0;background:transparent;color:#c5bba9;font-size:14px}
      .me-privacy{margin:12px 0 0;color:#8f897f;font-size:11px;line-height:1.5}
      body.light-theme #memberConsistencyCard{background:linear-gradient(145deg,#fff8e9,#fff);color:#30291e;border-color:#e0cfaa}
      body.light-theme #memberConsistencyCard .mc-copy,body.light-theme #memberConsistencyCard .mc-stats{color:#6d6558}
      body.light-theme .me-card{background:linear-gradient(155deg,#fffdf8,#f6efe2);color:#30291e}
      body.light-theme .me-question{color:#30291e}
      @media(prefers-reduced-motion:reduce){#memberConsistencyCard *,.me-dialog *{transition:none!important}}
    `;
    document.head.appendChild(style);
  }

  async function init(){
    addStyles();
    ensureConsistencyCard();
    try{
      const {data,error}=await db.auth.getUser();
      if(error)throw error;
      if(data?.user)await activateForCurrentUser(data.user);
    }catch(error){safeError(error,"Member engagement initial session check failed.");}
    db.auth.onAuthStateChange((event,session)=>{
      if(event==="SIGNED_OUT"){activeUserId=null;lastCheckinKey="";if($("memberExperienceDialog"))$("memberExperienceDialog").classList.add("hidden");return;}
      if(session?.user)window.setTimeout(()=>activateForCurrentUser(session.user),0);
    });
    document.addEventListener("visibilitychange",()=>{
      if(document.visibilityState==="visible"&&activeUserId){
        const key=activeUserId+":"+lagosDate();
        if(key!==lastCheckinKey)activateForCurrentUser({id:activeUserId});
      }
    });
  }

  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",init,{once:true});
  else init();
})();
