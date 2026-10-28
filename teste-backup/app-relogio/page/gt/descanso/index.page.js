import * as hmUI from '@zos/ui';
import { px } from '@zos/utils';
import { replace } from '@zos/router';
import { onDigitalCrown, offDigitalCrown } from '@zos/interaction';
import * as display from '@zos/display';
import { DEVICE_WIDTH, DEVICE_HEIGHT } from '../layout.js';
import { aviso } from '../aviso.js';
import { salvarSessao } from '../sessao.js';
import { vibrar } from '../vibracao.js';

Page({
  onInit(params){try{this.p=JSON.parse(params)||{};}catch(_){this.p={};}},
  build(){
    let p=this.p, total=p.descanso||60;
    let fim=p.fimAbs||Date.now()+total*1000;
    let acumulado=0,timer=null,saiu=false,ultimoNumero=-1,ultimoAngulo=null;
    const texto=(x,y,w,h,text,size,color=0xffffff)=>hmUI.createWidget(hmUI.widget.TEXT,{
      x:px(x),y:px(y),w:px(w),h:px(h),text,text_size:px(size),color,
      align_h:hmUI.align.CENTER_H,align_v:hmUI.align.CENTER_V,
      text_style:hmUI.text_style.ELLIPSIS,
    });
    try{display.setPageBrightTime({brightTime:300000});
      display.pauseDropWristScreenOff({duration:300000});}catch(_){}
    hmUI.createWidget(hmUI.widget.FILL_RECT,{
      x:0,y:0,w:DEVICE_WIDTH,h:DEVICE_HEIGHT,color:0,
    });
    const anel=hmUI.createWidget(hmUI.widget.ARC,{
      x:0,y:0,w:DEVICE_WIDTH,h:DEVICE_HEIGHT,line_width:px(14),
      start_angle:-90,end_angle:270,color:0x168cff,
    });
    texto(110,58,260,40,'DESCANSO',26,0x168cff);
    const numero=texto(90,104,300,170,'',150);
    texto(100,276,280,28,'GIRE A COROA: ±5 s',18,0xaaaaaa);
    texto(90,308,300,40,`PRÓXIMA  ${p.carga ?? 0} kg`,28);
    const parar=()=>{
      saiu=true;
      if(timer!==null) clearTimeout(timer);
      offDigitalCrown();
    };
    this.limpar=parar;
    const erro=e=>{
      parar();
      aviso(e.message,()=>replace({url:'page/gt/descanso/index.page',
        params:JSON.stringify({...p,descanso:total,fimAbs:fim})}));
    };
    const voltar=()=>{
      if(saiu) return;
      parar();
      const proxima={...p,fase:'exercicio',reps:0};
      delete proxima.fimAbs; delete proxima.descanso;
      const executar=()=>{
        try{
          const s=salvarSessao(proxima);
          vibrar('fim');
          replace({url:'page/gt/exercicio/index.page',params:JSON.stringify(s)});
        }catch(e){aviso(e.message,executar);}
      };
      executar();
    };
    hmUI.createWidget(hmUI.widget.BUTTON,{
      x:px(120),y:px(366),w:px(240),h:px(60),radius:px(30),
      normal_color:0x202020,press_color:0x353535,text:'PULAR',
      text_size:px(24),color:0xffffff,click_func:voltar,
    });
    const salvar=()=>{
      try{p=salvarSessao({...p,fase:'descanso',descanso:total,fimAbs:fim});return true;}
      catch(e){erro(e);return false;}
    };
    const atualizar=()=>{
      if(saiu) return;
      const restante=Math.max(0,fim-Date.now());
      const segundos=Math.ceil(restante/1000);
      if(segundos!==ultimoNumero){
        ultimoNumero=segundos;
        numero.setProperty(hmUI.prop.MORE,{
          text:String(segundos),text_size:px(segundos>=1000?88:segundos>=100?118:150),
        });
      }
      const angulo=-90+360*Math.min(1,restante/(total*1000));
      if(ultimoAngulo===null || Math.abs(angulo-ultimoAngulo)>=1 || restante===0){
        ultimoAngulo=angulo;anel.setProperty(hmUI.prop.MORE,{end_angle:angulo});
      }
      if(restante<=0) voltar();
    };
    if(!salvar()) return;
    onDigitalCrown({callback:(key,degree)=>{
      if(saiu || !Number.isFinite(degree)) return;
      acumulado-=degree;
      if(Math.abs(acumulado)<5) return;
      const passo=acumulado>0?5:-5; acumulado=0;
      const restante=Math.max(0,fim-Date.now());
      const novo=Math.max(0,Math.min(3600000,restante+passo*1000));
      fim=Date.now()+novo; total=Math.max(5,Math.ceil(novo/1000));
      if(salvar()) atualizar();
    }});
    const quadro=()=>{
      atualizar();
      if(!saiu) timer=setTimeout(quadro,100);
    };
    quadro();
  },
  onDestroy(){if(this.limpar)this.limpar();},
});
