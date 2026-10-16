import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";
import { replace } from "@zos/router";
import { onDigitalCrown, offDigitalCrown } from "@zos/interaction";
import * as sensor from "@zos/sensor";
import * as display from "@zos/display";
import { DEVICE_WIDTH, DEVICE_HEIGHT } from "../layout.js";

const AZUL = 0x168cff;
const INICIO = -90;
const LIMIAR = 25;
const ATUALIZA_MS = 20;

const MARGEM_ANEL = 0;
const ESPESSURA_ANEL = 8;

Page({
  onInit(params) {
    let p = {};
    try { p = JSON.parse(params); } catch (e) {}
    this.p = p;
  },

  build() {
    const p = this.p;
    let total = p.descanso || 60;
    let fim = Date.now() + total * 1000;
    let acumulado = 0;
    let timer = null;
    let saiu = false;
    let ultimoNumero = -1;
    let ultimoAngulo = -9999;

    try { display.setPageBrightTime({ brightTime: 300000 }); } catch (e) {}
    try { display.pauseDropWristScreenOff({ duration: 300000 }); } catch (e) {}

    const vibrador = new sensor.Vibrator();

    hmUI.createWidget(hmUI.widget.FILL_RECT, {
      x: 0, y: 0, w: DEVICE_WIDTH, h: DEVICE_HEIGHT, color: 0x000000,
    });

    const margem = px(MARGEM_ANEL);
    const anel = hmUI.createWidget(hmUI.widget.ARC, {
      x: margem, y: margem,
      w: DEVICE_WIDTH - margem * 2, h: DEVICE_HEIGHT - margem * 2,
      line_width: px(ESPESSURA_ANEL),
      start_angle: INICIO, end_angle: INICIO + 360,
      color: AZUL,
    });

    hmUI.createWidget(hmUI.widget.TEXT, {
      x: px(80), y: px(80), w: DEVICE_WIDTH - px(160), h: px(40),
      text: "DESCANSO", text_size: px(20), color: AZUL,
      align_h: hmUI.align.CENTER_H, align_v: hmUI.align.CENTER_V,
    });

    const numero = hmUI.createWidget(hmUI.widget.TEXT, {
      x: px(80), y: px(130), w: DEVICE_WIDTH - px(160), h: px(130),
      text: String(total), text_size: px(100), color: 0xffffff,
      align_h: hmUI.align.CENTER_H, align_v: hmUI.align.CENTER_V,
    });

    hmUI.createWidget(hmUI.widget.TEXT, {
      x: px(80), y: px(262), w: DEVICE_WIDTH - px(160), h: px(28),
      text: "GIRE A COROA: ±5 s", text_size: px(14), color: 0xaaaaaa,
      align_h: hmUI.align.CENTER_H, align_v: hmUI.align.CENTER_V,
    });

    hmUI.createWidget(hmUI.widget.TEXT, {
      x: px(80), y: px(292), w: DEVICE_WIDTH - px(160), h: px(36),
      text: `PRÓXIMA  ${p.carga} kg`, text_size: px(20), color: 0xffffff,
      align_h: hmUI.align.CENTER_H, align_v: hmUI.align.CENTER_V,
    });

    const voltar = () => {
      if (saiu) return;
      saiu = true;
      if (timer) clearTimeout(timer);
      try {
        vibrador.stop();
        vibrador.setMode(sensor.VIBRATOR_SCENE_SHORT_STRONG);
        vibrador.start();
      } catch (e) {}
      replace({
        url: "page/gt/exercicio/index.page",
        params: JSON.stringify({
          t: p.t, ex: p.ex, serie: p.serie, carga: p.carga,
          inicio: p.inicio, feitas: p.feitas, exs: p.exs,
        }),
      });
    };

    hmUI.createWidget(hmUI.widget.BUTTON, {
      x: px(110), y: px(355), w: DEVICE_WIDTH - px(220), h: px(54), radius: px(27),
      normal_color: 0x202020, press_color: 0x353535,
      text: "PULAR", text_size: px(18), color: 0xffffff,
      click_func: voltar,
    });

    const atualizar = () => {
      const msRestante = Math.max(0, fim - Date.now());
      const segundos = Math.ceil(msRestante / 1000);

      if (segundos !== ultimoNumero) {
        ultimoNumero = segundos;
        numero.setProperty(hmUI.prop.TEXT, String(segundos));
      }

      const angulo = INICIO + 360 * Math.min(1, msRestante / (total * 1000));
      if (Math.abs(angulo - ultimoAngulo) >= 0.4) {
        ultimoAngulo = angulo;
        anel.setProperty(hmUI.prop.END_ANGLE, angulo);
      }

      if (msRestante <= 0) voltar();
    };

    const quadro = () => {
      if (saiu) return;
      const t0 = Date.now();
      atualizar();
      const gasto = Date.now() - t0;
      timer = setTimeout(quadro, Math.max(0, ATUALIZA_MS - gasto));
    };
    quadro();

    onDigitalCrown({
      callback: (key, degree) => {
        acumulado += degree;
        let passo = 0;
        if (acumulado >= LIMIAR) { passo = 1; acumulado = 0; }
        else if (acumulado <= -LIMIAR) { passo = -1; acumulado = 0; }
        if (!passo) return;
        fim += passo * 5000;
        total = Math.max(5, total + passo * 5);
        atualizar();
      },
    });

    this.limpar = () => {
      if (timer) clearTimeout(timer);
      offDigitalCrown();
    };
  },

  onDestroy() {
    if (this.limpar) this.limpar();
  },
});