/* Le son du Soleil : trois sinus purs à la hauteur du bourdon solaire mesuré, et une salle.
   Ni saturation, ni battement, ni bruit, ni position mobile en HRTF (elle grésillait). Mesures : ../../soleil/RAPPORT.md. */
(() => {
  // Accordé sur la voix choisie (même note, graves), pour ne jamais jurer avec les autres sons. Le bourdon mesuré est à 142,24 Hz.
  const root = f => { f = f || 523; while (f > 172) f /= 2; return f < 118 ? f * 1.5 : f };
  const LENGTH = 1.2, WET = .035;
  // Montée en cosinus, descente exponentielle refermée en cosinus : aucune cassure.
  const bell = (u, rise, fall) => u <= 0 ? 0 : (u < rise ? .5 - .5 * Math.cos(Math.PI * u / rise) : Math.exp(-(u - rise) / fall));
  const close = u => u > LENGTH - .4 ? .5 + .5 * Math.cos(Math.PI * Math.min(1, (u - LENGTH + .4) / .4)) : 1;
  const curve = fn => Float32Array.from({ length: 2048 }, (_, i) => i === 0 || i === 2047 ? 0 : fn(i / 2047 * LENGTH) * close(i / 2047 * LENGTH));
  const body = curve(u => bell(u, .13, .19) + .26 * bell(u - .36, .15, .2));
  const second = curve(u => bell(u, .10, .14) + .2 * bell(u - .36, .13, .16));
  const third = curve(u => bell(u, .09, .12));
  // L'espace : une salle immense et sombre. Elle arrive en retard, s'ouvre lentement, met un peu plus d'une seconde à s'éteindre.
  // Filtrée deux fois vers le grave pour rester lisse ; gauche et droite à égalité.
  const rooms = new WeakMap();
  function space(ctx) {
    if (rooms.has(ctx)) return rooms.get(ctx);
    const n = ctx.sampleRate * 1.9 | 0, b = ctx.createBuffer(1, n, ctx.sampleRate), k = 1 - Math.exp(-2 * Math.PI * 340 / ctx.sampleRate);
    { const c = 0;
      const d = b.getChannelData(c); let seed = 14238, l1 = 0, l2 = 0, l3 = 0, e = 0;
      for (let i = 0; i < n; i++) {
        seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
        l1 += k * (seed / 2147483648 - 1 - l1); l2 += k * (l1 - l2); l3 += k * (l2 - l3);
        const u = i / ctx.sampleRate - .05, v = u < 0 ? 0 : (u < .16 ? .5 - .5 * Math.cos(Math.PI * u / .16) : Math.exp(-(u - .16) / .36)) * (i > n * .8 ? .5 + .5 * Math.cos(Math.PI * (i - n * .8) / (n * .2)) : 1);
        d[i] = l3 * v; e += d[i] * d[i];
      }
      // Même force à gauche et à droite là où vit le son, pas seulement en moyenne.
      let q = 0; for (let f = 122; f <= 168; f += 2) { let x = 0, y = 0; for (let i = 0; i < n; i += 4) { const a = 2 * Math.PI * f * i / ctx.sampleRate; x += d[i] * Math.cos(a); y += d[i] * Math.sin(a) } q += x * x + y * y }
      const s = 14 / Math.sqrt(q / 24) / 4; for (let i = 0; i < n; i++) d[i] *= s;
    }
    // La même salle des deux côtés, à 17 ms d'écart : large, et toujours à égalité.
    const c = new ConvolverNode(ctx, { buffer: b, disableNormalization: true, channelCount: 1, channelCountMode: 'explicit' }), l = new StereoPannerNode(ctx, { pan: -.9 }), q = new StereoPannerNode(ctx, { pan: .9 }), d = new DelayNode(ctx, { delayTime: .017 }), o = new GainNode(ctx);
    c.connect(l); c.connect(d); d.connect(q); l.connect(o); q.connect(o); o.in = c; rooms.set(ctx, o); return o;
  }
  let last = null;
  function coeur(ctx, out, { t0, pan = 0, f } = {}) {
    const ROOT = root(f);
    const t = Math.max(ctx.currentTime, t0 || 0);
    if (last && t - last.t < .05) return;
    if (last) { last.g.gain.cancelScheduledValues(t); last.g.gain.setTargetAtTime(0, t, .03) }
    const master = new GainNode(ctx, { gain: .058 }), clean = new BiquadFilterNode(ctx, { type: 'lowpass', frequency: 700, Q: .5 });
    const room = space(ctx), send = new GainNode(ctx, { gain: WET }), cut = new BiquadFilterNode(ctx, { type: 'highpass', frequency: 95, Q: .5 });
    clean.connect(master); master.connect(out); master.connect(cut); cut.connect(send); send.connect(room.in); room.connect(out);
    const part = (mult, level, env, where) => {
      const o = new OscillatorNode(ctx, { frequency: ROOT * mult }), g = new GainNode(ctx, { gain: 0 }), l = new GainNode(ctx, { gain: level }), p = new StereoPannerNode(ctx, { pan: where });
      // La hauteur se pose en douceur, une seule fois.
      o.frequency.setValueAtTime(ROOT * mult * .955, t); o.frequency.setTargetAtTime(ROOT * mult, t, .06);
      o.connect(g); g.connect(l); l.connect(p); p.connect(clean); g.gain.setValueCurveAtTime(env, t, LENGTH); o.start(t); o.stop(t + LENGTH + .02); return o;
    };
    const first = part(1, 1, body, pan * .1);
    part(2, .17, second, pan * .1); part(3, .03, third, 0);
    const me = last = { t, g: master };
    first.onended = () => { master.disconnect(); setTimeout(() => send.disconnect(), 4000); if (last === me) last = null };
  }
  window.Soleil = { voices: { coeur } };
})();
/* L'empreinte d'une version : le Soleil, trois anneaux (nouveau, mieux, réparé), un gros point par changement. */
window.Embleme=(x,w,h,n,o)=>{const TAU=Math.PI*2,R=Math.min(w,h)*.47,cx=w/2,cy=h/2,c=o.c,t=o.t||0,fine=o.fine!==false,ring=[.94,.68,.43],pts=[];let k=0;
 const put=(X,Y,r,a,f)=>{x.globalAlpha=Math.min(1,a);x.fillStyle=f;x.beginPath();x.arc(X,Y,r,0,TAU);x.fill()};
 for(let g=0;g<3;g++){const q=ring[g]*R,turn=t*.00005*(g%2?-1:1);if(fine)for(let j=-2;j<=2;j++){const rr=q+j*R*.052,m=Math.max(10,Math.round(rr*TAU/(R*.062)));for(let i=0;i<m;i++){const a=i/m*TAU+turn*1.6+j*.02,lit=.5+.5*Math.cos(a+.7);put(cx+Math.cos(a)*rr,cy+Math.sin(a)*rr,R*(.0085+.009*lit*(1-Math.abs(j)/3)),(.1+.36*lit)*(1-Math.abs(j)/3.4)*(n[g]?1:.45),c.accent)}}
  for(let i=0;i<n[g];i++,k++){const a=-Math.PI/2+i/Math.max(1,n[g])*TAU+turn+g*.6,on=o.on===k,X=cx+Math.cos(a)*q,Y=cy+Math.sin(a)*q,r=R*(fine?.047:.075)*(on?1.5:1);pts.push([X,Y,k]);x.globalAlpha=1;x.fillStyle=c.night;x.beginPath();x.arc(X,Y,r*1.6,0,TAU);x.fill();put(X,Y,r,o.on>=0&&!on?.5:1,'#fff')}}
 put(cx,cy,R*.15,1,c.sun);x.globalAlpha=1;return pts};
