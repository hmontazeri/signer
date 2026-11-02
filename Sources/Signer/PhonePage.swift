enum PhonePage {
    static let html = #"""
<!doctype html><html lang="de"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover">
<title>Unterschrift</title>
<style>
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent;-webkit-user-select:none;user-select:none}
html,body{margin:0;height:100%;font-family:-apple-system,system-ui,sans-serif;background:#f2f2f7;color:#111;overscroll-behavior:none}
@media (prefers-color-scheme:dark){body{background:#000;color:#eee}.card{background:#1c1c1e!important}}
#app{display:flex;flex-direction:column;height:100%;padding:max(env(safe-area-inset-top),10px) 14px max(env(safe-area-inset-bottom),14px)}
header{display:flex;justify-content:space-between;gap:8px;font-size:15px;padding:6px 2px 10px}
header b{font-weight:600}
header span{opacity:.6;text-align:right}
main{flex:1;display:flex;flex-direction:column;justify-content:center;min-height:0}
#pad{position:relative;width:100%;background:#fff;border-radius:14px;box-shadow:0 1px 10px #0003;overflow:hidden;touch-action:none}
#bg{position:absolute;inset:0;width:100%;height:100%;opacity:.5;pointer-events:none}
#cv{position:absolute;inset:0;width:100%;height:100%;touch-action:none}
#hint{text-align:center;font-size:13px;opacity:.55;margin-top:10px}
.card{background:#fff;border-radius:14px;padding:28px 20px;text-align:center;font-size:17px;line-height:1.4}
.card small{display:block;opacity:.6;margin-top:6px;font-size:14px}
footer{display:flex;gap:10px;padding-top:12px}
button{flex:1;font:inherit;font-size:18px;font-weight:600;padding:15px;border:0;border-radius:13px;background:#e5e5ea;color:#111}
button.primary{background:#0a60ff;color:#fff}
button:disabled{opacity:.35}
</style></head><body><div id="app">
<header><b id="doc">PDF Signer</b><span id="where"></span></header>
<main>
  <div id="wait" class="card">Warte auf den Mac …<small>Wähle am Mac eine Stelle im Dokument.</small></div>
  <div id="work" style="display:none">
    <div id="pad"><img id="bg" alt=""><canvas id="cv"></canvas></div>
    <div id="hint">Tipp: Handy quer halten für mehr Platz</div>
  </div>
  <div id="done" class="card" style="display:none">✓ Gesendet<small>Weiter am Mac.</small></div>
</main>
<footer id="foot" style="display:none"><button id="clear">Neu</button><button id="send" class="primary" disabled>Senden</button></footer>
<div id="conn" style="text-align:center;font-size:12px;color:#c00;min-height:14px"></div>
</div>
<script>
const T=new URLSearchParams(location.search).get('t');
const $=id=>document.getElementById(id);
const pad=$('pad'),cv=$('cv'),ctx=cv.getContext('2d');
let st={active:false,id:0},strokes=[],cur=null,sentId=-1;
function show(w){$('wait').style.display=w=='wait'?'':'none';$('work').style.display=w=='work'?'':'none';$('done').style.display=w=='done'?'':'none';$('foot').style.display=w=='work'?'flex':'none';}
function fit(){const r=pad.getBoundingClientRect(),d=window.devicePixelRatio||1;cv.width=Math.round(r.width*d);cv.height=Math.round(r.height*d);redraw();}
function redraw(){ctx.clearRect(0,0,cv.width,cv.height);ctx.lineCap='round';ctx.lineJoin='round';ctx.strokeStyle=st.ink||'#12238c';ctx.lineWidth=2.8*(window.devicePixelRatio||1);
 for(const s of strokes){ctx.beginPath();s.forEach((p,i)=>{const x=p[0]*cv.width,y=p[1]*cv.height;if(i)ctx.lineTo(x,y);else ctx.moveTo(x,y);});if(s.length==1)ctx.lineTo(s[0][0]*cv.width+.1,s[0][1]*cv.height);ctx.stroke();}
 $('send').disabled=!strokes.length;}
function add(e){const r=cv.getBoundingClientRect();cur.push([(e.clientX-r.left)/r.width,(e.clientY-r.top)/r.height,e.timeStamp]);}
cv.addEventListener('pointerdown',e=>{if(!st.active)return;cv.setPointerCapture(e.pointerId);cur=[];strokes.push(cur);add(e);redraw();e.preventDefault();});
cv.addEventListener('pointermove',e=>{if(!cur)return;let ev=e.getCoalescedEvents?e.getCoalescedEvents():[];if(!ev.length)ev=[e];ev.forEach(add);redraw();e.preventDefault();});
['pointerup','pointercancel'].forEach(n=>cv.addEventListener(n,()=>{cur=null;}));
$('clear').onclick=()=>{strokes=[];redraw();};
$('send').onclick=async()=>{
  $('send').disabled=true;
  try{const r=await fetch('/api/sign?t='+T,{method:'POST',body:JSON.stringify({id:st.id,strokes})});
    const j=await r.json();if(j.ok){sentId=st.id;strokes=[];show('done');if(navigator.vibrate)navigator.vibrate(30);}else{alert('Nicht angenommen – Stelle am Mac wurde geändert.');}}
  catch(e){alert('Senden fehlgeschlagen');}
  $('send').disabled=!strokes.length;};
function onState(){
  strokes=[];cur=null;
  if(st.active&&st.id!==sentId){show('work');pad.style.aspectRatio=st.aspect;$('bg').src='/api/preview?t='+T+'&id='+st.id;
    $('where').textContent='Seite '+st.page+' von '+st.pages;requestAnimationFrame(fit);}
  else if(!st.active){show('wait');$('where').textContent='';}
}
async function poll(){
  try{const r=await fetch('/api/state?t='+T,{cache:'no-store'});const s=await r.json();
    const changed=s.active!==st.active||(s.id||0)!==(st.id||0);st=s;$('doc').textContent=s.doc||'PDF Signer';
    if(changed)onState();$('conn').textContent='';}
  catch(e){$('conn').textContent='Verbindung zum Mac verloren …';}
  setTimeout(poll,900);}
window.addEventListener('resize',()=>{if(st.active)fit();});
poll();
</script></body></html>
"""#
}
