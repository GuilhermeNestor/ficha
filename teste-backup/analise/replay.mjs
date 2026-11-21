import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
const pasta=path.dirname(fileURLToPath(import.meta.url));
const entrada=process.argv[2];
if(!entrada){console.error('Uso: node analise/replay.mjs gravacoes.json [resultado.json]');process.exit(1);}
const pacote=JSON.parse(fs.readFileSync(entrada,'utf8'));
if(pacote.formato!=='ficha-treino-coletas'||pacote.versao!==1||!Array.isArray(pacote.gravacoes))throw Error('Exportação incompatível');
const nomes=['simples','direcao','dtw'];
const fontes=Object.fromEntries(nomes.map(n=>[n,fs.readFileSync(path.join(pasta,`detector-${n}.js`),'utf8')]));
const limpar=s=>s.replace(/import[\s\S]*?from\s+['"][^'"]+['"];?/g,'').replace(/export /g,'');
const fabrica=nome=>{
 const ctx=vm.createContext({Math,Number,Array,JSON});
 vm.runInContext(limpar(fontes.simples),ctx);
 if(nome!=='simples')vm.runInContext(`(function(){${limpar(fontes[nome])};globalThis.fabrica=criarDetectorAdaptativo;})()`,ctx);
 return nome==='simples'?()=>{
   let det=ctx.criarDetector({deltaMin:60,fatorDelta:.35,intervaloMin:700,atrasoInicial:1200});let bloqueio=0;
   return{feed:(x,y,z,t)=>t<bloqueio?0:det.feed(x,y,z,t)?1:0,estado:()=>({fimSerie:false}),
     pausaVibracao:t=>{det.reiniciar(t);bloqueio=t+450;},exportarModelo:()=>null};
 }:ctx.fabrica;
};
const criar=Object.fromEntries(nomes.map(n=>[n,fabrica(n)]));
const modelos={direcao:new Map(),dtw:new Map()};const resultados=[];
for(const g of pacote.gravacoes.slice().sort((a,b)=>a.inicio-b.inicio)){
 const gabarito=g.rotulos?.repsReais??g.repsReais;
 const elegivel=Number.isInteger(gabarito)&&!g.truncada&&!g.interrompida;
 const fim=g.fimManualMs??g.duracaoMs;
 const chave=JSON.stringify([g.sessaoId,g.exercicioId]);const testes={};
 for(const nome of nomes){
   const inicial=nome==='direcao'?(g.modeloInicial||modelos.direcao.get(chave)):nome==='dtw'?modelos.dtw.get(chave):null;
   const det=criar[nome]({modelo:inicial});let quantidade=0,apos=0,terminou=null;
   const marcas=[];const eventos=(g.eventos||[]).filter(e=>e.tipo==='vibracao_meta').sort((a,b)=>a.t-b.t);let e=0;
   const aplicar=t=>{while(e<eventos.length&&eventos[e].t<=t){det.pausaVibracao(g.inicio+eventos[e].t);e++;}};
   for(const a of g.amostras){
     aplicar(a[0]-1);
     const n=det.feed(a[1],a[2],a[3],g.inicio+a[0]);
     if(n){marcas.push({t:a[0],quantidade:n});if(a[0]<=fim)quantidade+=n;else apos+=n;}
     if(terminou===null&&det.estado(g.inicio+a[0]).fimSerie)terminou=a[0];
     aplicar(a[0]);
   }
   const modelo=det.exportarModelo();if(modelo&&nome!=='simples')modelos[nome].set(chave,modelo);
   testes[nome]={contadas:quantidade,aposFimManual:apos,erroTotal:elegivel?quantidade-gabarito:null,
     fimAutomaticoMs:terminou,marcas};
 }
 resultados.push({id:g.id,exercicio:g.exercicioNome,serie:g.serie,gabarito,elegivel,
   papel:g.serie===1?'ajuste':'validacao_sugerida',fimManualMs:fim,amostras:g.amostras.length,testes});
}
const resumo=Object.fromEntries(nomes.map(nome=>{
 const validos=resultados.filter(r=>r.elegivel&&r.papel==='validacao_sugerida');
 return[nome,{series:validos.length,erroAbsolutoMedio:validos.length?
  validos.reduce((s,r)=>s+Math.abs(r.testes[nome].erroTotal),0)/validos.length:null,
  contagensAposFim:validos.reduce((s,r)=>s+r.testes[nome].aposFimManual,0)}];
}));
const saida={versao:1,observacoes:[
 'Total real não permite localizar cada falso positivo ou repetição perdida.',
 'Fim manual é uma marca do usuário e pode ocorrer depois da última repetição.',
 'Não ajustar parâmetros usando as séries reservadas para validação.',
 'Arquivos usam os mesmos sinais arredondados e eventos de vibração capturados.',
 'O DTW é a reprodução experimental da abordagem anterior; não é um algoritmo validado.',
],fontes:Object.fromEntries(nomes.map(n=>[n,crypto.createHash('sha256').update(fontes[n]).digest('hex')])),resumo,resultados};
const destino=process.argv[3]||path.join(path.dirname(entrada),'comparacao-detectores.json');
fs.writeFileSync(destino,JSON.stringify(saida,null,2));console.table(resumo);console.log(destino);
