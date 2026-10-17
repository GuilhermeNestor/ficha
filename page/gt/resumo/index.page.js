import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";
import { replace } from "@zos/router";
import * as sensor from "@zos/sensor";
import { DEVICE_WIDTH, DEVICE_HEIGHT } from "../layout.js";
import { treinos } from "../dados.js";
import { limparSessao } from "../sessao.js";

const LIMA = 0xb6ff00;
const LIMA_PRESS = 0x8fc700;
const INICIO = -90;
const MARGEM_ANEL = 0;
const ESPESSURA_ANEL = 12;

function formatarTempo(ms) {
  const total = Math.max(0, Math.round(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const dois = (n) => (n < 10 ? "0" + n : "" + n);
  return h > 0 ? `${h}:${dois(m)}:${dois(s)}` : `${dois(m)}:${dois(s)}`;
}

Page({
  onInit(params) {
    let p = {};
    try { p = JSON.parse(params); } catch (e) {}
    this.p = p;
  },

  build() {
    limparSessao();
    const p = this.p;
    const treino = treinos[p.t || 0];
    const totalEx = treino.exercicios.length;
    const duracao = (p.fim || Date.now()) - (p.inicio || Date.now());
    const centroX = DEVICE_WIDTH / 2;

    // vibra ao concluir
    try {
      const v = new sensor.Vibrator();
      v.stop();
      v.setMode(sensor.VIBRATOR_SCENE_SHORT_STRONG);
      v.start();
    } catch (e) {}

    // fundo
    hmUI.createWidget(hmUI.widget.FILL_RECT, {
      x: 0, y: 0, w: DEVICE_WIDTH, h: DEVICE_HEIGHT, color: 0x000000,
    });

    // anel completo
    const margem = px(MARGEM_ANEL);
    hmUI.createWidget(hmUI.widget.ARC, {
      x: margem, y: margem,
      w: DEVICE_WIDTH - margem * 2, h: DEVICE_HEIGHT - margem * 2,
      line_width: px(ESPESSURA_ANEL),
      start_angle: INICIO, end_angle: INICIO + 360,
      color: LIMA,
    });

    hmUI.createWidget(hmUI.widget.TEXT, {
      x: px(60), y: px(62), w: DEVICE_WIDTH - px(120), h: px(30),
      text: "TREINO CONCLUÍDO", text_size: px(18), color: LIMA,
      align_h: hmUI.align.CENTER_H, align_v: hmUI.align.CENTER_V,
    });

    hmUI.createWidget(hmUI.widget.TEXT, {
      x: px(60), y: px(94), w: DEVICE_WIDTH - px(120), h: px(34),
      text: treino.nome, text_size: px(24), color: 0xffffff,
      align_h: hmUI.align.CENTER_H, align_v: hmUI.align.CENTER_V,
    });

    // tempo total
    hmUI.createWidget(hmUI.widget.TEXT, {
      x: px(60), y: px(145), w: DEVICE_WIDTH - px(120), h: px(90),
      text: formatarTempo(duracao), text_size: px(72), color: 0xffffff,
      align_h: hmUI.align.CENTER_H, align_v: hmUI.align.CENTER_V,
    });

    hmUI.createWidget(hmUI.widget.TEXT, {
      x: px(60), y: px(232), w: DEVICE_WIDTH - px(120), h: px(24),
      text: "TEMPO TOTAL", text_size: px(13), color: 0x888888,
      align_h: hmUI.align.CENTER_H, align_v: hmUI.align.CENTER_V,
    });

    // linha separadora
    hmUI.createWidget(hmUI.widget.FILL_RECT, {
      x: centroX - px(1), y: px(272), w: px(2), h: px(60), color: 0x2a2a2c,
    });

    const coluna = (x, valor, rotulo) => {
      hmUI.createWidget(hmUI.widget.TEXT, {
        x, y: px(268), w: px(120), h: px(44),
        text: valor, text_size: px(34), color: 0xffffff,
        align_h: hmUI.align.CENTER_H, align_v: hmUI.align.CENTER_V,
      });
      hmUI.createWidget(hmUI.widget.TEXT, {
        x, y: px(312), w: px(120), h: px(22),
        text: rotulo, text_size: px(13), color: 0x888888,
        align_h: hmUI.align.CENTER_H, align_v: hmUI.align.CENTER_V,
      });
    };

    coluna(centroX - px(150), String(p.feitas || 0), "SÉRIES");
    coluna(centroX + px(30), `${p.exs || 0}/${totalEx}`, "EXERCÍCIOS");

    // botão
    hmUI.createWidget(hmUI.widget.BUTTON, {
      x: px(110), y: px(372), w: DEVICE_WIDTH - px(220), h: px(54), radius: px(27),
      normal_color: LIMA, press_color: LIMA_PRESS,
      text: "CONCLUIR", text_size: px(18), color: 0x000000,
      click_func: () => replace({ url: "page/gt/home/index.page" }),
    });
  },
});