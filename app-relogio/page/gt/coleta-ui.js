import * as hmUI from '@zos/ui';
import { px } from '@zos/utils';
import { TESTE, VAGAS, MAX_AMOSTRAS, MAX_DURACAO, listarGravacoes, salvarGravacao } from './gravacoes.js';
import { contarEventos, resumoTexto } from './multi-detectores.js';

export function criarColeta({ficha, ex, serie, sessaoId, carga, reps, modelo, extras = () => ({}), iniciar, podeIniciar, aoGabarito = () => {}, aoTerminar = () => {}}) {
  let g = null, etapa = 'ociosa', timer = null, depois = null;
  let reais = 0, acumulado = 0, widgets = [], mensagem = null, numero = null, fimCaudaEm = 0;
  const texto = (x,y,w,h,text,size=20) => hmUI.createWidget(hmUI.widget.TEXT, {
    x:px(x),y:px(y),w:px(w),h:px(h),text,text_size:px(size),color:0xffffff,
    align_h:hmUI.align.CENTER_H,align_v:hmUI.align.CENTER_V,text_style:hmUI.text_style.WRAP,
  });
  const botao = (x,y,w,h,text,click_func) => hmUI.createWidget(hmUI.widget.BUTTON,{
    x:px(x),y:px(y),w:px(w),h:px(h),radius:px(16),text,text_size:px(18),
    normal_color:0x28330f,press_color:0x485c1b,color:0xb6ff00,click_func,
  });
  const ocultar = () => {widgets.forEach(w=>w.setProperty(hmUI.prop.VISIBLE,false));widgets=[];};
  let ultimaEtiqueta = 'FIM';
  const etiqueta = t => {if(btn && t!==ultimaEtiqueta){ultimaEtiqueta=t;btn.setProperty(hmUI.prop.MORE,{text:t});}};
  const evento = (tipo, dados={}) => {
    if(g && etapa!=='ociosa' && etapa!=='gabarito')
      g.eventos.push({t:Math.max(0,Date.now()-g.inicio),tipo,...dados});
  };
  const abrir = (auto = false) => {
    if(etapa==='gravando'){aoTerminar();return;}
    if(etapa!=='ociosa' || !podeIniciar()) return;
    if(reps()!==0){etiqueta(auto?'S/ REC':'ANTES\nDA SÉRIE');return;}   // série retomada no meio: não grava
    try {
      if(listarGravacoes().length>=VAGAS) throw new Error('Sincronize');
      const inicio=Date.now();
      g={versao:1,id:`coleta_${inicio}_${Math.random().toString(36).slice(2,10)}`,
        inicio,sessaoId,fichaId:ficha.id,fichaNome:ficha.nome,exercicioId:ex.id,exercicioNome:ex.nome,
        serie,carga:carga(),meta:ex.reps,unidade:'cm/s2',formato:['t_ms','x','y','z'],
        detector:'multi-v1-coleta3',modeloInicial:modelo(),
        captura:{versao:2,modoSensor:'NORMAL',intervaloMinMs:40},
        amostras:[],eventos:[],repsReais:null,truncada:false,interrompida:false,
        rotulos:{observacao:'',repsAtipicas:[],temposReais:[]}};
      etapa='gravando';iniciar();evento('inicio');etiqueta('FIM');
    }catch(e){etiqueta('SINCRONIZE');g=null;etapa='ociosa';}
  };
  const btn=TESTE?botao(32,160,86,48,'FIM',()=>abrir(false)):null;
  const amostra=(a,t,n,estado,outros)=>{
    if(!g || (etapa!=='gravando' && etapa!=='cauda')) return;
    if(etapa==='cauda' && Date.now()>=fimCaudaEm){gabarito();return;}
    const rel=t-g.inicio;
    if(rel<0){g.truncada=true;return;}
    if(g.amostras.length>=MAX_AMOSTRAS || rel>MAX_DURACAO){g.truncada=true;etiqueta('LIMITE');return;}
    const anterior=g.amostras[g.amostras.length-1];
    if(anterior && rel<=anterior[0])return;
    g.amostras.push([rel,Math.round(a.x),Math.round(a.y),Math.round(a.z)]);
    if(n>0)g.eventos.push({t:rel,tipo:'rep_detector',quantidade:n});
    if(outros)for(const nome in outros)g.eventos.push({t:rel,tipo:'rep_outro',detector:nome,quantidade:outros[nome]});
    if(estado.fimSerie && !g.fimAutomaticoMs){g.fimAutomaticoMs=rel;evento('fim_detector');}
  };
  // contagem de cada detector (da série e depois do FIM) + tempo de processamento de cada um
  const fecharDetectores=()=>{
    g.repsPorDetector=contarEventos(g.eventos,g.fimManualMs);
    try{const x=extras();g.detectores=x.nomes;g.cpu=x.cpu;}catch(_){}
  };
  const salvar=()=>{
    if(etapa!=='gabarito')return;
    try {
      if (!g.amostras.length) throw new Error('Sem leituras do sensor');
      g.repsReais=reais;
      salvarGravacao(g);
      etapa='ociosa';g=null;ocultar();etiqueta('GRAVAR');
      const cb=depois;depois=null;if(cb)cb();
    }catch(e){mensagem.setProperty(hmUI.prop.TEXT,`Não salvou: ${e.message}\nClique para tentar novamente.`);}
  };
  const gabarito=()=>{
    if(!g || etapa==='gabarito')return;
    if(timer!==null){clearTimeout(timer);timer=null;}
    etapa='gabarito';reais=0;aoGabarito();
    g.duracaoMs=g.amostras.length?g.amostras[g.amostras.length-1][0]:0;
    g.repsDetectadas=g.eventos.filter(e=>e.tipo==='rep_detector').reduce((n,e)=>n+e.quantidade,0);
    g.repsDetectadasSerie=g.eventos.filter(e=>e.tipo==='rep_detector' && e.t<=(g.fimManualMs??Infinity)).reduce((n,e)=>n+e.quantidade,0);
    g.repsAposFim=g.repsDetectadas-g.repsDetectadasSerie;
    fecharDetectores();
    widgets.push(hmUI.createWidget(hmUI.widget.FILL_RECT,{x:0,y:0,w:px(480),h:px(480),color:0}));
    widgets.push(texto(110,55,260,40,'REPETIÇÕES REAIS',23));
    mensagem=texto(95,105,290,58,'Informe o total que você fez.\nGire a coroa ou use − / +.',18);widgets.push(mensagem);
    numero=texto(150,182,180,80,'0',64);widgets.push(numero);
    widgets.push(botao(65,198,70,56,'−',()=>mudar(reais-1)));
    widgets.push(botao(345,198,70,56,'+',()=>mudar(reais+1)));
    widgets.push(texto(100,280,280,48,`Detector: ${g.repsDetectadasSerie} + ${g.repsAposFim} após\n${g.truncada?'Gravação parcial':'Gravação completa'}`,18));
    widgets.push(texto(60,328,360,32,resumoTexto(g.repsPorDetector),15));
    widgets.push(botao(120,365,240,60,'SALVAR',salvar));
  };
  const mudar=n=>{reais=Math.max(0,Math.min(300,n));numero.setProperty(hmUI.prop.TEXT,String(reais));};
  const finalizar=cb=>{
    if(etapa==='ociosa')return false;
    if(etapa!=='gravando')return true;
    depois=cb;g.repsTelaNoFim=reps();g.fimManualMs=Math.max(0,Date.now()-g.inicio);evento('fim_manual');
    etapa='cauda';etiqueta('MAIS 5s');fimCaudaEm=Date.now()+5000;
    timer=setTimeout(()=>{timer=null;if(etapa==='cauda')gabarito();},5000);
    return true;
  };
  // Grava desde o começo da série, sem precisar tocar em nada.
  if(TESTE) abrir(true);
  return {
    ativa:()=>etapa!=='ociosa',
    bloqueia:()=>etapa==='cauda'||etapa==='gabarito',
    amostra,evento,finalizar,
    coroa:degree=>{
      if(etapa!=='gabarito')return false;
      acumulado-=degree;
      if(Math.abs(acumulado)>=5){mudar(reais+(acumulado>0?1:-1));acumulado=0;}
      return true;
    },
    clique:()=>{if(etapa==='gabarito'){salvar();return true;}return etapa==='cauda';},
    destruir:()=>{
      if(timer!==null)clearTimeout(timer);
      if(g && g.amostras.length){
        g.interrompida=true;g.repsReais=null;
        g.duracaoMs=g.amostras[g.amostras.length-1][0];
        g.repsDetectadas=g.eventos.filter(e=>e.tipo==='rep_detector').reduce((n,e)=>n+e.quantidade,0);
    g.repsDetectadasSerie=g.eventos.filter(e=>e.tipo==='rep_detector' && e.t<=(g.fimManualMs??Infinity)).reduce((n,e)=>n+e.quantidade,0);
    g.repsAposFim=g.repsDetectadas-g.repsDetectadasSerie;
        fecharDetectores();
        try{salvarGravacao(g);}catch(e){console.log('Gravação não salva:',String(e));}
      }
      g=null;etapa='ociosa';ocultar();
    },
  };
}