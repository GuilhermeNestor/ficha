import { criarDetector } from './detector-simples.js';
const N=32;
const clone=v=>JSON.parse(JSON.stringify(v));
function forma(a){
 if(a.length<10)return null;
 const inicio=a[0].t,duracao=a[a.length-1].t-inicio;
 if(duracao<650||duracao>10000)return null;
 let j=0;const f=[];
 for(let i=0;i<N;i++){
  const t=inicio+duracao*i/(N-1);while(j<a.length-2&&a[j+1].t<t)j++;
  const k=Math.max(0,Math.min(1,(t-a[j].t)/Math.max(1,a[j+1].t-a[j].t)));
  f.push(a[j].v.map((v,e)=>v+(a[j+1].v[e]-v)*k));
 }
 const media=[0,1,2].map(e=>f.reduce((s,v)=>s+v[e],0)/N);let soma=0;
 f.forEach(v=>v.forEach((_,e)=>{v[e]-=media[e];soma+=v[e]*v[e];}));
 const amplitude=Math.sqrt(soma/(N*3));if(amplitude<20)return null;
 f.forEach(v=>v.forEach((_,e)=>v[e]/=amplitude));
 return{versao:1,duracao,amplitude,forma:f};
}
function score(a,b){let prev=Array(N+1).fill(Infinity);prev[0]=0;
 for(let i=1;i<=N;i++){const next=Array(N+1).fill(Infinity);
  for(let j=Math.max(1,i-4);j<=Math.min(N,i+4);j++)next[j]=
   a.forma[i-1].reduce((s,v,k)=>s+(v-b.forma[j-1][k])**2,0)+Math.min(prev[j],next[j-1],prev[j-1]);
  prev=next;
 }return Math.max(0,1-Math.sqrt(prev[N]/(N*3))/2);
}
const combina=(a,b,rigor=.78)=>a.duracao/b.duracao>=.45&&a.duracao/b.duracao<=2.4&&
 a.amplitude/b.amplitude>=.35&&a.amplitude/b.amplitude<=2.8&&score(a,b)>=rigor;
// Reprodução da abordagem experimental de DTW: calibração em 3 ciclos,
// confirmação do início em 2 ciclos e contagem em bloco.
export function criarDetectorAdaptativo(opcoes={}){
 let modelo=opcoes.modelo?.versao===1?clone(opcoes.modelo):null;
 let det,a,cal,pending,suave,prev,coleta,ultimo,ativo,fim,bloqueio=0;
 const reset=()=>{det=criarDetector({deltaMin:60,fatorDelta:.35,intervaloMin:650,atrasoInicial:900});
  a=[];cal=[];pending=[];suave=null;prev=coleta=ultimo=null;ativo=fim=false;};reset();
 const pausa=()=>Math.max(5000,Math.min(24000,modelo?modelo.duracao*2.4+1200:5000));
 const aceita=(c,t)=>{
  if(!modelo){if(cal.length&&!cal.every(x=>combina(c,x,.82)))cal=[];
   cal.push(c);if(cal.length<3)return 0;
   const sorted=cal.slice().sort((x,y)=>cal.reduce((s,z)=>s+score(y,z),0)-cal.reduce((s,z)=>s+score(x,z),0));
   modelo=clone(sorted[0]);modelo.duracao=cal.map(x=>x.duracao).sort((x,y)=>x-y)[1];
   modelo.amplitude=cal.map(x=>x.amplitude).sort((x,y)=>x-y)[1];cal=[];ativo=true;ultimo=t;return 3;}
  if(!combina(c,modelo)){pending=[];return 0;}
  if(!ativo){if(pending.length&&!combina(c,pending[0]))pending=[];pending.push(c);
   if(pending.length<2)return 0;pending=[];ativo=true;ultimo=t;return 2;}
  ultimo=t;if(score(c,modelo)>=.90){const novo=Math.max(modelo.duracao*.9,Math.min(modelo.duracao*1.1,c.duracao));modelo.duracao=modelo.duracao*.8+novo*.2;}return 1;
 };
 return {
 feed(x,y,z,t){if(![x,y,z,t].every(Number.isFinite)||fim||t<bloqueio)return 0;
  if(prev!==null&&t<=prev)return 0;if(prev!==null&&t-prev>1000)reset();
  const dt=prev===null?40:t-prev;prev=t;if(!suave)suave=[x,y,z];
  [x,y,z].forEach((v,k)=>suave[k]+=(v-suave[k])*dt/(80+dt));
  if(coleta===null||t-coleta>=40){a.push({t,v:suave.slice()});coleta=t;}
  if(a.length&&t-a[0].t>14000){a=[];cal=[];pending=[];}let n=0;
  if(det.feed(x,y,z,t)){const c=forma(a);a=[{t,v:suave.slice()}];coleta=t;
   if(c)n=aceita(c,t);else{cal=[];pending=[];}}
  if(ativo&&ultimo!==null&&t-ultimo>=pausa())fim=true;return n;},
 estado:()=>({fimSerie:fim}),exportarModelo:()=>modelo?clone(modelo):null,
 suspender(t,ms=0){reset();bloqueio=t+ms;},
 pausaVibracao(t){const ativoAntes=ativo;reset();ativo=ativoAntes;bloqueio=t+450;ultimo=ativo?bloqueio:null;},
 };
}
