import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";
import { replace } from "@zos/router";
import { onDigitalCrown, offDigitalCrown } from "@zos/interaction";
import { LocalStorage } from "@zos/storage";
import * as sensor from "@zos/sensor";
import * as display from "@zos/display";
import { DEVICE_WIDTH, DEVICE_HEIGHT } from "../layout.js";
import { treinos } from "../dados.js";
import { salvarSessao } from "../sessao.js";


const LIMA = 0xb6ff00;
const LIMA_PRESS = 0x8fc700;
const TRILHA = 0x1c1c1e;
const INICIO = -90;
const LIMIAR_COROA = 25;
const PASSO_CARGA = 2.5;
const PESO_MAX = 500;
// ---- anel ----
const MARGEM_ANEL = 0;
const ESPESSURA_ANEL = 12;



// ---- roda de peso ----
const ANGULO = 36;
const RAIO = 85;
const DURACAO = 220;
const PASSO_MS = 20;

// ---- detecção de repetição (calibre aqui) ----
const DEBUG = true;
const LIMIAR_ALTO = 3.0;
const LIMIAR_BAIXO = 1.2;
const INTERVALO_MIN = 900;
const ATRASO_INICIAL = 1500;

const storage = new LocalStorage();
const chaveUltimo = (nome) => `ultimo_${nome}`;
const fmt = (v) => (v % 1 === 0 ? String(v) : v.toFixed(1));

function cinza(g) {
  const v = Math.max(0, Math.min(255, Math.round(g)));
  return (v << 16) | (v << 8) | v;
}

