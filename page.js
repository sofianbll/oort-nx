/* L'empreinte d'une version : le Soleil, trois anneaux (nouveau, mieux, réparé), un gros point par changement. */
window.Embleme=(x,w,h,n,o)=>{const TAU=Math.PI*2,R=Math.min(w,h)*.47,cx=w/2,cy=h/2,c=o.c,t=o.t||0,fine=o.fine!==false,ring=[.94,.68,.43],pts=[];let k=0;
 const put=(X,Y,r,a,f)=>{x.globalAlpha=Math.min(1,a);x.fillStyle=f;x.beginPath();x.arc(X,Y,r,0,TAU);x.fill()};
 for(let g=0;g<3;g++){const q=ring[g]*R,turn=t*.00005*(g%2?-1:1);if(fine)for(let j=-2;j<=2;j++){const rr=q+j*R*.052,m=Math.max(10,Math.round(rr*TAU/(R*.062)));for(let i=0;i<m;i++){const a=i/m*TAU+turn*1.6+j*.02,lit=.5+.5*Math.cos(a+.7);put(cx+Math.cos(a)*rr,cy+Math.sin(a)*rr,R*(.0085+.009*lit*(1-Math.abs(j)/3)),(.1+.36*lit)*(1-Math.abs(j)/3.4)*(n[g]?1:.45),c.accent)}}
  for(let i=0;i<n[g];i++,k++){const a=-Math.PI/2+i/Math.max(1,n[g])*TAU+turn+g*.6,on=o.on===k,X=cx+Math.cos(a)*q,Y=cy+Math.sin(a)*q,r=R*(fine?.047:.075)*(on?1.5:1);pts.push([X,Y,k]);x.globalAlpha=1;x.fillStyle=c.night;x.beginPath();x.arc(X,Y,r*1.6,0,TAU);x.fill();put(X,Y,r,o.on>=0&&!on?.5:1,'#fff')}}
 put(cx,cy,R*.15,1,c.sun);x.globalAlpha=1;return pts};
document.addEventListener('touchstart',()=>{},{passive:true});
(()=>{const still=matchMedia('(prefers-reduced-motion:reduce)'),css=n=>getComputedStyle(document.documentElement).getPropertyValue(n).trim();
document.querySelectorAll('canvas.emb').forEach(c=>{const x=c.getContext('2d'),n=c.dataset.n.split(',').map(Number),host=c.closest('article');let on=-1,vis=true,w=0,h=0;const fit=()=>{const r=c.getBoundingClientRect(),d=Math.min(devicePixelRatio||1,2);w=r.width;h=r.height;c.width=w*d;c.height=h*d;x.setTransform(d,0,0,d,0,0);draw(performance.now())};
 const draw=t=>{if(!w)return;x.clearRect(0,0,w,h);Embleme(x,w,h,n,{t:still.matches?0:t,on,c:{accent:css('--accent'),night:css('--night'),sun:css('--sun')}})};
 if(host)host.querySelectorAll('[data-i]').forEach(l=>{l.addEventListener('pointerenter',()=>{on=+l.dataset.i;draw(performance.now())});l.addEventListener('pointerleave',()=>{on=-1;draw(performance.now())})});
 new ResizeObserver(fit).observe(c);new IntersectionObserver(e=>{vis=e[0].isIntersecting}).observe(c);let last=0;const loop=t=>{if(vis&&!document.hidden&&!still.matches&&t-last>40){last=t;draw(t)}requestAnimationFrame(loop)};requestAnimationFrame(loop)});
document.querySelectorAll('.sha').forEach(b=>b.addEventListener('click',async()=>{const s=b.querySelector('span'),o=s.textContent;try{await navigator.clipboard.writeText(b.dataset.sha);s.textContent=b.dataset.done}catch(e){s.textContent=b.dataset.sha}setTimeout(()=>s.textContent=o,1600)}))})();