(()=>{
const $=(s,r=document)=>r.querySelector(s),$$=(s,r=document)=>[...r.querySelectorAll(s)],TAU=Math.PI*2,still=matchMedia('(prefers-reduced-motion:reduce)'),W=window.OORT;
const css=n=>getComputedStyle(document.documentElement).getPropertyValue(n).trim();
/* ---------- Sons : tout est synthétisé ici, aucun fichier. ---------- */
const S=(()=>{let ac,out,i0,i1,on=localStorage.getItem('oort-son')!=='0',pack='oort';
 const P={oort:{w:'sine',f:523,d:.16,h:[1,2.01],c:5200},pollen:{w:'sine',f:659,d:.28,h:[1,3.9],c:6500},umbra:{w:'triangle',f:262,d:.24,h:[1,1.5],c:1500},impulsion:{w:'square',f:392,d:.07,h:[1],c:2600}};
 const boot=()=>{if(ac)return ac.state==='suspended'?ac.resume():0;const A=window.AudioContext||window.webkitAudioContext;if(!A)return;ac=new A();i0=ac;i1=performance.now();ac.addEventListener('statechange',()=>{if(ac.state==='running')i0=null});out=ac.createGain();out.gain.value=.55;
  const len=ac.sampleRate*.5|0,ir=ac.createBuffer(2,len,ac.sampleRate);for(let c=0;c<2;c++){const d=ir.getChannelData(c);for(let i=0;i<len;i++)d[i]=(Math.random()*2-1)*Math.pow(1-i/len,3.2)}
  const rv=ac.createConvolver(),wet=ac.createGain();rv.buffer=ir;wet.gain.value=.12;out.connect(ac.destination);out.connect(rv);rv.connect(wet);wet.connect(ac.destination)};
 const note=(mul,at=0,vol=.2,pan=0,p=P[pack],dur=1)=>{if(!on||!ac)return;const t=ac.currentTime+at;p.h.forEach((h,i)=>{const o=ac.createOscillator(),g=ac.createGain(),f=ac.createBiquadFilter(),s=ac.createStereoPanner();o.type=p.w;o.frequency.value=p.f*mul*h;f.type='lowpass';f.frequency.value=p.c;s.pan.value=pan;const v=vol/(1+i*2.6)*(p.w==='square'?.35:1);
  g.gain.setValueAtTime(0,t);g.gain.linearRampToValueAtTime(v,t+.004);g.gain.exponentialRampToValueAtTime(.0001,t+p.d*dur/(1+i*.6));o.connect(f);f.connect(g);g.connect(s);s.connect(out);o.start(t);o.stop(t+p.d*dur+.05)})};
 const click=(vol=.1,fr=2400,pan=0)=>{if(!on||!ac)return;const n=ac.sampleRate*.018|0,b=ac.createBuffer(1,n,ac.sampleRate),d=b.getChannelData(0);for(let i=0;i<n;i++)d[i]=(Math.random()*2-1)*Math.pow(1-i/n,6);const s=ac.createBufferSource(),f=ac.createBiquadFilter(),g=ac.createGain(),q=ac.createStereoPanner();s.buffer=b;f.type='bandpass';f.frequency.value=fr;f.Q.value=1.1;g.gain.value=vol;q.pan.value=pan;s.connect(f);f.connect(g);g.connect(q);q.connect(out);s.start()};
 const pan=e=>e&&e.getBoundingClientRect?Math.max(-.6,Math.min(.6,(e.getBoundingClientRect().left+20)/innerWidth*1.4-.7)):0;
 const SU={montee:[0,.5,1,1.5,2,2.5,3,3.5],majeure:[0,2,4,5,7,9,11,12],penta:[0,2,4,7,9,12,14,16],mineure:[0,2,3,5,7,8,10,12],arpege:[0,4,7,12,16,19,16,12],reve:[0,2,4,6,8,10,12,14],lune:[0,2,3,7,8,12,14,15],vague:[0,4,7,9,12,9,7,4],descente:[12,11,9,7,5,4,2,0]};
 const DEF=()=>({jeux:{s:'montee',o:0},ruban:{s:'majeure',o:0},joueurs:{s:'penta',o:0},listes:{s:'montee',o:0}});let seq=DEF();try{const q=JSON.parse(localStorage.getItem('oort-notes')||'{}');for(const k in seq){const v=q[k];if(!v)continue;if(Array.isArray(v.n)&&v.n.length===8&&v.n.every(Number.isFinite))seq[k].n=v.n.map(x=>Math.max(0,Math.min(24,x)));if(SU[v.s]||v.s==='toi'&&seq[k].n)seq[k].s=v.s;if(Number.isInteger(v.o))seq[k].o=Math.max(-2,Math.min(2,v.o))}}catch(e){}
 const tones=k=>seq[k].s==='toi'?seq[k].n:SU[seq[k].s];
 const api={boot,P,SU,seq,tones,save(){localStorage.setItem('oort-notes',JSON.stringify(seq))},reset(k){seq[k]=DEF()[k]},step:(k,i,e,vol=.055,dur=.45)=>note(1.5*Math.pow(2,tones(k)[((i%8)+8)%8]/12+seq[k].o),0,vol,pan(e),P[pack],dur),get live(){return !!ac&&(ac.state==='running'||i0===ac&&performance.now()-i1<400)},get on(){return on},set on(v){on=v;localStorage.setItem('oort-son',v?'1':'0')},set pack(v){pack=v},
  focus:(i=0,e)=>api.step('jeux',i,e),press:e=>{click(.22,1500,pan(e));note(.5,0,.1,pan(e),P[pack],.5)},release:e=>click(.09,3200,pan(e)),
  toggle:(v,e)=>{click(.16,v?2600:1700,pan(e));note(v?1.335:1,.012,.12,pan(e))},lock:e=>{click(.26,1100,pan(e));note(.75,0,.13,pan(e));note(1.125,.07,.13,pan(e))},back:e=>note(.75,0,.1,pan(e)),
  done:()=>{note(1,0,.15);note(1.5,.09,.15);note(2,.2,.16,0,P[pack],2.2)},motif:k=>{const p=P[k];note(1,0,.22,-.15,p,1.4);note(1.5,.11,.2,.15,p,1.8);note(1.25,.3,.17,0,p,2.6)},slide:v=>note(.8+v*.9,0,.05,0,P[pack],.4),
  ping:(x=0)=>{if(on&&ac)Soleil.voices.coeur(ac,ac.destination,{pan:x,f:P[pack].f})}};return api})();
for(const ev of ['pointerdown','keydown'])addEventListener(ev,S.boot,{capture:true});
addEventListener('pointerdown',e=>{const b=e.target.closest('.btn,.key,.who,.dock button,.dock a');if(b)S.press(b)});addEventListener('pointerup',e=>{const b=e.target.closest('.btn,.key');if(b)S.release(b)});
/* ---------- Toiles : dessinées seulement quand on les voit. ---------- */
const live=new Set,seen=new IntersectionObserver(l=>l.forEach(e=>e.isIntersecting?live.add(e.target):live.delete(e.target)),{rootMargin:'60px'});
const canvas=(c,draw,fps=30)=>{const x=c.getContext('2d');const o={c,x,w:0,h:0,last:0,dirty:true};const fit=()=>{const r=c.getBoundingClientRect(),d=Math.min(devicePixelRatio||1,2);if(!r.width)return;o.w=r.width;o.h=r.height;c.width=r.width*d;c.height=r.height*d;x.setTransform(d,0,0,d,0,0);o.dirty=true};new ResizeObserver(fit).observe(c);fit();c._o=o;o.draw=t=>{x.clearRect(0,0,o.w,o.h);draw(x,o.w,o.h,t,o)};o.gap=1000/fps;seen.observe(c);return o};
const dots=(x,list,color)=>{x.fillStyle=color;const B=10,q=Array.from({length:B+1},()=>[]);for(const d of list)if(d[2]>.2&&d[3]>.03)q[Math.round(Math.min(1,d[3])*B)].push(d);for(let i=1;i<=B;i++){if(!q[i].length)continue;x.globalAlpha=i/B;x.beginPath();for(const d of q[i]){x.moveTo(d[0]+d[2],d[1]);x.arc(d[0],d[1],d[2],0,TAU)}x.fill()}x.globalAlpha=1};
const loop=t=>{if(document.visibilityState==='visible')for(const c of live){const o=c._o;if(!o||!o.w)continue;if(o.dirty||(!still.matches&&t-o.last>o.gap)){o.last=t;o.dirty=false;o.draw(t)}}still.matches?setTimeout(()=>requestAnimationFrame(loop),100):requestAnimationFrame(loop)};
let seed=5;const rnd=()=>(seed=seed*16807%2147483647)/2147483647;
/* ---------- Le nuage d'Oort en coupe, en 3D ---------- */
const sky=$('#ciel');if(sky){const pts=[];const N=innerWidth<760?5200:9800,GA=Math.PI*(3-Math.sqrt(5));
 for(let i=0;i<N;i++){const y=1-2*(i+.5)/N,r=Math.sqrt(1-y*y),a=i*GA,x=Math.cos(a)*r,z=Math.sin(a)*r;if(z>.1)continue;const k=.9+.1*rnd();pts.push([x*k,y*k,z*k,x,y,z,0])}
 for(let j=0;j<9;j++){const r=1-j*.0165,m=Math.round(330-j*16);for(let i=0;i<m;i++){const a=i/m*TAU+j*.02,th=Math.cos(a);if(th<.15&&j>3+th*3+3)continue;pts.push([Math.cos(a)*r,Math.sin(a)*r,.1-j*.003,0,0,1,1])}}
 for(let k=0;k<30;k++){const t=.16+k*.0262,n=Math.round(t*(innerWidth<760?105:150)),th=.004+.085*Math.pow(t,2.8),ly=Math.max(1,Math.round(th/.016));for(let j=0;j<ly;j++){const h=ly===1?0:(j/(ly-1)-.5)*2*th;for(let i=0;i<n;i++){const a=(i+(k+j)%2*.5)/n*TAU;pts.push([Math.cos(a)*t,h,Math.sin(a)*t,0,Math.sign(h)||1,0,2])}}}
 const stars=Array.from({length:150},()=>[rnd(),rnd(),.4+rnd()*1,.15+rnd()*.6,rnd()*TAU]);
 let mx=-9e3,my=-9e3,tx=0,ty=0,px=0,py=0,wave=-1,born=performance.now(),sun=[0,0,0];
 sky.parentElement.addEventListener('pointermove',e=>{const r=sky.getBoundingClientRect();mx=e.clientX-r.left;my=e.clientY-r.top;tx=mx/r.width-.5;ty=my/r.height-.5});sky.parentElement.addEventListener('pointerleave',()=>{mx=my=-9e3;tx=ty=0});
 const sb0=$('#soleil'),sunPan=()=>Math.max(-.4,Math.min(.4,sun[0]/Math.max(1,sky.clientWidth)*.9-.45));sb0.addEventListener('click',()=>{wave=performance.now();S.boot();S.ping(sunPan())});
 canvas(sky,(x,w,h,t)=>{const m=w<860,R=m?Math.min(w*.56,h*.31):Math.min(h*.47,w*.36),cx=m?w*.54:w*.68,cy=m?h*.27:h*.47;px+=(tx-px)*.06;py+=(ty-py)*.06;const ya=-.36+px*.5+(still.matches?0:Math.sin(t*.00021)*.11),xa=.3+py*.3+(still.matches?0:Math.sin(t*.00016)*.05),ca=Math.cos(ya),sa=Math.sin(ya),cb=Math.cos(xa),sb=Math.sin(xa),grow=still.matches?1:Math.min(1,(performance.now()-born)/1500),ez=1-Math.pow(1-grow,4),wt=wave<0?9:(performance.now()-wave)/900;
  const turn=still.matches?0:t*.00007,ct=Math.cos(turn),st=Math.sin(turn),L=[-.62,-.5,.6],list=[],front=[];
  for(const s of stars){const tw=still.matches?1:.6+.4*Math.sin(t*.001+s[4]);list.push([s[0]*w,s[1]*h,s[2],s[3]*tw])}
  for(const p of pts){let X=p[0],Y=p[1],Z=p[2],nx=p[3],ny=p[4],nz=p[5];if(p[6]!==1){if(p[6]===2){const q=X*ct-Z*st;Z=X*st+Z*ct;X=q}}
   if(ez<1){const g=1+(1-ez)*(1.6+((X*37+Y*91)%1));X*=g;Y*=g;Z*=g}
   let a=X*ca+Z*sa,c=-X*sa+Z*ca,b=Y*cb-c*sb;c=Y*sb+c*cb;const pr=3.4/(3.4-c),sx=cx+a*R*pr,sy=cy+b*R*pr;if(sx<-8||sx>w+8||sy<-8||sy>h+8)continue;
   let na=nx*ca+nz*sa,nc=-nx*sa+nz*ca,nb=ny*cb-nc*sb;nc=ny*sb+nc*cb;let lum,rad;
   if(p[6]===0){const ins=-(na*L[0]+nb*L[1]+nc*L[2]);lum=Math.max(0,ins)*.62+.07+.2*Math.max(0,1-Math.hypot(X,Y,Z)*.2-Math.abs(Y));rad=.0034+.0046*lum}
   else if(p[6]===1){const lit=.5+.5*(p[0]*.86-p[1]*.25);lum=.35+.65*lit;rad=.0032+.0058*lit}
   else{const d=Math.hypot(X,Z);lum=.16+.5*Math.max(0,1-d*.95)+.42*Math.max(0,c*.9+.12);rad=.0022+.0026*(1-d*.4)+.0016*Math.max(0,c)}
   if(wt<1.7){const d=Math.hypot(X,Y,Z)*1.1-wt*1.2;const k=Math.exp(-d*d*90);lum+=k*.8;rad+=k*.004}
   const dm=Math.hypot(sx-mx,sy-my);if(dm<120){const k=1-dm/120;lum+=k*k*.55;rad+=k*k*.0045}
   const fade=m?Math.min(1,Math.max(.05,(h*.46-sy)/(h*.15))):Math.min(1,Math.max(.0,(sx-w*.3)/(w*.16)+.12));(p[6]===2&&c>.02?front:list).push([sx,sy,Math.max(.5,rad*R*pr),Math.min(1,lum)*fade*ez])}
  dots(x,list,css('--accent'));const sc=R*.052*(wt<1?1+.35*Math.sin(wt*Math.PI):1)*ez;sun=[cx,cy,sc];{const q=Math.max(48,sc*2.6);sb0.style.cssText=`left:${cx-q/2}px;top:${cy-q/2}px;width:${q}px;height:${q}px`};x.fillStyle=css('--sun');x.globalAlpha=ez;x.beginPath();x.arc(cx,cy,sc,0,TAU);x.fill();
  x.strokeStyle='#fff';x.lineWidth=1.2;x.globalAlpha=.6*ez;x.beginPath();for(const [vx,vy] of [[1,0],[-1,0],[0,1],[0,-1]]){x.moveTo(cx+vx*sc*1.8,cy+vy*sc*1.8);x.lineTo(cx+vx*sc*2.9,cy+vy*sc*2.9)}x.stroke();x.globalAlpha=1;
  dots(x,front,css('--accent'));
  const ox=R*1.34,oy=R*.34,rot=-.34,A=still.matches?.6:t*.00022%TAU;x.strokeStyle=css('--accent');x.lineWidth=1;x.globalAlpha=.34*ez;x.setLineDash([2,7]);x.beginPath();x.ellipse(cx,cy,ox,oy,rot,-.3,Math.PI+.3);x.stroke();x.setLineDash([]);const ex=Math.cos(A)*ox,ey=Math.sin(A)*oy,fx=cx+ex*Math.cos(rot)-ey*Math.sin(rot),fy=cy+ex*Math.sin(rot)+ey*Math.cos(rot);if(Math.sin(A)>-.3){x.globalAlpha=ez;x.fillStyle='#fff';x.beginPath();x.arc(fx,fy,2.6,0,TAU);x.fill()}x.globalAlpha=1},40)}
/* ---------- Trame sous le pointeur des cartes ---------- */
addEventListener('pointermove',e=>{const c=e.target.closest&&e.target.closest('.card,.who');if(c){const r=c.getBoundingClientRect();c.style.setProperty('--mx',e.clientX-r.left+'px');c.style.setProperty('--my',e.clientY-r.top+'px')}},{passive:true});
/* ---------- Dock ---------- */
/* La barre du bas change de page sur place, comme dans une app mobile. Sans script, la page reste une longue page. */
const dl=$$('.dock a'),slide=$('.dock .slide'),ids=dl.map(a=>a.hash.slice(1)),pages=ids.map(id=>$$(`[data-v="${id}"]`)),keep=ids.map(()=>0),rootEl=document.documentElement;let cur=-1,shown=-1,anim=[];
const pill=()=>{const a=dl[cur];if(!a)return;slide.style.width=a.offsetWidth+'px';slide.style.transform=`translateX(${a.offsetLeft}px)`};
const show=(i,o={})=>{if(i<0||i>=ids.length)return;if(i===cur){if(!o.first)scrollTo({top:0,behavior:still.matches?'instant':'smooth'});return}
 const from=shown;if(from>=0)keep[from]=scrollY;cur=i;anim.forEach(a=>a.cancel());anim=[];/* finish() rallumerait un fondu déjà annulé. */rootEl.dataset.page=ids[i];
 dl.forEach((a,k)=>k===i?a.setAttribute('aria-current','page'):a.removeAttribute('aria-current'));pill();
 const swap=()=>{shown=i;pages.forEach((l,k)=>l.forEach(e=>{e.hidden=k!==i}));scrollTo({top:o.top?0:keep[i],behavior:'instant'});dispatchEvent(new Event('resize'));if(o.focus){const h=$('h1,h2',pages[i][0]);h.tabIndex=-1;h.focus({preventScroll:true})}
  if(from<0||still.matches)return;pages[i].forEach(e=>anim.push(e.animate([{opacity:0,transform:'scale(.985)'},{opacity:1,transform:'none'}],{duration:300,easing:'cubic-bezier(.22,1,.36,1)'})))};
 if(from<0||still.matches||o.now)swap();else{const out=pages[from].map(e=>e.animate([{opacity:1},{opacity:0}],{duration:110,easing:'ease-out',fill:'forwards'}));anim=out;let done=false;const end=()=>{if(done)return;done=true;out.forEach(a=>a.cancel());if(cur===i)swap()};Promise.allSettled(out.map(a=>a.finished)).then(end);setTimeout(end,220)}
 if(!o.silent)S.step('listes',i,dl[i],.09)};
const viewOf=h=>{const e=h.length>1&&document.getElementById(h.slice(1)),v=e&&(e.dataset.v||(e.closest('[data-v]')||{dataset:{}}).dataset.v);return v?ids.indexOf(v):-1};
rootEl.classList.add('tabs');
addEventListener('click',e=>{const a=e.target.closest&&e.target.closest('a[href^="#"]');if(!a||e.metaKey||e.ctrlKey||e.shiftKey||e.altKey)return;if(a.hash==='#contenu'){e.preventDefault();$('#contenu').focus();return}const i=viewOf(a.hash);if(i<0)return;e.preventDefault();if(i!==cur)history.pushState(null,'',a.hash);show(i,{top:!a.closest('.dock'),focus:!e.detail&&i!==cur});const el=$(a.hash);if(el&&!ids.includes(el.id))setTimeout(()=>el.scrollIntoView({block:'start',behavior:'instant'}),300)});
addEventListener('popstate',()=>show(Math.max(0,viewOf(location.hash)),{silent:true}));
/* Recharger ou revenir rend la page là où elle était. */
const POS='oort-pos'+location.pathname,nav=performance.getEntriesByType('navigation')[0],back=nav&&nav.type!=='navigate';if(back)try{(JSON.parse(sessionStorage.getItem(POS))||[]).forEach((y,k)=>{if(k in keep&&Number.isFinite(y))keep[k]=y})}catch(e){}
addEventListener('pagehide',()=>{if(shown>=0)keep[shown]=scrollY;try{sessionStorage.setItem(POS,JSON.stringify(keep))}catch(e){}});
history.scrollRestoration='manual';show(Math.max(0,viewOf(location.hash)),{first:true,silent:true,top:!back});
$('.lang').addEventListener('click',e=>{e.currentTarget.hash=location.hash});
addEventListener('resize',pill);document.fonts.ready.then(pill);
const sb=$('#son');const paintSon=()=>{sb.setAttribute('aria-pressed',S.on);sb.querySelector('.w').style.display=S.on?'':'none';sb.querySelector('.x').style.display=S.on?'none':''};sb.addEventListener('click',()=>{S.on=!S.on;paintSon();if(S.on)S.done()});paintSon();
/* ---------- Chapitres : on descend, la barre suit, un point s'allume quand on a touché ---------- */
const panels=$$('.panel'),subs=$$('.sub button'),subSl=$('.sub .slide'),done=new Set;let pan=0;
const subPill=()=>{const b=subs[pan];if(!b||!b.offsetWidth)return;subSl.style.width=b.offsetWidth+'px';subSl.style.transform=`translateX(${b.offsetLeft}px)`;subs.forEach((x,k)=>k===pan?x.setAttribute('aria-current','true'):x.removeAttribute('aria-current'))};
const goPan=i=>{i=Math.max(0,Math.min(panels.length-1,i));const R=panels[i].getBoundingClientRect();scrollTo({top:scrollY+R.top-96,behavior:still.matches?'instant':'smooth'});S.step('listes',i,subs[i],.09)};
subs.forEach((b,i)=>b.addEventListener('click',()=>goPan(i)));
const spy=()=>{if(rootEl.dataset.page!=='essayer')return;let i=0;panels.forEach((p,k)=>{if(p.getBoundingClientRect().top<innerHeight*.42)i=k});if(innerHeight+scrollY>=rootEl.scrollHeight-40)i=panels.length-1;if(i!==pan){pan=i;subPill()}};addEventListener('scroll',spy,{passive:true});addEventListener('resize',()=>{spy();subPill()});document.fonts.ready.then(subPill);
panels.forEach((p,i)=>{const mark=e=>{if(done.has(i)||!e.target.closest('button,input,[role=slider]')||e.type==='click'&&!e.detail&&!rootEl.classList.contains('pad')&&e.isTrusted===false)return;done.add(i);subs[i].classList.add('ok');if(done.size===panels.length){S.done();const n=$('#essayer a.next');n&&n.classList.add('ready')}};p.addEventListener('click',mark);p.addEventListener('input',mark);p.addEventListener('keydown',e=>{if(/Arrow|Enter| /.test(e.key))mark(e)})});
/* Chaque carte se développe une fois, en montant, quand elle arrive. */
if(!still.matches&&'IntersectionObserver'in window){const io=new IntersectionObserver(l=>l.forEach(e=>{if(!e.isIntersecting)return;io.unobserve(e.target);if(still.matches)return;const k=[...e.target.parentElement.children].indexOf(e.target)%3;e.target.animate([{opacity:0,transform:'translateY(34px)'},{opacity:1,transform:'none'}],{duration:620,delay:k*70,easing:'cubic-bezier(.22,1,.36,1)',fill:'backwards'})}),{threshold:.12});$$('#essayer .card,.chap,.steps li').forEach(e=>io.observe(e))}
/* « La suite » : le point qui grossit vers la page d'après. */
$$('a.next').forEach(n=>canvas($('canvas',n),(x,w,h,t)=>{const L=[],on=n.matches(':hover,:focus-visible'),ph=still.matches?0:t*.0011;for(let j=0;j<4;j++){const R=10+j*12,m=16+j*10;for(let i=0;i<m;i++){const a=i/m*TAU+ph*(j%2?-.12:.12);L.push([w/2+Math.cos(a)*R,h/2+Math.sin(a)*R,1.3+(on?.8:0)+.5*Math.sin(ph*2-j),.3+(on?.4:.1)+.2*Math.sin(ph*2-j)])}}dots(x,L,css('--accent'));x.fillStyle=css('--sun');x.globalAlpha=1;x.beginPath();x.arc(w/2,h/2,n.classList.contains('ready')||on?7:5,0,TAU);x.fill()},30));
/* ---------- Rangée : un seul contour de focus qui glisse ---------- */
$$('.rail').forEach(r=>{const b=$$('button',r),ring=$('.ring',r),name=$('.name',r.closest('.railbox'));let at=1;const go=(i,quiet,f)=>{at=(i+b.length)%b.length;b.forEach((x,k)=>{x.setAttribute('aria-checked',k===at);x.tabIndex=k===at?0:-1});name.textContent=b[at].dataset.n;const o=b[at],g=o.offsetWidth*.1+6;ring.style.width=ring.style.height=o.offsetWidth+g*2+'px';ring.style.transform=`translate(${o.offsetLeft-g}px,${o.offsetTop-g}px)`;if(!quiet)S.focus(at,o);if(f)o.focus({preventScroll:true});const s=r.parentElement;s.scrollTo({left:o.offsetLeft-s.clientWidth/2+o.offsetWidth/2,behavior:quiet||still.matches?'instant':'smooth'})};
 b.forEach((x,k)=>{x.addEventListener('click',()=>go(k,k===at));x.addEventListener('focus',()=>{if(k!==at)go(k,true)});x.addEventListener('pointerenter',e=>{if(e.pointerType==='mouse'&&k!==at)go(k)})});r.addEventListener('keydown',e=>{const d=e.key==='ArrowRight'?1:e.key==='ArrowLeft'?-1:0;if(d){e.preventDefault();e.stopPropagation();go(at+d,false,true)}});document.fonts.ready.then(()=>go(1,true));addEventListener('resize',()=>go(at,true))});
/* ---------- Ruban ---------- */
{const r=$('.ribbon'),s=$('.strip',r),t=$$('.tile',s),nm=$('#ruban-nom');let at=1,lk=1;const paint=()=>{s.style.transform=`translateY(${62-at*126}px)`;t.forEach((x,k)=>{x.classList.toggle('on',k===at&&k!==lk);x.classList.toggle('lock',k===lk)});nm.textContent=t[at].dataset.n};
const mv=d=>{const n=Math.max(0,Math.min(t.length-1,at+d));if(n!==at){at=n;S.step('ruban',at*2,r,.09)}else S.back(r);paint()};$('#r-haut').onclick=()=>mv(-1);$('#r-bas').onclick=()=>mv(1);$('#r-a').onclick=()=>{const x=t[at];x.classList.add('down');S.lock(r);setTimeout(()=>{x.classList.remove('down');lk=at;paint()},130)};r.addEventListener('wheel',e=>{if(Math.abs(e.deltaY)>8&&document.activeElement&&r.contains(document.activeElement))e.preventDefault()},{passive:false});paint()}
/* ---------- Vague ---------- */
{const w=$('.wave'),c=$('canvas',w),b=$('#vague-b');let p=0,run=false,end=0,t0=0,tm=0;const D=5950,fin=()=>{clearTimeout(tm);run=false;p=1;end=still.matches?-9e9:performance.now();w.classList.add('done');b.disabled=false;b.textContent=W.again;if(rootEl.dataset.page==='essayer')S.done();o.dirty=true};matchMedia(still.media).addEventListener('change',()=>{if(run)fin()});/* à part : Chromium n'avertit pas un objet dont on lit matches à chaque image. */const o=canvas(c,(x,W2,H,t)=>{if(run)p=Math.min(1,Math.max(0,(t-t0)/D));
 if(p<=0&&!run)return;const L=[];if(p<1){const base=H*(1-p);for(let yy=0;yy<H;yy+=7)for(let xx=(yy/7%2)*3.5;xx<W2;xx+=7){const s=base+Math.sin(xx*.032+t*.0026)*5+Math.sin(xx*.06-t*.0017)*3,d=yy-s;if(d>-12){const k=Math.max(0,1-Math.abs(d-2)/16);L.push([xx,yy,d>0?1.5+k*2.1:Math.max(0,1.2+d/12),d>0?.28+k*.72:.5])}}dots(x,L,'#fff')}
 else{const k=Math.min(1,(t-end)/900),f=k<.55?k/.55:1-(k-.55)/.45;if(k<1){for(let j=0;j<4;j++){const n=30+j*9;for(let i=0;i<n;i++){const a=i/n*TAU+(1-k)*1.4,r=(30+j*8)*(.55+.45*Math.min(1,k*2));L.push([W2/2+Math.cos(a)*r,H/2+Math.sin(a)*r,2.2-j*.3,f])}}dots(x,L,'#fff');x.globalAlpha=f;x.fillStyle=css('--sun');x.beginPath();x.arc(W2/2,H/2,7,0,TAU);x.fill();x.globalAlpha=1}}},40);
b.addEventListener('click',()=>{p=0;w.classList.remove('done');b.disabled=true;b.textContent=W.running;if(still.matches)fin();else{run=true;t0=performance.now();tm=setTimeout(fin,D)}o.dirty=true})}
/* ---------- Packs sonores ---------- */
$$('.pad1').forEach(b=>{const k=b.dataset.k,c=$('canvas',b);let hit=-9e9;const base=Array.from({length:26},(_,i)=>.18+.16*Math.abs(Math.sin(i*({oort:.5,pollen:.9,umbra:.27,impulsion:1.6})[k]+1)));canvas(c,(x,w,h,t)=>{const L=[],e=Math.max(0,1-(t-hit)/900);base.forEach((v,i)=>{const a=v+e*.82*Math.abs(Math.sin(i*.55-t*.017))*(1-Math.abs(i-13)/16),n=Math.max(1,Math.round(a*h/6));for(let j=0;j<n;j++)L.push([4+i*(w-8)/25,h/2+(j-(n-1)/2)*5,1.55,.38+e*.62])});dots(x,L,'#fff')},30);b.addEventListener('click',()=>{hit=performance.now();S.pack=k;$$('.pad1').forEach(x=>x.setAttribute('aria-pressed',x===b));S.motif(k)})});
/* ---------- Manette : les vraies touches s'allument ---------- */
{const sec=$('#manette'),c=$('canvas',sec),lit={},pos={l:[-.43,-.23],d:[-.145,.1],y:[.467,-.36],x:[.343,-.24],b:[.59,-.24],a:[.467,-.115],r:[.24,.05],h:[0,-.3]};const cells=[];
 {const w=420,h=300,o=document.createElement('canvas');o.width=w;o.height=h;const g=o.getContext('2d',{willReadFrequently:true});g.beginPath();g.moveTo(112,52);g.bezierCurveTo(150,44,270,44,308,52);g.bezierCurveTo(352,58,372,110,392,190);g.bezierCurveTo(408,254,384,284,352,272);g.bezierCurveTo(318,258,304,214,272,206);g.bezierCurveTo(240,200,180,200,148,206);g.bezierCurveTo(116,214,102,258,68,272);g.bezierCurveTo(36,284,12,254,28,190);g.bezierCurveTo(48,110,68,58,112,52);g.fill();const d=g.getImageData(0,0,w,h).data,q=8.2;for(let y=0,r=0;y<h;y+=q*.866,r++)for(let x=r%2*q/2;x<w;x+=q)if(d[((y|0)*w+(x|0))*4+3]>128)cells.push([(x-w/2)/210,(y-150)/210])}
 const rad={l:.135,r:.125,d:.1,y:.062,x:.062,b:.062,a:.062,h:.055};let ax=[0,0,0,0];
 canvas(c,(x,w,h,t)=>{const s=w*.47,z=Math.min(1,s/245),L=[],G=[];for(const k in lit)lit[k]*=.86;for(const [px,py] of cells){let k=null,d0=1;for(const n in pos){let [qx,qy]=pos[n];const d=Math.hypot(px-qx,py-qy);if(d<rad[n]&&d<d0){k=n;d0=d}}const X=w/2+px*s,Y=h/2+py*s;if(k){const v=lit[k]||0,edge=d0/rad[k];if(v>.04)G.push([X,Y,(2.4+v*3.4*(1-edge*.4))*z,.35+v*.65]);else if(edge>.7)L.push([X,Y,2.2*z,.9])}else{const sh=.4+.5*Math.max(0,.5+px*.5-py*.4);L.push([X,Y,(1.5+sh*2.2)*z,.25+sh*.6])}}
  for(const [n,i] of [['l',0],['r',2]]){const [qx,qy]=pos[n];for(let a=0;a<16;a++)L.push([w/2+(qx+ax[i]*.05)*s+Math.cos(a/16*TAU)*s*.065,h/2+(qy+ax[i+1]*.05)*s+Math.sin(a/16*TAU)*s*.065,2.3*z,1])}dots(x,L,css('--accent'));dots(x,G,'#fff')},40);
 const hit=(k,e)=>{lit[k]=1;const b=$(`[data-p="${k}"]`,sec);if(b){b.classList.add('down');setTimeout(()=>b.classList.remove('down'),130)}if(k==='a'||k==='b')S.lock(e||sec);else S.step('listes',Object.keys(pos).indexOf(k),e||sec,.09);c._o.dirty=true;if(still.matches)setTimeout(()=>{c._o.dirty=true},260)};
 $$('[data-p]',sec).forEach(b=>b.addEventListener('click',()=>hit(b.dataset.p,b)));
 addEventListener('keydown',e=>{if(e.repeat||e.metaKey||e.ctrlKey||e.altKey||!live.has(c)||/INPUT/.test(document.activeElement.tagName))return;const m={a:'a',b:'b',x:'x',y:'y',h:'h'}[e.key.toLowerCase()];if(m)hit(m)});
 /* Manette : lue en continu (certains navigateurs n'annoncent pas une manette déjà branchée), trois dispositions, ou WebHID. */
 const st=$('#pad-etat'),hb=$('#pad-hid'),root=document.documentElement,nin=/057e|nintendo|switch|joy-?con|pro controller/i;let hid=null,was={},seenPad='',rep=null,run=0,runAt=0,grab=null;const free=()=>{if(grab){grab.classList.remove('grab');grab=null}};
 const hat=v=>{if(v===undefined||v>1.05||v<-1.05)return{};const n=Math.round((v+1)*3.5);return{up:n===7||n<2,right:n>0&&n<4,down:n>2&&n<6,left:n>4&&n<8}};
 const read=()=>{if(hid&&hid.s)return hid.s;let g=null;try{for(const x of navigator.getGamepads?navigator.getGamepads():[])if(x&&x.connected!==false&&(!g||x.timestamp>g.timestamp))g=x}catch(e){}if(!g)return null;const N=nin.test(g.id),B=i=>!!g.buttons[i]&&(g.buttons[i].pressed||g.buttons[i].value>.5),std=g.mapping==='standard',h=std?{up:B(12),down:B(13),left:B(14),right:B(15)}:hat(g.axes[9]);
  return{name:g.id,N,g,b:{s:B(0),e:B(1),w:B(2),n:B(3),l1:B(4),r1:B(5),l2:B(6),r2:B(7),minus:B(8),plus:B(9),l:B(10),r:B(11),h:B(std?16:12),...h},ax:[0,1,2,std||g.axes.length<6||N?3:5].map(k=>{const v=g.axes[k]||0;return Math.abs(v)<.14?0:v})}};
 const buzz=s=>{try{!still.matches&&s.g&&s.g.vibrationActuator&&s.g.vibrationActuator.playEffect('dual-rumble',{duration:45,strongMagnitude:.35,weakMagnitude:.5}).catch(()=>{})}catch(e){}};
 const nodes=()=>$$('a[href],button:not([disabled]),input,[role=slider]').filter(e=>{const r=e.getBoundingClientRect();return r.width&&r.height&&!e.closest('[inert]')&&!e.matches('.skip')&&getComputedStyle(e).visibility!=='hidden'});
 const put=e=>{free();e.focus({preventScroll:true});if(e.closest('.dock,.hints,.stops'))return;const r=e.getBoundingClientRect();if(r.top<90||r.bottom>innerHeight-130)scrollTo({top:scrollY+r.top+r.height/2-innerHeight/2,behavior:still.matches?'instant':'smooth'})};
 const move=d=>{const a=document.activeElement,now=performance.now(),V=d==='up'||d==='down',sg=d==='down'||d==='right'?1:-1;run=now-runAt<900?run+1:0;runAt=now;
  if(a&&a.type==='range'&&!V){sg>0?a.stepUp():a.stepDown();a.dispatchEvent(new Event('input',{bubbles:true}));return}
  if(a&&a===grab&&V){a.dispatchEvent(new KeyboardEvent('keydown',{key:sg<0?'ArrowUp':'ArrowDown',bubbles:true}));return}
  const rg=a&&a.getAttribute('role')==='radio'&&a.closest('[role=radiogroup]');if(rg){const rs=$$('[role=radio]',rg),n=rs[rs.indexOf(a)+sg];if(n){const p=a.getBoundingClientRect(),q=n.getBoundingClientRect();if((V?Math.abs(q.top-p.top):Math.abs(q.left-p.left))>4&&!a.dispatchEvent(new KeyboardEvent('keydown',{key:V?(sg>0?'ArrowDown':'ArrowUp'):(sg>0?'ArrowRight':'ArrowLeft'),bubbles:true,cancelable:true}))){const f=document.activeElement;if(f!==a)put(f);return}}}
  const L=nodes();if(!a||a===document.body||a.id==='contenu'||d==='up'&&a.closest('.dock')||!L.includes(a)){const f=L.find(e=>{const r=e.getBoundingClientRect();return r.top>60&&r.bottom<innerHeight-60&&!e.closest('.dock,.top')})||L[0];if(f)put(f);S.step('listes',0,f);return}
  const A=a.getBoundingClientRect();let best=null,bs=1e9;for(const e of L){if(e===a||!!e.closest('.dock')!==!!a.closest('.dock'))continue;const R=e.getBoundingClientRect();if(V&&(R.right<0||R.left>innerWidth))continue;const al=V?(sg>0?R.top-A.bottom:A.top-R.bottom):(sg>0?R.left-A.right:A.left-R.right);const c=V?(R.top+R.bottom-A.top-A.bottom)/2*sg:(R.left+R.right-A.left-A.right)/2*sg;if(c<6||al<-Math.min(V?A.height:A.width,V?R.height:R.width)*.6)continue;const gap=V?Math.max(0,R.left-A.right,A.left-R.right):Math.max(0,R.top-A.bottom,A.top-R.bottom),off=Math.abs(V?(R.left+R.right-A.left-A.right)/2:(R.top+R.bottom-A.top-A.bottom)/2);if(!V&&gap>40)continue;const s=Math.max(0,al)+gap*2.4+off*.12;if(s<bs){bs=s;best=e}}
  if(best){put(best);if(!best.closest('.rail'))S.step('listes',run,best)}else S.back(a)};
 /* Une manette sert au jeu ou à Oort quand une autre fenêtre est devant. */const away=()=>document.hidden||!document.hasFocus();const tick=()=>{const s=away()?null:read();if(!s){if(seenPad&&!away()){seenPad='';was={};st.textContent=W.nopad;root.classList.remove('pad')}setTimeout(()=>requestAnimationFrame(tick),320);return}
  if(seenPad!==s.name){seenPad=s.name;was={};st.textContent=W.pad+' '+s.name.replace(/\s*\((STANDARD|Vendor).*$/i,'').slice(0,40);hb.hidden=true;S.done();[['a',s.N?'B':'A'],['b',s.N?'A':'B'],['x',s.N?'Y':'X'],['y',s.N?'X':'Y']].forEach(([k,l])=>{const e=$(`[data-p="${k}"]`,sec);if(e)e.textContent=l})}
  ax=s.ax;const on=live.has(c),b=s.b,dn=k=>b[k]&&!was[k],vis=[['s','a'],['e','b'],['w','x'],['n','y'],['h','h'],['l','l'],['r','r'],['plus','r'],['minus','l'],['up','d'],['down','d'],['left','d'],['right','d']];
  if(Object.keys(b).some(dn)||Math.hypot(ax[0],ax[1])>.5){S.boot();root.classList.add('pad')}
  vis.forEach(([k,p])=>{if(on&&dn(k))hit(p);if(b[k])lit[p]=1});
  const ok=s.N?'e':'s',no=s.N?'s':'e';let d=b.up||ax[1]<-.55?'up':b.down||ax[1]>.55?'down':b.left||ax[0]<-.55?'left':b.right||ax[0]>.55?'right':null;const now=performance.now();if(!d)rep=null;else if(!rep||rep.d!==d){rep={d,at:now+340};move(d)}else if(now>rep.at){rep.at=now+110;move(d)}
  if(dn(ok)){const e=document.activeElement;if(e&&e.getAttribute('role')==='slider'&&e!==grab){free();grab=e;e.classList.add('grab');S.lock(e);buzz(s)}else if(e===grab&&grab){free();S.press(e)}else if(e&&e!==document.body&&e.click&&!e.matches('#contenu')){e.classList.add('down');S.press(e);buzz(s);setTimeout(()=>{e.classList.remove('down');if(e.type!=='range')e.click()},90)}else move('down')}
  if(dn(no)&&grab){free();S.back()}else if(dn(no)){S.back();const e=$('.dock a[aria-current]')||$('.dock a');e&&e.focus({preventScroll:true})}
  if(dn('l1')||dn('r1')){const L=$$('.dock a'),i=L.findIndex(x=>x.hasAttribute('aria-current')),q=L[Math.max(0,Math.min(L.length-1,i+(dn('r1')?1:-1)))];if(q){S.lock(q);q.click()}}
  if((dn('l2')||dn('r2'))&&root.dataset.page==='essayer')goPan(pan+(dn('r2')?1:-1));
  if(Math.abs(ax[3])>.2)scrollBy({top:ax[3]*22,behavior:'instant'});
  was=b;requestAnimationFrame(tick)};tick();
 addEventListener('pointermove',e=>{if(e.pointerType==='mouse'&&(e.movementX||e.movementY))root.classList.remove('pad')},{passive:true});
 /* Chromium ne montre pas toujours une manette Switch en Bluetooth : la lire directement, sur choix de la personne. */
 if(navigator.hid&&hb){setTimeout(()=>{if(!seenPad)hb.hidden=false},2500);hb.addEventListener('click',async()=>{try{const [d]=await navigator.hid.requestDevice({filters:[{usagePage:1,usage:5},{usagePage:1,usage:4}]});if(!d)return;if(!d.opened)await d.open();if(hid)hid.ac.abort();const ac=new AbortController,H=hid={d,s:null,ac},signal={signal:ac.signal};const sw=d.vendorId===0x57e;if(sw)try{await d.sendReport(1,new Uint8Array([0,0,1,64,64,0,1,64,64,3,48]))}catch(e){}
  d.addEventListener('inputreport',({reportId,data:v})=>{const z=x=>Math.abs(x)<.16?0:Math.max(-1,Math.min(1,x));let b,a;if(reportId===0x30&&v.byteLength>10){const R=v.getUint8(2),M=v.getUint8(3),L=v.getUint8(4),k=o=>[(v.getUint8(o)|(v.getUint8(o+1)&15)<<8),(v.getUint8(o+1)>>4|v.getUint8(o+2)<<4)].map(x=>(x-2048)/1500),l=k(5),r=k(8);b={s:R&4,e:R&8,w:R&1,n:R&2,l1:L&64,r1:R&64,l2:L&128,r2:R&128,minus:M&1,plus:M&2,r:M&4,l:M&8,h:M&16,down:L&1,up:L&2,right:L&4,left:L&8};a=[l[0],-l[1],r[0],-r[1]]}
  else if(reportId===0x3f&&v.byteLength>10){const x=v.getUint8(0),y=v.getUint8(1),q=v.getUint8(2),k=o=>(v.getUint16(o,true)-32768)/32768;b={s:x&1,e:x&2,w:x&4,n:x&8,l1:x&16,r1:x&32,l2:x&64,r2:x&128,minus:y&1,plus:y&2,l:y&4,r:y&8,h:y&16,up:q===7||q<2,right:q>0&&q<4,down:q>2&&q<6,left:q>4&&q<8};a=[k(3),k(5),k(7),k(9)]}else return;for(const k in b)b[k]=!!b[k];H.s={name:d.productName||'Manette',N:sw,b,ax:a.map(z)}},signal);
  navigator.hid.addEventListener('disconnect',e=>{if(e.device===d){ac.abort();if(hid===H)hid=null}},signal);st.textContent=W.press}catch(e){st.textContent=W.nohid}})}
}
/* ---------- Compose : une suite de notes et une octave par endroit ---------- */
{const box=$('.compo');if(box){const cv=$('.staff canvas',box),cols=$$('[role=slider]',box),pl=$$('.places button',box),belt=$('.belt',box),su=$$('.belt button',box),win=$('.win',box),oc=$('#octave'),ov=$('#octave-v'),NN=W.notes;let k='jeux',lit=Array(8).fill(0),tm=[],drag=null;
 const o=canvas(cv,(x,w,h)=>{const L=[],G=[],n=S.tones(k),cw=w/8,q=Math.min(9,cw/6.5);n.forEach((v,i)=>{const top=14+(1-v/24)*(h-60);const e=lit[i];lit[i]*=.93;for(let y=h-14;y>top+9;y-=q)for(let m=-2;m<3;m++){const X=cw*(i+.5)+m*q+(Math.round((h-14-y)/q)%2?0:q/2)-q/4,f=1-(y-top)/(h-top);L.push([X,y,1.1+f*1.5+e*1.7,.22+f*.45+e*.5])}G.push([cw*(i+.5),top,7+e*4,1])});dots(x,L,css('--accent'));dots(x,G,'#fff')},40);
 const name=v=>NN[((Math.round(v)+7)%12+12)%12];
 const mini=su.map(b=>{const c=$('canvas',b);return canvas(c,(x,w,h)=>{const key=b.dataset.s,n=key==='toi'?S.seq[k].n||S.tones(k):S.SU[key];dots(x,n.map((v,i)=>[6+i*(w-12)/7,h-5-v/24*(h-10)*1.35,2.4,1]),b.getAttribute('aria-checked')==='true'?'#fff':css('--accent'))},8)});
 const paint=()=>{const n=S.tones(k);cols.forEach((c,i)=>{c.setAttribute('aria-valuenow',n[i]);c.setAttribute('aria-valuetext',name(n[i]))});su.forEach(b=>{const v=b.dataset.s===S.seq[k].s;b.setAttribute('aria-checked',v);b.tabIndex=v?0:-1;if(v){win.style.width=b.offsetWidth+'px';win.style.transform=`translateX(${b.offsetLeft}px)`;belt.scrollTo({left:b.offsetLeft-belt.clientWidth/2+b.offsetWidth/2,behavior:still.matches?'instant':'smooth'})}});pl.forEach(b=>b.setAttribute('aria-pressed',b.dataset.k===k));oc.value=S.seq[k].o;ov.textContent=(S.seq[k].o>0?'+':'')+S.seq[k].o;o.dirty=true;mini.forEach(m=>m.dirty=true)};
 const one=(i,vol=.15,dur=.9)=>{lit[i]=1;S.step(k,i,cols[i],vol,dur);o.dirty=true};
 const play=()=>{tm.forEach(clearTimeout);tm=S.tones(k).map((_,i)=>setTimeout(()=>{if(rootEl.dataset.page==='essayer'&&S.live)one(i,.15,i===7?1.8:.9)},i*135))};
 const set=(i,v)=>{v=Math.max(0,Math.min(24,Math.round(v)));const n=[...S.tones(k)];if(n[i]===v&&S.seq[k].s==='toi')return;const same=n[i]===v;n[i]=v;S.seq[k].n=n;S.seq[k].s='toi';S.save();paint();if(!same)one(i)};
 const pick=(b,p)=>{if(b.dataset.s==='toi'&&!S.seq[k].n)S.seq[k].n=S.tones(k).map(Math.round);S.seq[k].s=b.dataset.s;S.save();paint();if(p)play()};
 pl.forEach(b=>b.addEventListener('click',()=>{k=b.dataset.k;paint();play()}));
 /* Le curseur de blocs : on glisse, il prend le bloc sous le doigt ; au relâcher, la suite joue du début à la fin. */
 let sl=null;belt.addEventListener('pointerdown',e=>{const b=e.target.closest('button');if(b)sl={x:e.clientX,b,moved:false,id:e.pointerId,touch:e.pointerType==='touch'}});
 addEventListener('pointermove',e=>{if(!sl||e.pointerId!==sl.id||sl.touch)return;if(Math.abs(e.clientX-sl.x)>6)sl.moved=true;if(sl.moved){const r=belt.getBoundingClientRect();if(e.clientX>r.right-40)belt.scrollLeft+=8;if(e.clientX<r.left+40)belt.scrollLeft-=8;const b=su.find(x=>{const q=x.getBoundingClientRect();return e.clientX>=q.left&&e.clientX<=q.right});if(b&&b!==sl.b){sl.b=b;S.seq[k].s=b.dataset.s==='toi'&&!S.seq[k].n?S.seq[k].s:b.dataset.s;paint();one(0,.1,.5)}}});
 addEventListener('pointerup',e=>{if(!sl||e.pointerId!==sl.id)return;const m=sl.moved,b=sl.b;sl=null;if(m){pick(b,true);belt._skip=performance.now()}});addEventListener('pointercancel',()=>sl=null);
 su.forEach(b=>b.addEventListener('click',()=>{if(belt._skip&&performance.now()-belt._skip<80)return;pick(b,true)}));
 belt.addEventListener('keydown',e=>{const d={ArrowRight:1,ArrowDown:1,ArrowLeft:-1,ArrowUp:-1}[e.key];if(!d)return;e.preventDefault();e.stopPropagation();const b=su[(su.indexOf(document.activeElement)+d+su.length)%su.length];pick(b,true);b.focus({preventScroll:true})});
 cols.forEach((c,i)=>{const at=e=>{const r=cv.getBoundingClientRect();return (1-(e.clientY-r.top-14)/(r.height-60))*24};c.addEventListener('pointerdown',e=>{c.setPointerCapture(e.pointerId);drag=i;set(i,at(e));one(i)});c.addEventListener('pointermove',e=>{if(drag===i&&c.hasPointerCapture(e.pointerId))set(i,at(e))});c.addEventListener('pointerup',()=>drag=null);c.addEventListener('pointercancel',()=>drag=null);
  c.addEventListener('keydown',e=>{const v=S.tones(k)[i],d={ArrowUp:1,ArrowDown:-1,PageUp:12,PageDown:-12,Home:-24,End:24}[e.key];if(d){e.preventDefault();e.stopPropagation();set(i,v+d)}else if(e.key==='ArrowRight'||e.key==='ArrowLeft'){e.preventDefault();cols[(i+(e.key==='ArrowRight'?1:7))%8].focus()}else if(e.key==='Enter'||e.key===' '){e.preventDefault();one(i)}})});
 oc.addEventListener('input',()=>{S.seq[k].o=+oc.value;S.save();paint();one(0)});$('#ecouter').onclick=play;$('#origine').onclick=()=>{S.reset(k);S.save();paint();play()};
 document.fonts.ready.then(paint);addEventListener('resize',paint)}}
/* ---------- La route : la caméra s'éloigne du Soleil ; au bout, le nuage entier ---------- */
{const box=$('#route .track'),hold=box&&$('.hold',box);if(box){const li=$$('.stop',box),b=li.map(x=>$('button',x)),N=b.length,st=li.map(x=>x.dataset.s),nm=b.map(x=>$('strong',x).textContent);let at=0,pos=0,want=0,hov=-1;
 const ang=[.62,2.5,.95,2.25,.72,0],G=1.72,rad=k=>Math.pow(G,k),tilt=.4,GA=Math.PI*(3-Math.sqrt(5)),M=innerWidth<760?1500:2600,shell=[];
 for(let i=0;i<M;i++){const y=1-2*(i+.5)/M,r=Math.sqrt(1-y*y),a=i*GA;shell.push([Math.cos(a)*r*(.95+.05*rnd()),y*(.95+.05*rnd()),Math.sin(a)*r])}
 const geo=(w,h)=>{const m=w<900,e=Math.max(0,Math.min(1,pos-(N-2))),T=(m?Math.min(w*.39,h*.3):Math.min(w*.265,h*.43))*(1-(m?.2:.11)*e);return{m,cx:m?w*.5:w*.31,cy:m?h*.27:h*(.5-.055*e),s:T/rad(pos)}};
 const turn=(k,t)=>ang[k]+(still.matches?0:Math.sin(t*.00016+k*1.9)*.07);
 const pt=(g,k,t)=>{const a=turn(k,t),r=rad(k)*g.s;if(k===N-1)return[g.cx+Math.cos(.35)*r*.97,g.cy-Math.sin(.35)*r*.97];return[g.cx+Math.cos(a)*r,g.cy+Math.sin(a)*r*tilt]};
 const sticky=()=>!box.classList.contains('flat');
 const o=canvas($('canvas',hold),(x,w,h,t)=>{const d=want-pos;pos+=still.matches||Math.abs(d)<.0008?d:d*.11;const g=geo(w,h),L=[],H=[],P=[],lim=g.m?h*.56:h,ac=css('--accent'),night=css('--night'),sunR=Math.max(g.m?6:7,Math.min(g.m?20:30,g.s*.2));
  const edge=(X,Y)=>Math.max(0,Math.min(1,Y/50,(lim-Y)/(g.m?70:90),X/50,g.m?(w-X)/40:(w*.64-X)/(w*.07)));
  /* le nuage, tout au bout */
  const ce=Math.max(0,Math.min(1,(pos-(N-2.5))/1.2));if(ce>.01){const R=rad(N-1)*g.s,tu=still.matches?0:t*.00004,ct=Math.cos(tu),sn=Math.sin(tu);for(const q of shell){const X=q[0]*ct-q[2]*sn,Z=q[0]*sn+q[2]*ct;if(Z>.25)continue;const sx=g.cx+X*R,sy=g.cy+q[1]*R,lit=Math.max(0,X*.86-q[1]*.25),rim=Math.max(0,Math.hypot(X,q[1])-.72)/.28;L.push([sx,sy,.7+lit*1.5+rim*.7,(.05+lit*.34+rim*.3)*ce*edge(sx,sy)])}for(let j=0;j<4;j++){const m=Math.round(R*2.4/ (1+j*.2));for(let i=0;i<m;i+=1){const a=i/m*TAU+j*.02,c0=Math.cos(a),rr=R*(1-j*.02),lit=.5+.5*(c0*.86-Math.sin(a)*.25);if(j>1&&c0<.1)continue;const sx=g.cx+c0*rr,sy=g.cy+Math.sin(a)*rr;if(i%4===j%4)L.push([sx,sy,1+lit*1.6,(.16+lit*.7)*ce*edge(sx,sy)])}}}
  /* les orbites : la part faite est allumée, à partir de la planète */
  for(let k=0;k<N-1;k++){const a0=rad(k)*g.s;if(a0<sunR*1.25||a0>w*1.5)continue;const on=Math.max(0,1-Math.abs(k-pos)),q=st[k],tot=q.length,ok=[...q].filter(c=>c==='o').length/tot,nw=[...q].filter(c=>c==='n').length/tot&&[...q].filter((c,i)=>c==='n').length/tot,rows=on>.4?3:a0<60?1:2,s0=turn(k,t),al=Math.min(1,a0/(sunR*2.4)-.2);
   for(let j=0;j<rows;j++){const rr=a0+(j-(rows-1)/2)*8,n=Math.min(620,Math.round(rr*4.5/(on>.4?7.4:9.6)));for(let i=0;i<n;i++){const f=i/n,a=s0+f*TAU+(j%2)*.5/n*TAU,X=g.cx+Math.cos(a)*rr,Y=g.cy+Math.sin(a)*rr*tilt;if(X<-6||X>w+6||Y<-6||Y>lim)continue;const dep=.5+.5*Math.sin(a),done=f<ok,ed=edge(X,Y)*al,v=(.08+dep*.16)+(hov===k?.16:0);if(done&&on>.02)H.push([X,Y,1+dep*.9+on*.9,(.2+on*.8)*ed*(.55+.45*dep)]);else L.push([X,Y,.9+dep*.7+on*.5,(v+on*.2*(1-f*.5))*ed])}}}
  dots(x,L,ac);dots(x,H,'#fff');
  /* le chemin parcouru, et la comète */
  const K=Math.min(N-1,Math.max(0,pos)),i0=Math.min(N-1,Math.floor(K)),f=K-i0,path=[[g.cx,g.cy]];for(let k=0;k<=i0;k++)path.push(pt(g,k,t));if(f>.01){const A=pt(g,i0,t),B=pt(g,i0+1,t),q=f*f*(3-2*f);path.push([A[0]+(B[0]-A[0])*q,A[1]+(B[1]-A[1])*q])}
  for(let s=1;s<path.length;s++){const [ax,ay]=path[s-1],[bx,by]=path[s],len=Math.hypot(bx-ax,by-ay),n=Math.min(90,Math.floor(len/8)),vx=-(by-ay)*.16,vy=(bx-ax)*.16;for(let i=1;i<n;i++){const q=i/n,c=Math.sin(q*Math.PI),X=ax+(bx-ax)*q+vx*c,Y=ay+(by-ay)*q+vy*c;P.push([X,Y,1.35,(s===path.length-1?.35+.6*q:.4)*Math.max(.25,edge(X,Y))])}}dots(x,P,'#fff');
  /* les planètes et leurs lunes */
  for(let k=0;k<N;k++){const [X,Y]=pt(g,k,t),on=Math.max(0,1-Math.abs(k-pos)*1.5),near=Math.max(0,1-Math.abs(k-pos)*.5),a0=rad(k)*g.s;if(k<N-1&&a0<sunR*1.5||X<-40||X>w+40||Y<-40||Y>h+40)continue;const e=Math.max(on,edge(X,Y)),R=(4+near*3+on*10)*(g.m?.82:1)*(k===N-1?.7+.3*ce:1),D=[],vis=k===N-1?ce:1;if(vis<.05)continue;
   x.globalAlpha=1;x.fillStyle=night;x.beginPath();x.arc(X,Y,R+5,0,TAU);x.fill();for(let r=0;r<=R;r+=3.2){const n=Math.max(1,Math.round(r*1.95));for(let i=0;i<n;i++)D.push([X+Math.cos(i/n*TAU)*r,Y+Math.sin(i/n*TAU)*r,1.55,(.45+on*.55)*e*vis])}dots(x,D,k<=pos+.02?'#fff':ac);
   if(on>.05){const q=st[k],OK=[],NO=[];[...q].forEach((c,i)=>{const a=-Math.PI/2+i/q.length*TAU+(still.matches?0:t*.00022),mr=R+16,mx=X+Math.cos(a)*mr,my=Y+Math.sin(a)*mr;x.fillStyle=night;x.globalAlpha=on;x.beginPath();x.arc(mx,my,7,0,TAU);x.fill();if(c==='o')OK.push([mx,my,4.4,on]);else if(c==='n'){x.globalAlpha=on*(still.matches?1:.6+.4*Math.sin(t*.004+i));x.fillStyle=css('--sun');x.beginPath();x.arc(mx,my,4.2,0,TAU);x.fill()}else{x.globalAlpha=on*.8;x.strokeStyle=ac;x.lineWidth=1.5;x.setLineDash(c==='i'?[2,2.4]:[]);x.beginPath();x.arc(mx,my,3.8,0,TAU);x.stroke();x.setLineDash([])}});dots(x,OK,'#fff')}
   if(!g.m&&(on>.05||hov===k||Math.abs(k-pos)<1.6&&e>.55&&a0>sunR*3)){const act=on>.5||hov===k;x.font=`${act?600:500} 14px Inter,system-ui`;x.textBaseline='middle';x.textAlign='center';const tw=x.measureText(nm[k]).width/2,LX=Math.max(tw+16,Math.min(w*.615-tw,X)),LY=Y+R+(on>.1?34:17);x.globalAlpha=(act?Math.max(on,hov===k?1:0):.85)*vis;x.lineWidth=5;x.lineJoin='round';x.strokeStyle=night;x.strokeText(nm[k],LX,LY);x.fillStyle=act?'#fff':css('--quiet');x.fillText(nm[k],LX,LY)}}
  x.globalAlpha=.15;x.fillStyle=css('--sun');x.beginPath();x.arc(g.cx,g.cy,sunR*1.85,0,TAU);x.fill();x.globalAlpha=1;x.beginPath();x.arc(g.cx,g.cy,sunR,0,TAU);x.fill()},60);
 const paint=k=>{if(k===at)return;at=k;li.forEach((x,i)=>{x.classList.toggle('on',i===k);b[i].setAttribute('aria-expanded',i===k);const m=$('.more',x);m.inert=i!==k});S.step('listes',k,b[k],.1,.9);o.dirty=true};li.forEach((x,i)=>{x.classList.toggle('on',i===0);$('.more',x).inert=i!==0});
 const span=()=>box.offsetHeight-hold.offsetHeight;
 const fromScroll=()=>{if(rootEl.dataset.page!=='route'||!sticky())return;const p=Math.max(0,Math.min(1,-box.getBoundingClientRect().top/Math.max(1,span())))*(N-1);/* un palier autour de chaque étape : on s'y pose */const q=Math.floor(p),f=p-q,e=Math.max(0,Math.min(1,(f-.18)/.64));want=q+e*e*(3-2*e);o.dirty=true;paint(Math.round(p))};
 const go=(k,f)=>{k=Math.max(0,Math.min(N-1,k));if(f)b[k].focus({preventScroll:true});if(sticky())scrollTo({top:scrollY+box.getBoundingClientRect().top+span()*k/(N-1),behavior:still.matches?'instant':'smooth'});else{want=k;paint(k);o.dirty=true}};
 const fit=()=>{if(rootEl.dataset.page!=='route')return;box.classList.remove('flat');box.classList.add('nt');const ov=$('.over',hold);let tall=0;li.forEach((x,i)=>{li.forEach((y,j)=>y.classList.toggle('on',i===j));tall=Math.max(tall,ov.scrollHeight)});li.forEach((y,j)=>y.classList.toggle('on',j===at));void ov.offsetHeight;box.classList.remove('nt');if(tall>hold.clientHeight+2||innerHeight<560)box.classList.add('flat');fromScroll();o.dirty=true};
 addEventListener('scroll',fromScroll,{passive:true});addEventListener('resize',fit);document.fonts.ready.then(fit);
 b.forEach((x,k)=>{x.addEventListener('click',()=>{history.replaceState(null,'','#'+x.id);go(k)});x.addEventListener('pointerenter',e=>{if(e.pointerType==='mouse'){hov=k;o.dirty=true}});x.addEventListener('pointerleave',()=>{hov=-1;o.dirty=true});x.addEventListener('focus',()=>{if(rootEl.classList.contains('pad')&&k!==at)go(k)});
  x.addEventListener('keydown',e=>{const d={ArrowDown:1,ArrowRight:1,ArrowUp:-1,ArrowLeft:-1}[e.key];if(d){e.preventDefault();e.stopPropagation();go(at+d,true)}})});
 const near=e=>{const R=o.c.getBoundingClientRect(),g=geo(o.w,o.h),X=e.clientX-R.left,Y=e.clientY-R.top;let bk=-1,bd=1e9;for(let k=0;k<N;k++){const p=pt(g,k,performance.now()),r=rad(k)*g.s,d=Math.min(Math.hypot(p[0]-X,p[1]-Y),k<N-1?Math.abs(Math.hypot((X-g.cx)/r,(Y-g.cy)/(r*tilt))-1)*r*tilt:Math.abs(Math.hypot(X-g.cx,Y-g.cy)-r));if(d<bd){bd=d;bk=k}}return bd<60?bk:-1};
 o.c.addEventListener('click',e=>{const k=near(e);if(k>=0)go(k)});o.c.addEventListener('pointermove',e=>{if(e.pointerType!=='mouse')return;const k=near(e);if(k!==hov){hov=k;o.c.style.cursor=k>=0?'pointer':'';o.dirty=true}},{passive:true});
 const deep=()=>{const k=b.findIndex(x=>'#'+x.id===location.hash);if(k>=0)setTimeout(()=>{fit();go(k)},still.matches?30:360)};addEventListener('hashchange',deep);addEventListener('popstate',deep);addEventListener('click',e=>{const a=e.target.closest&&e.target.closest('a[href^="#route-"]');if(a)setTimeout(deep,10)});deep()}}
/* ---------- Le journal : l'empreinte suit la version qu'on lit ---------- */
{const g=$('#grand'),rels=$$('.rel');if(g){const num=c=>c.dataset.n.split(',').map(Number),N=rels.map(r=>num($('.emb',r))),B=$('.stick .big'),B2=$('.stick .sub2');let cur=0,to=0,p=1,hot=-1,pts=[];const label=()=>{B.textContent=$('.ver h3',rels[to]).textContent;B2.textContent=$('.meta time',rels[to]).textContent};
 const pal=()=>({accent:css('--accent'),night:css('--night'),sun:css('--sun')});
 const o=canvas(g,(x,w,h,t)=>{if(cur!==to||p<1){p=still.matches?1:p+.055;if(p>=.5&&cur!==to)cur=to;if(p>=1)p=1}const k=p>=1?1:p<.5?1-p*2:(p-.5)*2,z=1-Math.pow(1-k,3);x.save();x.translate(w/2,h/2);x.scale(.12+.88*z,.12+.88*z);x.rotate((1-z)*.9);x.translate(-w/2,-h/2);pts=Embleme(x,w,h,N[cur],{t:still.matches?0:t,on:hot,c:pal()});x.restore();if(p<1)o.dirty=true},40);
 $$('.emb').forEach(c=>canvas(c,(x,w,h,t)=>Embleme(x,w,h,num(c),{t:still.matches?0:t,on:-1,c:pal(),fine:w>90}),12));
 const spyV=()=>{if(rootEl.dataset.page!=='versions')return;let i=0,bd=1e9;rels.forEach((r,k)=>{if(r.hidden)return;const R=r.getBoundingClientRect(),d=R.top>innerHeight*.45?1e8+R.top:Math.max(0,innerHeight*.3-R.bottom);if(d<bd){bd=d;i=k}});if(i!==to){to=i;p=0;hot=-1;label();rels.forEach((r,k)=>r.classList.toggle('on',k===i));o.dirty=true;S.step('listes',i,rels[i],.05)}};
 rels.forEach((r,k)=>$$('[data-i]',r).forEach(l=>{l.addEventListener('pointerenter',e=>{if(e.pointerType==='mouse'&&k===to){hot=+l.dataset.i;o.dirty=true;S.step('listes',hot,l,.035)}});l.addEventListener('pointerleave',()=>{hot=-1;o.dirty=true})}));
 const chips=$$('#versions .chips button');chips.forEach(c=>c.addEventListener('click',()=>{chips.forEach(x=>x.setAttribute('aria-pressed',x===c));rels.forEach(r=>{r.hidden=!!c.dataset.p&&!r.dataset.p.split(' ').includes(c.dataset.p)});S.step('listes',chips.indexOf(c),c,.09);spyV()}));
 rels[0]&&rels[0].classList.add('on');label();addEventListener('scroll',spyV,{passive:true});addEventListener('resize',spyV)}}
/* ---------- Installer : ton appareil d'abord ---------- */
{const tabs=$$('.picker [role=tab]'),ua=navigator.userAgent,me=/android/i.test(ua)?'android':/iphone|ipad|ipod/i.test(ua)||/Macintosh/.test(ua)&&navigator.maxTouchPoints>1?'ios':/windows/i.test(ua)?'windows':/mac/i.test(ua)?'mac':/linux|x11/i.test(ua)?'linux':'mac';
 const pick=(t,f,quiet)=>{tabs.forEach(x=>{const on=x===t;x.setAttribute('aria-selected',on);x.tabIndex=on?0:-1;$('#'+x.getAttribute('aria-controls')).hidden=!on});if(f)t.focus({preventScroll:true});if(!quiet)S.step('listes',tabs.indexOf(t),t,.09);$$('canvas',$('#'+t.getAttribute('aria-controls'))).forEach(c=>c._o&&(c._o.dirty=true))};
 tabs.forEach((t,i)=>{t.addEventListener('click',()=>pick(t));t.addEventListener('keydown',e=>{const d={ArrowRight:1,ArrowDown:1,ArrowLeft:-1,ArrowUp:-1}[e.key];if(d){e.preventDefault();e.stopPropagation();pick(tabs[(i+d+tabs.length)%tabs.length],true)}});if(t.dataset.p===me){t.classList.add('mine');const s=document.createElement('b');s.className='sr';s.textContent=t.parentElement.dataset.here;t.append(s);pick(t,false,true)}});
 const of=W.offers[me];$$('.get-mine').forEach(a=>{if(of){a.href=of.u;$('span',a).textContent=of.t}else{a.href='#installer';$('span',a).textContent=W.all}});if(me!=='mac'){const c=$('#compat'),q=c.textContent.split(' · ');c.textContent=of?of.c:q[1][0].toUpperCase()+q[1].slice(1)+' · Mac '+q[0]}
 $$('.sha').forEach(b=>b.addEventListener('click',async()=>{const s=$('span',b),q=s.textContent;try{await navigator.clipboard.writeText(b.dataset.sha);s.textContent=b.dataset.done;S.done()}catch(e){s.textContent=b.dataset.sha}setTimeout(()=>s.textContent=q,1600)}))}
/* ---------- Choix, interrupteurs, taille, joueurs, données, palettes ---------- */
$$('[data-radio]').forEach(g=>{const b=$$('[role=radio]',g);const pick=(x,f)=>{b.forEach(y=>{y.setAttribute('aria-checked',y===x);y.tabIndex=y===x?0:-1});S.step('listes',b.indexOf(x),x,.09);if(f)x.focus();if(x.dataset.theme!==undefined){x.dataset.theme?document.documentElement.dataset.theme=x.dataset.theme:delete document.documentElement.dataset.theme;$$('canvas').forEach(c=>c._o&&(c._o.dirty=true))}};b.forEach(x=>x.addEventListener('click',()=>pick(x)));g.addEventListener('keydown',e=>{const d={ArrowDown:1,ArrowRight:1,ArrowUp:-1,ArrowLeft:-1}[e.key];if(d){e.preventDefault();e.stopPropagation();const i=b.indexOf(document.activeElement);pick(b[(i+d+b.length)%b.length],true)}})});
{const box=$('#reglages'),rows=$$('[role=switch]',box),dr=$('.draft',box),saved=rows.map(r=>r.getAttribute('aria-checked'));const chk=()=>{const on=rows.some((r,i)=>r.getAttribute('aria-checked')!==saved[i]);dr.classList.toggle('on',on);if(!on&&dr.contains(document.activeElement))rows[0].focus({preventScroll:true});dr.inert=!on};rows.forEach(r=>r.addEventListener('click',()=>{const v=r.getAttribute('aria-checked')!=='true';r.setAttribute('aria-checked',v);S.toggle(v,r);chk()}));$('#garder').onclick=()=>{rows.forEach((r,i)=>saved[i]=r.getAttribute('aria-checked'));S.done();chk()};$('#jeter').onclick=()=>{rows.forEach((r,i)=>r.setAttribute('aria-checked',saved[i]));S.back();chk()};chk()}
{const i=$('#zoom'),s=$('.sample'),o=$('#zoom-v');let l=0;i.addEventListener('input',()=>{s.style.transform=`scale(${i.value/100*1.05})`;o.textContent=i.value+' %';if(performance.now()-l>45){l=performance.now();S.slide((i.value-80)/45)}})}
{const b=$$('.seat'),n=$('#places');const say=()=>{const k=b.filter(x=>x.getAttribute('aria-pressed')==='true').length;n.textContent=W.seats(k)};b.forEach((x,i)=>x.addEventListener('click',()=>{const v=x.getAttribute('aria-pressed')!=='true';x.setAttribute('aria-pressed',v);v?S.step('joueurs',i,x,.09):S.back(x);say()}));say()}
{const box=$('#donnees');$$('[role=switch]',box).forEach(r=>r.addEventListener('click',()=>{const v=r.getAttribute('aria-checked')!=='true';r.setAttribute('aria-checked',v);$(`.l[data-l="${r.dataset.l}"]`,box).classList.toggle('on',v);S.toggle(v,r)}))}
/* ---------- Petites figures ---------- */
const mini=(c,f)=>canvas(c,(x,w,h,t)=>{const L=[];f(L,w,h,still.matches?0:t);dots(x,L,css('--accent'))},24);
$$('.steps canvas').forEach((c,n)=>{const k=n%3;mini(c,(L,w,h,t)=>{const a=(t*.001)%1.6;if(k===0){for(let y=0;y<9;y++)for(let i=0;i<5;i++){if(y>4&&Math.abs(i-2)>8-y-.5+0)continue;if(y<=4&&Math.abs(i-2)>1)continue;const p=((y/9-a*.7)%1+1)%1;L.push([w/2+(i-2)*9,12+y*8,2.6,.35+.65*(1-p)])}}else if(k===1){for(let i=0;i<16;i++){const g=i/16*TAU;L.push([w*.25+Math.cos(g)*13+Math.min(1,a)*w*.4*(i%2?1:1),h/2+Math.sin(g)*13,2.5,1])}for(let i=0;i<9;i++)for(const y of [14,h-14])L.push([w*.52+i*5.4,y,2,.55]);for(let i=0;i<12;i++)L.push([w*.97,14+i*(h-28)/11,2,.55],[w*.5,14+i*(h-28)/11,2,.55])}else for(let j=0;j<4;j++){const n=14+j*8;for(let i=0;i<n;i++){const g=i/n*TAU;L.push([w/2+Math.cos(g)*(10+j*10),h/2+Math.sin(g)*(10+j*10),2.5-j*.25,Math.max(.2,1-Math.abs(a*3-j)*.5)])}}})});
{const c=$('#fin canvas');if(c)canvas(c,(x,w,h,t)=>{const L=[],s=w*.46,b=still.matches?0:t*.0004;for(const [gx,gy,gr] of W.glyph){L.push([w/2+gx/1000*s,h/2+gy/1000*s,gr/1e4*s*(1+.14*Math.sin(b*5+gx*.006+gy*.004)),1])}dots(x,L,css('--silver'));x.fillStyle=css('--sun');x.beginPath();x.arc(w/2,h/2,s*.075,0,TAU);x.fill()},24)}
requestAnimationFrame(loop);
})();