Page({
  onInit(params) {
    let p = {};
    try { p = JSON.parse(params); } catch (e) {}
    this.tI = p.t || 0;
    this.exI = p.ex || 0;
    this.serie = p.serie || 1;
    this.inicio = p.inicio || Date.now();
    this.feitas = p.feitas || 0;
    this.exs = p.exs || 0;
    this.repsIni = p.reps || 0;

    const ex = treinos[this.tI].exercicios[this.exI];

    let ultimo = ex.carga;
    try {
      const salvo = storage.getItem(chaveUltimo(ex.nome));
      if (salvo !== undefined && salvo !== null && salvo !== "") ultimo = parseFloat(salvo);
    } catch (e) {}
    this.ultimo = ultimo;

    this.carga = p.carga !== undefined ? p.carga : ultimo;
  },

  build() {
    const tI = this.tI;
    const exI = this.exI;
    const lista = treinos[tI].exercicios;
    const ex = lista[exI];
    const serie = this.serie;
    const ultimo = this.ultimo;
    const inicio = this.inicio;
    const feitas = this.feitas;
    const exs = this.exs;
    let carga = this.carga;

    let repeticoes = this.repsIni || 0;
    let acumulado = 0;
    let finalizando = false;
    let modoRoda = false;
    let armado = true;
    let suave = 0;
    let pico = 0;
    let ultimaRep = 0;
    const abriuEm = Date.now();

    const centroX = DEVICE_WIDTH / 2;
    const ultimaSerie = serie >= ex.series;
    const ultimoEx = exI >= lista.length - 1;

    try { display.setPageBrightTime({ brightTime: 300000 }); } catch (e) {}
    try { display.pauseDropWristScreenOff({ duration: 300000 }); } catch (e) {}

    const vibrador = new sensor.Vibrator();
    const vibrar = (forte) => {
      try {
        vibrador.stop();
        vibrador.setMode(
          forte ? sensor.VIBRATOR_SCENE_SHORT_STRONG : sensor.VIBRATOR_SCENE_SHORT_LIGHT
        );
        vibrador.start();
      } catch (e) {}
    };

    // ---------- fundo ----------
    hmUI.createWidget(hmUI.widget.FILL_RECT, {
      x: 0, y: 0, w: DEVICE_WIDTH, h: DEVICE_HEIGHT, color: 0x000000,
    });

    // ---------- anel ----------
    const margem = px(MARGEM_ANEL);
    const box = {
      x: margem, y: margem,
      w: DEVICE_WIDTH - margem * 2, h: DEVICE_HEIGHT - margem * 2,
      line_width: px(ESPESSURA_ANEL),
    };
    hmUI.createWidget(hmUI.widget.ARC, {
      ...box, start_angle: INICIO, end_angle: INICIO + 360, color: TRILHA,
    });
    const anel = hmUI.createWidget(hmUI.widget.ARC, {
      ...box, start_angle: INICIO, end_angle: INICIO, color: LIMA,
    });

    // ---------- toque no número = +1 rep ----------
    hmUI.createWidget(hmUI.widget.BUTTON, {
      x: px(130), y: px(108), w: DEVICE_WIDTH - px(260), h: px(130),
      radius: px(30),
      normal_color: 0x000000, press_color: 0x10150a,
      text: "",
      click_func: () => contarRep(),
    });

    // ---------- nome ----------
    hmUI.createWidget(hmUI.widget.TEXT, {
      x: px(70), y: px(52), w: DEVICE_WIDTH - px(140), h: px(34),
      text: ex.nome, text_size: px(22), color: 0xffffff,
      align_h: hmUI.align.CENTER_H, align_v: hmUI.align.CENTER_V,
    });

    // ---------- bolinhas das séries ----------
    const dot = px(11);
    const gap = px(9);
    const larguraTotal = ex.series * dot + (ex.series - 1) * gap;
    const x0 = centroX - larguraTotal / 2;
    for (let i = 0; i < ex.series; i++) {
      hmUI.createWidget(hmUI.widget.FILL_RECT, {
        x: x0 + i * (dot + gap), y: px(94), w: dot, h: dot, radius: dot / 2,
        color: i < serie - 1 ? LIMA : i === serie - 1 ? 0xffffff : 0x3a3a3c,
      });
    }

    // ---------- contador ----------
    const contador = hmUI.createWidget(hmUI.widget.TEXT, {
      x: px(110), y: px(110), w: DEVICE_WIDTH - px(220), h: px(100),
      text: "00", text_size: px(84), color: 0xffffff,
      align_h: hmUI.align.CENTER_H, align_v: hmUI.align.CENTER_V,
    });

    const sub = hmUI.createWidget(hmUI.widget.TEXT, {
      x: px(100), y: px(212), w: DEVICE_WIDTH - px(200), h: px(26),
      text: `DE ${ex.reps} REPETIÇÕES`, text_size: px(14), color: 0xaaaaaa,
      align_h: hmUI.align.CENTER_H, align_v: hmUI.align.CENTER_V,
    });

    // ---------- pesos: anterior e atual ----------
    const distancia = px(48);
    const colW = px(96);
    const pesoY = px(258);
    const xAnt = centroX - distancia - colW / 2;
    const xAtu = centroX + distancia - colW / 2;

    hmUI.createWidget(hmUI.widget.FILL_RECT, {
      x: centroX - px(1), y: pesoY + px(10), w: px(2), h: px(70),
      color: 0x2a2a2c,
    });

    hmUI.createWidget(hmUI.widget.BUTTON, {
      x: xAtu, y: pesoY - px(6), w: colW, h: px(100), radius: px(20),
      normal_color: 0x000000, press_color: 0x10150a,
      text: "",
      click_func: () => abrirRoda(),
    });

    const colunaPeso = (x, rotulo, valor, corRotulo) => {
      hmUI.createWidget(hmUI.widget.TEXT, {
        x, y: pesoY, w: colW, h: px(22),
        text: rotulo, text_size: px(13), color: corRotulo,
        align_h: hmUI.align.CENTER_H, align_v: hmUI.align.CENTER_V,
      });
      const v = hmUI.createWidget(hmUI.widget.TEXT, {
        x, y: pesoY + px(22), w: colW, h: px(56),
        text: fmt(valor), text_size: px(40), color: 0xffffff,
        align_h: hmUI.align.CENTER_H, align_v: hmUI.align.CENTER_V,
      });
      hmUI.createWidget(hmUI.widget.TEXT, {
        x, y: pesoY + px(78), w: colW, h: px(20),
        text: "kg", text_size: px(14), color: 0x888888,
        align_h: hmUI.align.CENTER_H, align_v: hmUI.align.CENTER_V,
      });
      return v;
    };

    colunaPeso(xAnt, "ANTERIOR", ultimo, 0x888888);
    const cargaTxt = colunaPeso(xAtu, "ATUAL", carga, LIMA);

    // ---------- botão PULAR ----------
    hmUI.createWidget(hmUI.widget.BUTTON, {
      x: px(130), y: px(372), w: DEVICE_WIDTH - px(260), h: px(50), radius: px(25),
      normal_color: 0x202020, press_color: 0x353535,
      text: "PULAR", text_size: px(17), color: 0xffffff,
      click_func: () => pular(),
    });

        // ---------- botão +REP (só para teste) ----------
    const TESTE = true;   // coloque false para esconder quando terminar de testar
    if (TESTE) {
      hmUI.createWidget(hmUI.widget.BUTTON, {
        x: px(52), y: px(148), w: px(64), h: px(64), radius: px(32),
        normal_color: 0x202020, press_color: 0x353535,
        text: "+REP", text_size: px(15), color: LIMA,
        click_func: () => contarRep(),
      });
    }

    // =====================================================
    //  RODA DE PESO
    // =====================================================
    const overlay = [];
    const ov = (w) => { overlay.push(w); return w; };

    const rodaY = px(235);
    const altLinha = px(60);
    const raio = px(RAIO);
    const rad = (ANGULO * Math.PI) / 180;

    ov(hmUI.createWidget(hmUI.widget.FILL_RECT, {
      x: 0, y: 0, w: DEVICE_WIDTH, h: DEVICE_HEIGHT, color: 0x000000,
    }));

    ov(hmUI.createWidget(hmUI.widget.TEXT, {
      x: px(80), y: px(62), w: DEVICE_WIDTH - px(160), h: px(32),
      text: "PESO ATUAL", text_size: px(20), color: LIMA,
      align_h: hmUI.align.CENTER_H, align_v: hmUI.align.CENTER_V,
    }));

    ov(hmUI.createWidget(hmUI.widget.TEXT, {
      x: px(80), y: px(96), w: DEVICE_WIDTH - px(160), h: px(24),
      text: "GIRE A COROA", text_size: px(13), color: 0x888888,
      align_h: hmUI.align.CENTER_H, align_v: hmUI.align.CENTER_V,
    }));

    ov(hmUI.createWidget(hmUI.widget.FILL_RECT, {
      x: centroX - px(110), y: rodaY - altLinha / 2,
      w: px(220), h: altLinha, radius: px(30), color: 0x12170a,
    }));

    const slots = [];
    for (let i = 0; i < 5; i++) {
      slots.push(ov(hmUI.createWidget(hmUI.widget.TEXT, {
        x: px(100), y: rodaY - altLinha / 2, w: DEVICE_WIDTH - px(200), h: altLinha,
        text: "", text_size: px(20), color: 0x000000,
        align_h: hmUI.align.CENTER_H, align_v: hmUI.align.CENTER_V,
      })));
    }

    ov(hmUI.createWidget(hmUI.widget.TEXT, {
      x: centroX + px(78), y: rodaY - px(12), w: px(50), h: px(26),
      text: "kg", text_size: px(16), color: LIMA,
      align_h: hmUI.align.LEFT, align_v: hmUI.align.CENTER_V,
    }));

    ov(hmUI.createWidget(hmUI.widget.BUTTON, {
      x: px(110), y: px(385), w: DEVICE_WIDTH - px(220), h: px(56), radius: px(28),
      normal_color: LIMA, press_color: LIMA_PRESS,
      text: "OK", text_size: px(20), color: 0x000000,
      click_func: () => fecharRoda(true),
    }));

    const mostrarOverlay = (on) => {
      overlay.forEach((w) => w.setProperty(hmUI.prop.VISIBLE, on));
    };
    mostrarOverlay(false);

    let base0 = carga;
    let alvo = 0;
    let posRoda = 0;
    let timerRoda = null;

    const valorDe = (i) => base0 + i * PASSO_CARGA;

    const renderRoda = (p) => {
      const base = Math.round(p);
      slots.forEach((w, k) => {
        const idx = base + (k - 2);
        const valor = valorDe(idx);
        const a = (idx - p) * rad;

        if (valor < 0 || valor > PESO_MAX || Math.abs(a) >= Math.PI / 2) {
          w.setProperty(hmUI.prop.MORE, { text: "", color: 0x000000 });
          return;
        }
        const c = Math.cos(a);
        w.setProperty(hmUI.prop.MORE, {
          text: fmt(valor),
          y: rodaY + raio * Math.sin(a) - altLinha / 2,
          text_size: px(Math.round(14 + 34 * c * c)),
          color: cinza(255 * Math.pow(c, 2.5)),
        });
      });
    };

    const irParaRoda = (novo) => {
      const v = valorDe(novo);
      if (novo === alvo || v < 0 || v > PESO_MAX) return;
      alvo = novo;
      if (timerRoda) clearInterval(timerRoda);

      const ini = posRoda;
      const fim = alvo;
      const t0 = Date.now();

      timerRoda = setInterval(() => {
        const t = (Date.now() - t0) / DURACAO;
        if (t >= 1) {
          posRoda = fim;
          renderRoda(posRoda);
          clearInterval(timerRoda);
          timerRoda = null;
          return;
        }
        posRoda = ini + (fim - ini) * (1 - Math.pow(1 - t, 3));
        renderRoda(posRoda);
      }, PASSO_MS);
    };

    const abrirRoda = () => {
      if (finalizando || modoRoda) return;
      modoRoda = true;
      acumulado = 0;
      base0 = carga;
      alvo = 0;
      posRoda = 0;
      renderRoda(0);
      mostrarOverlay(true);
    };

    const fecharRoda = (confirmar) => {
      if (!modoRoda) return;
      if (timerRoda) { clearInterval(timerRoda); timerRoda = null; }
      if (confirmar) {
        carga = Math.max(0, valorDe(alvo));
        cargaTxt.setProperty(hmUI.prop.TEXT, fmt(carga));
      }
      salvarEstado();
      mostrarOverlay(false);
      modoRoda = false;
      acumulado = 0;
    };

    // =====================================================
    //  AÇÕES
    // =====================================================
    const salvarPeso = () => {
      try { storage.setItem(chaveUltimo(ex.nome), String(carga)); } catch (e) {}
    };

    const salvarEstado = () => {
      salvarSessao({
        fase: "exercicio",
        t: tI, ex: exI, serie, carga,
        inicio, feitas, exs,
        reps: repeticoes,
      });
    };

    // vai para o próximo exercício ou, se for o último, para o resumo
    const proximo = (feitasAgora, exsAgora) => {
      if (!ultimoEx) {
        replace({
          url: "page/gt/exercicio/index.page",
          params: JSON.stringify({
            t: tI, ex: exI + 1, serie: 1,
            inicio, feitas: feitasAgora, exs: exsAgora,
          }),
        });
      } else {
        replace({
          url: "page/gt/resumo/index.page",
          params: JSON.stringify({
            t: tI, inicio, fim: Date.now(),
            feitas: feitasAgora, exs: exsAgora,
          }),
        });
      }
    };

    const pular = () => {
      if (finalizando || modoRoda) return;
      finalizando = true;
      proximo(feitas, exs);   // exercício pulado não conta
    };

    const concluirSerie = () => {
      if (finalizando) return;
      finalizando = true;
      vibrar(true);
      if (!ultimaSerie) {
        replace({
          url: "page/gt/descanso/index.page",
          params: JSON.stringify({
            t: tI, ex: exI, serie: serie + 1, carga, descanso: ex.descanso,
            inicio, feitas: feitas + 1, exs,
          }),
        });
      } else {
        salvarPeso();
        proximo(feitas + 1, exs + 1);
      }
    };

    const contarRep = () => {
      if (finalizando || modoRoda || repeticoes >= ex.reps) return;
      repeticoes++;
      contador.setProperty(hmUI.prop.MORE, {
        text: repeticoes < 10 ? "0" + repeticoes : "" + repeticoes,
        text_size: px(100),
      });
      setTimeout(() => contador.setProperty(hmUI.prop.MORE, { text_size: px(84) }), 90);
      anel.setProperty(hmUI.prop.MORE, {
        end_angle: INICIO + 360 * (repeticoes / ex.reps),
      });
      if (repeticoes < ex.reps) salvarEstado();
      if (repeticoes >= ex.reps) concluirSerie();
      else vibrar(false);
    };

    // ---------- acelerômetro ----------
    let acc = null;
    try {
      acc = new sensor.Accelerometer();
      let gravidade = null;

      acc.onChange(() => {
        const a = acc.getCurrent();
        if (!a) return;
        const mag = Math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z);

        gravidade = gravidade === null ? mag : gravidade + (mag - gravidade) * 0.05;
        const dinamico = Math.abs(mag - gravidade);

        suave += (dinamico - suave) * 0.3;
        if (suave > pico) pico = suave;

        if (modoRoda) return;

        const agora = Date.now();
        if (agora - abriuEm < ATRASO_INICIAL) return;

        if (armado && suave > LIMIAR_ALTO && agora - ultimaRep > INTERVALO_MIN) {
          armado = false;
          ultimaRep = agora;
          contarRep();
        } else if (!armado && suave < LIMIAR_BAIXO) {
          armado = true;
        }

        if (DEBUG) {
          sub.setProperty(hmUI.prop.TEXT, `mov ${suave.toFixed(1)} · pico ${pico.toFixed(1)}`);
        }
      });
      acc.start();
    } catch (e) {}
    this.acc = acc;

    // ---------- coroa: só funciona com a roda aberta ----------
    onDigitalCrown({
      callback: (key, degree) => {
        if (!modoRoda) return;
        acumulado += degree;
        if (acumulado >= LIMIAR_COROA) { acumulado = 0; irParaRoda(alvo + 1); }
        else if (acumulado <= -LIMIAR_COROA) { acumulado = 0; irParaRoda(alvo - 1); }
      },
    });

    // restaura a contagem se o treino foi retomado no meio da série
    if (repeticoes > 0) {
      contador.setProperty(
        hmUI.prop.TEXT,
        repeticoes < 10 ? "0" + repeticoes : "" + repeticoes
      );
      anel.setProperty(hmUI.prop.MORE, {
        end_angle: INICIO + 360 * (repeticoes / ex.reps),
      });
    }
    salvarEstado();

    this.limpar = () => {
      if (timerRoda) clearInterval(timerRoda);
      offDigitalCrown();
    };
  },

  onDestroy() {
    if (this.limpar) this.limpar();
    try {
      if (this.acc) {
        this.acc.offChange();
        this.acc.stop();
      }
    } catch (e) {}
  },
});