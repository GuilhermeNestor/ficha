import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";
import { push, replace } from "@zos/router";
import { onDigitalCrown, offDigitalCrown } from "@zos/interaction";
import { DEVICE_WIDTH, DEVICE_HEIGHT } from "../layout.js";
import {
  carregarSessao,
  limparSessao,
  salvarSessao,
} from "../sessao.js";
import { carregarFichas } from "../ficha.js";
import { podeIniciarTreino } from "../resultados.js";
import { aviso } from "../aviso.js";

const LIMA = 0xb6ff00;
const LIMA_PRESS = 0x8fc700;
const LIMA_ESCURO = 0x4d6600;
const LIMIAR = 5;
const DURACAO = 260;
const PASSO_MS = 20;
const ANGULO = 40;
const RAIO = 72;

function cinza(g) {
  const v = Math.max(0, Math.min(255, Math.round(g)));
  return (v << 16) | (v << 8) | v;
}

Page({
  build() {
    let fichas, treinos, sessao;

    try {
      sessao = carregarSessao();

      if (sessao && sessao.fase === "finalizacao") {
        replace({
          url: "page/gt/resumo/index.page",
          params: JSON.stringify(sessao),
        });
        return;
      }

      fichas = carregarFichas();

      treinos = fichas.map((f) => ({
        id: f.id,
        nome: f.nome,
        info: `${f.exercicios.length} exercícios · ${Math.round(
          f.exercicios.reduce(
            (n, e) => n + e.series * (45 + e.descanso),
            0
          ) / 60
        )} min`,
      }));

      if (
        sessao &&
        (!fichas[sessao.t] ||
          !fichas[sessao.t].exercicios[sessao.ex])
      ) {
        throw new Error("Ficha da sessão indisponível");
      }

      podeIniciarTreino();
    } catch (e) {
      aviso(e.message);
      return;
    }

    let sel = sessao ? sessao.t : 0;
    let pos = sel;
    let acumulado = 0;
    let timer = null;
    let botao = null;
    let descartar = null;

    const centroX = DEVICE_WIDTH / 2;
    const centroY = px(238);
    const altLinha = px(44);
    const raio = px(RAIO);
    const rad = (ANGULO * Math.PI) / 180;

    const emAndamento = () => !!sessao && sessao.t === sel;

    const textoInfo = () =>
      emAndamento()
        ? `EM ANDAMENTO · ${fichas[sessao.t].exercicios[sessao.ex].nome}`
        : treinos[sel].info;

    hmUI.createWidget(hmUI.widget.FILL_RECT, {
      x: 0, y: 0, w: DEVICE_WIDTH, h: DEVICE_HEIGHT,
      color: 0x000000,
    });

    hmUI.createWidget(hmUI.widget.TEXT, {
      x: px(30), y: px(65),
      w: DEVICE_WIDTH - px(60), h: px(45),
      text: "FICHA DE TREINO",
      text_size: px(24), color: 0xffffff,
      align_h: hmUI.align.CENTER_H,
      align_v: hmUI.align.CENTER_V,
    });

    hmUI.createWidget(hmUI.widget.BUTTON, {
      x: px(30), y: px(112),
      w: DEVICE_WIDTH - px(60), h: px(30),
      normal_color: 0x000000,
      press_color: 0x1c1c1e,
      text: "SINCRONIZAR",
      text_size: px(14), color: LIMA,
      align_h: hmUI.align.CENTER_H,
      align_v: hmUI.align.CENTER_V,
      click_func: () =>
        replace({ url: "page/gt/sincronizacao/index.page" }),
    });

    hmUI.createWidget(hmUI.widget.FILL_RECT, {
      x: centroX - px(115),
      y: centroY - altLinha / 2 - px(2),
      w: px(230), h: altLinha + px(4),
      radius: px(22), color: 0x12170a,
    });

    const itens = treinos.map((t) =>
      hmUI.createWidget(hmUI.widget.TEXT, {
        x: px(60), y: centroY - altLinha / 2,
        w: DEVICE_WIDTH - px(120), h: altLinha,
        text: t.nome, text_size: px(20), color: 0x000000,
        align_h: hmUI.align.CENTER_H,
        align_v: hmUI.align.CENTER_V,
      })
    );

    const seta = hmUI.createWidget(hmUI.widget.TEXT, {
      x: centroX - px(100), y: centroY - altLinha / 2,
      w: px(30), h: altLinha,
      text: "", text_size: px(24), color: LIMA,
      align_h: hmUI.align.CENTER_H,
      align_v: hmUI.align.CENTER_V,
    });

    const info = hmUI.createWidget(hmUI.widget.TEXT, {
      x: px(45), y: sessao ? px(322) : px(330),
      w: DEVICE_WIDTH - px(90), h: px(26),
      text: textoInfo(), text_size: px(14), color: 0xaaaaaa,
      align_h: hmUI.align.CENTER_H,
      align_v: hmUI.align.CENTER_V,
    });

    const atualizarRotulos = () => {
      info.setProperty(hmUI.prop.TEXT, textoInfo());

      if (botao) {
        botao.setProperty(hmUI.prop.MORE, {
          text: emAndamento() ? "CONTINUAR" : "INICIAR",
        });
      }

      if (descartar) {
        descartar.setProperty(hmUI.prop.VISIBLE, emAndamento());
      }
    };

    const render = (p) => {
      itens.forEach((w, i) => {
        const a = (i - p) * rad;

        if (Math.abs(a) >= Math.PI / 2) {
          w.setProperty(hmUI.prop.MORE, {
            text_size: px(12), color: 0x000000,
          });
          return;
        }

        const c = Math.cos(a);

        w.setProperty(hmUI.prop.MORE, {
          y: centroY + raio * Math.sin(a) - altLinha / 2,
          text_size: px(Math.round(12 + 16 * c * c)),
          color: cinza(255 * Math.pow(c, 2.5)),
        });
      });
    };

    const mostrarSeta = () => {
      let largura = px(120);

      try {
        const m = hmUI.getTextLayout(treinos[sel].nome, {
          text_size: px(28), text_width: 0, wrapped: 0,
        });
        if (m && m.width) largura = m.width;
      } catch (e) {}

      seta.setProperty(hmUI.prop.MORE, {
        x: centroX - largura / 2 - px(36),
        text: ">",
      });
    };

    const irPara = (novo) => {
      if (novo === sel || novo < 0 || novo > treinos.length - 1) {
        return;
      }

      sel = novo;
      seta.setProperty(hmUI.prop.TEXT, "");
      atualizarRotulos();

      if (timer) clearInterval(timer);

      const ini = pos;
      const fim = sel;
      const t0 = Date.now();

      timer = setInterval(() => {
        const t = (Date.now() - t0) / DURACAO;

        if (t >= 1) {
          pos = fim;
          render(pos);
          clearInterval(timer);
          timer = null;
          mostrarSeta();
          return;
        }

        pos = ini + (fim - ini) * (1 - Math.pow(1 - t, 3));
        render(pos);
      }, PASSO_MS);
    };

    render(pos);
    mostrarSeta();

    onDigitalCrown({
      callback: (key, degree) => {
        acumulado += degree;

        if (acumulado >= LIMIAR) {
          acumulado = 0;
          irPara(sel + 1);
        } else if (acumulado <= -LIMIAR) {
          acumulado = 0;
          irPara(sel - 1);
        }
      },
    });

    const btnX = px(110);
    const btnY = px(385);
    const btnW = DEVICE_WIDTH - px(220);
    const btnH = px(56);

    if (sessao) {
      descartar = hmUI.createWidget(hmUI.widget.BUTTON, {
        x: px(150), y: px(350),
        w: DEVICE_WIDTH - px(300), h: px(26),
        radius: px(13),
        normal_color: 0x000000, press_color: 0x1c1c1e,
        text: "DESCARTAR", text_size: px(20), color: 0x888888,
        click_func: () => {
          try {
            limparSessao();
          } catch (e) {
            aviso(e.message);
            return;
          }

          replace({ url: "page/gt/home/index.page" });
        },
      });
    }

    hmUI.createWidget(hmUI.widget.STROKE_RECT, {
      x: btnX - px(6), y: btnY - px(6),
      w: btnW + px(12), h: btnH + px(12),
      radius: (btnH + px(12)) / 2,
      line_width: px(2), color: LIMA_ESCURO,
    });

    botao = hmUI.createWidget(hmUI.widget.BUTTON, {
      x: btnX, y: btnY, w: btnW, h: btnH,
      radius: btnH / 2,
      normal_color: LIMA, press_color: LIMA_PRESS,
      text: emAndamento() ? "CONTINUAR" : "INICIAR",
      text_size: px(30), color: 0x000000,

      click_func: () => {
        if (!emAndamento()) {
          try {
            if (!podeIniciarTreino()) {
              replace({
                url: "page/gt/sincronizacao/index.page",
              });
              return;
            }

            const inicio = Date.now();

            const nova = salvarSessao({
              fase: "exercicio",
              id: `treino_${inicio}_${Math.random()
                .toString(36)
                .slice(2, 10)}`,
              t: sel,
              ex: 0,
              serie: 1,
              fichaId: fichas[sel].id,
              inicio,
              feitas: 0,
              exs: 0,
            });

            push({
              url: "page/gt/exercicio/index.page",
              params: JSON.stringify(nova),
            });
          } catch (e) {
            aviso(e.message);
          }

          return;
        }

        push({
          url:
            sessao.fase === "descanso"
              ? "page/gt/descanso/index.page"
              : "page/gt/exercicio/index.page",
          params: JSON.stringify(sessao),
        });
      },
    });

    this.limpar = () => {
      if (timer) clearInterval(timer);
      offDigitalCrown();
    };
  },

  onDestroy() {
    if (this.limpar) this.limpar();
  },
});