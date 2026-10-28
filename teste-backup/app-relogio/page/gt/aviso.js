import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";
import { replace } from "@zos/router";
import { DEVICE_WIDTH, DEVICE_HEIGHT } from "./layout.js";

export function aviso(mensagem, tentar) {
  hmUI.createWidget(hmUI.widget.FILL_RECT, {
    x: 0,
    y: 0,
    w: DEVICE_WIDTH,
    h: DEVICE_HEIGHT,
    color: 0x000000,
  });

  hmUI.createWidget(hmUI.widget.TEXT, {
    x: px(45),
    y: px(100),
    w: DEVICE_WIDTH - px(90),
    h: px(180),
    text: String(mensagem),
    text_size: px(20),
    color: 0xffffff,
    text_style: hmUI.text_style.WRAP,
    align_h: hmUI.align.CENTER_H,
    align_v: hmUI.align.CENTER_V,
  });

  hmUI.createWidget(hmUI.widget.BUTTON, {
    x: px(100),
    y: px(300),
    w: DEVICE_WIDTH - px(200),
    h: px(55),
    text: tentar ? "TENTAR NOVAMENTE" : "VOLTAR",
    text_size: px(17),
    color: 0x000000,
    normal_color: 0xb6ff00,
    press_color: 0x8fc700,
    click_func:
      tentar ||
      (() => replace({ url: "page/gt/home/index.page" })),
  });

  hmUI.createWidget(hmUI.widget.BUTTON, {
    x: px(100),
    y: px(365),
    w: DEVICE_WIDTH - px(200),
    h: px(48),
    text: "SINCRONIZAR",
    text_size: px(17),
    color: 0xffffff,
    normal_color: 0x202020,
    press_color: 0x353535,
    click_func: () =>
      replace({ url: "page/gt/sincronizacao/index.page" }),
  });
}