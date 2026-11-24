/* The Match — disable browser pinch zoom while preserving normal page scrolling. */
(function(){
 "use strict";
 const root=document.documentElement;
 root.style.touchAction="pan-x pan-y";
 if(document.body)document.body.style.touchAction="pan-x pan-y";
 document.addEventListener("gesturestart",e=>e.preventDefault(),{passive:false});
 document.addEventListener("gesturechange",e=>e.preventDefault(),{passive:false});
 document.addEventListener("gestureend",e=>e.preventDefault(),{passive:false});
 document.addEventListener("wheel",e=>{if(e.ctrlKey)e.preventDefault();},{passive:false});
})();
