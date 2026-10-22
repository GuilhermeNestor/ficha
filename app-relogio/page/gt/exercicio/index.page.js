import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";
import { replace } from "@zos/router";
import {
  onDigitalCrown,
  offDigitalCrown,
  onKey,
  offKey,
  KEY_HOME,
  KEY_EVENT_CLICK,
} from "@zos/interaction";
import * as sensor from "@zos/sensor";
import * as display from "@zos/display";
import {
  DEVICE_WIDTH,
  DEVICE_HEIGHT,
} from "../layout.js";
import { carregarFichas } from "../ficha.js";
import {
  ultimaCarga,
  salvarCarga,
} from "../cargas.js";
import {
  carregarSessao,
  salvarSessao,
  prepararFinalizacao,
} from "../sessao.js";
import { criarResultado } from "../resultados.js";
import {
  criarDetectorAdaptativo,
} from "../detector-adaptativo.js";
import { vibrar } from "../vibracao.js";
import { aviso } from "../aviso.js";

const LIMA = 0xb6ff00;

const fmt = (v) =>
  Number.isInteger(v)
    ? String(v)
    : v.toFixed(1);

Page({
  onInit(params) {
    try {
      this.p = JSON.parse(params) || {};
    } catch (_) {
      this.p = {};
    }
  },

  build() {
    let p = this.p;
    let ficha;
    let ex;

    try {
      const s = carregarSessao();

      if (s && s.fase === "finalizacao") {
        replace({
          url: "page/gt/resumo/index.page",
          params: JSON.stringify(s),
        });
        return;
      }

      if (
        s &&
        s.fase === "exercicio" &&
        s.inicio === p.inicio &&
        s.t === p.t &&
        s.ex === p.ex &&
        s.serie === p.serie
      ) {
        p = s;
      }

      ficha = carregarFichas()[p.t || 0];
      ex = ficha.exercicios[p.ex || 0];

      if (!ex) {
        throw new Error("Exercício indisponível");
      }

      p = {
        ...p,
        t: p.t || 0,
        ex: p.ex || 0,
        serie: p.serie || 1,
        inicio: p.inicio || Date.now(),
        feitas: p.feitas || 0,
        exs: p.exs || 0,
      };

      p = salvarSessao({
        ...p,
        fase: "exercicio",
      });
    } catch (e) {
      aviso(e.message);
      return;
    }

    let carga;
    let anterior;

    try {
      anterior = ultimaCarga(ficha, ex);
      carga = p.carga === undefined
        ? anterior
        : p.carga;
    } catch (e) {
      aviso(e.message);
      return;
    }

    let reps = p.reps || 0;
    let bloqueado = false;
    let editando = false;
    let destruido = false;
    let acumulado = 0;
    let teclaCoroa = KEY_HOME;
    let timerRoda = null;
    let ultimoStatus = 0;

    const salvo = (p.modelosMovimento || []).find(
      (m) => m.exercicioId === ex.id
    );

    const det = criarDetectorAdaptativo({
      modelo: salvo && salvo.modelo,
    });

    const guardarModelo = () => {
      const lista = (p.modelosMovimento || []).filter(
        (m) => m.exercicioId !== ex.id
      );

      const modelo = det.exportarModelo();

      if (modelo) {
        lista.push({
          exercicioId: ex.id,
          modelo,
        });
      }

      return lista;
    };

    const texto = (
      x, y, w, h, text, size, color = 0xffffff
    ) => hmUI.createWidget(hmUI.widget.TEXT, {
      x: px(x),
      y: px(y),
      w: px(w),
      h: px(h),
      text,
      text_size: px(size),
      color,
      text_style: hmUI.text_style.ELLIPSIS,
      align_h: hmUI.align.CENTER_H,
      align_v: hmUI.align.CENTER_V,
    });

    const botao = (
      x, y, w, h, text, click_func, verde = false
    ) => hmUI.createWidget(hmUI.widget.BUTTON, {
      x: px(x),
      y: px(y),
      w: px(w),
      h: px(h),
      radius: px(24),
      text,
      text_size: px(22),
      normal_color: verde ? LIMA : 0x202020,
      press_color: verde ? 0x8fc700 : 0x353535,
      color: verde ? 0x000000 : 0xffffff,
      click_func,
    });

    try {
      display.setPageBrightTime({
        brightTime: 300000,
      });

      display.pauseDropWristScreenOff({
        duration: 300000,
      });
    } catch (_) {}

    hmUI.createWidget(hmUI.widget.FILL_RECT, {
      x: 0,
      y: 0,
      w: DEVICE_WIDTH,
      h: DEVICE_HEIGHT,
      color: 0x000000,
    });

    const arco = {
      x: 0,
      y: 0,
      w: DEVICE_WIDTH,
      h: DEVICE_HEIGHT,
      line_width: px(14),
      start_angle: -90,
    };

    hmUI.createWidget(hmUI.widget.ARC, {
      ...arco,
      end_angle: 270,
      color: 0x1c1c1e,
    });

    const anel = hmUI.createWidget(hmUI.widget.ARC, {
      ...arco,
      end_angle: -90,
      color: LIMA,
    });

    texto(105, 52, 270, 38, ex.nome, 26);

    if (ex.series <= 10) {
      const largura =
        ex.series * 14 + (ex.series - 1) * 10;

      for (let i = 0; i < ex.series; i++) {
        hmUI.createWidget(hmUI.widget.FILL_RECT, {
          x: px(240 - largura / 2 + i * 24),
          y: px(96),
          w: px(14),
          h: px(14),
          radius: px(7),

          color:
            i < p.serie - 1
              ? LIMA
              : i === p.serie - 1
                ? 0xffffff
                : 0x3a3a3c,
        });
      }
    } else {
      texto(
        130, 90, 220, 26,
        `SÉRIE ${p.serie} DE ${ex.series}`,
        18,
        LIMA
      );
    }

    const contador = texto(
      125, 116, 230, 110, "00", 96
    );

    contador.addEventListener(
      hmUI.event.CLICK_UP,
      () => contar(1)
    );

    const sub = texto(
      90, 228, 300, 26, "", 18, 0xaaaaaa
    );

    const peso = (x, rotulo, valor, editar) => {
      const fundo = hmUI.createWidget(
        hmUI.widget.FILL_RECT,
        {
          x: px(x),
          y: px(262),
          w: px(140),
          h: px(100),
          radius: px(18),
          color: editar ? 0x12170a : 0x101010,
        }
      );

      const titulo = texto(
        x + 4, 264, 132, 24,
        rotulo,
        17,
        editar ? LIMA : 0x999999
      );

      const numero = texto(
        x + 4, 288, 132, 46,
        fmt(valor),
        fmt(valor).length > 4 ? 34 : 44
      );

      const unidade = texto(
        x + 4, 336, 132, 24,
        editar ? "kg · EDITAR" : "kg",
        16,
        editar ? LIMA : 0x999999
      );

      if (editar) {
        [fundo, titulo, numero, unidade].forEach((w) => {
          w.addEventListener(
            hmUI.event.CLICK_UP,
            () => abrir()
          );
        });
      }

      return numero;
    };

    peso(90, "ANTERIOR", anterior, false);

    const cargaTxt = peso(
      250, "ATUAL", carga, true
    );

    botao(
      120, 376, 240, 54,
      "PULAR",
      () => encaminhar(false, "coroa")
    );

    const overlay = [];

    const ov = (w) => {
      overlay.push(w);
      return w;
    };

    ov(hmUI.createWidget(hmUI.widget.FILL_RECT, {
      x: 0,
      y: 0,
      w: DEVICE_WIDTH,
      h: DEVICE_HEIGHT,
      color: 0x000000,
    }));

    ov(texto(
      110, 54, 260, 36,
      "PESO ATUAL",
      26,
      LIMA
    ));

    ov(texto(
      110, 94, 260, 26,
      "GIRE OU TOQUE − / +",
      17,
      0xaaaaaa
    ));

    ov(hmUI.createWidget(hmUI.widget.FILL_RECT, {
      x: px(110),
      y: px(206),
      w: px(260),
      h: px(64),
      radius: px(28),
      color: 0x12170a,
    }));

    const slots = [0, 1, 2, 3, 4].map(
      () => ov(texto(125, 208, 230, 60, "", 48))
    );

    ov(botao(
      48, 213, 56, 52,
      "−",
      () => mudarPeso(alvo - 1)
    ));

    ov(botao(
      376, 213, 56, 52,
      "+",
      () => mudarPeso(alvo + 1)
    ));

    ov(texto(
      170, 340, 140, 24,
      "kg",
      20,
      LIMA
    ));

    ov(botao(
      120, 378, 240, 54,
      "OK",
      () => fechar(),
      true
    ));

    const mostrar = (visivel) => {
      overlay.forEach((w) =>
        w.setProperty(hmUI.prop.VISIBLE, visivel)
      );
    };

    mostrar(false);

    let base = 0;
    let alvo = 0;
    let pos = 0;

    const valor = (i) =>
      Math.round((base + i * 2.5) * 100) / 100;

    const render = () => {
      const centro = Math.round(pos);

      slots.forEach((w, k) => {
        const i = centro + k - 2;
        const d = i - pos;
        const v = valor(i);
        const y = 208 + d * 72;

        const visivel =
          editando &&
          y >= 126 &&
          y + 60 <= 338 &&
          v >= 0 &&
          v <= 500;

        w.setProperty(
          hmUI.prop.VISIBLE,
          visivel
        );

        if (visivel) {
          w.setProperty(hmUI.prop.MORE, {
            y: px(y),
            text: fmt(v),

            text_size: px(
              Math.round(
                26 +
                22 * Math.max(0, 1 - Math.abs(d))
              )
            ),

            color:
              Math.abs(d) < 0.15
                ? 0xffffff
                : 0x888888,
          });
        }
      });
    };

    const mudarPeso = (novo) => {
      if (
        !editando ||
        valor(novo) < 0 ||
        valor(novo) > 500
      ) {
        return;
      }

      alvo = novo;

      if (timerRoda !== null) {
        clearInterval(timerRoda);
      }

      const origem = pos;
      const inicio = Date.now();

      timerRoda = setInterval(() => {
        const t = Math.min(
          1,
          (Date.now() - inicio) / 220
        );

        pos =
          origem +
          (alvo - origem) *
          (1 - Math.pow(1 - t, 3));

        render();

        if (t === 1) {
          clearInterval(timerRoda);
          timerRoda = null;
        }
      }, 20);
    };

    const abrir = () => {
      if (bloqueado) return;

      editando = true;
      acumulado = 0;
      base = carga;
      alvo = 0;
      pos = 0;

      mostrar(true);
      render();

      det.suspender(Date.now());
    };

    const fechar = () => {
      if (!editando || bloqueado) return;

      if (timerRoda !== null) {
        clearInterval(timerRoda);
        timerRoda = null;
      }

      carga = valor(alvo);

      cargaTxt.setProperty(hmUI.prop.MORE, {
        text: fmt(carga),
        text_size: px(
          fmt(carga).length > 4 ? 34 : 44
        ),
      });

      editando = false;
      mostrar(false);
      acumulado = 0;

      det.suspender(Date.now());
      salvar();
    };

    const atualizarStatus = () => {
      const estado = det.estado(Date.now());

      let msg =
        `META ${ex.reps} · COROA ENCERRA`;

      if (estado.fase === "aprendendo") {
        msg =
          `APRENDENDO ${estado.amostrasModelo}/3` +
          ` · META ${ex.reps}`;
      } else if (estado.fase === "reconhecendo") {
        msg = `RECONHECENDO · META ${ex.reps}`;
      } else if (
        estado.restanteMs !== null &&
        estado.restanteMs <= 2500
      ) {
        msg =
          `ENCERRANDO EM ` +
          `${Math.ceil(estado.restanteMs / 1000)} s`;
      }

      sub.setProperty(hmUI.prop.TEXT, msg);
    };

    const atualizar = () => {
      contador.setProperty(hmUI.prop.MORE, {
        text: String(reps).padStart(2, "0"),
        text_size: px(reps >= 100 ? 72 : 96),
      });

      atualizarStatus();

      anel.setProperty(hmUI.prop.MORE, {
        end_angle:
          -90 + 360 * Math.min(1, reps / ex.reps),
      });
    };

    const salvar = () => {
      try {
        p = salvarSessao({
          ...p,
          fase: "exercicio",
          carga,
          reps,
          modelosMovimento: guardarModelo(),
        });

        return true;
      } catch (e) {
        bloqueado = true;

        aviso(e.message, () => {
          if (salvar()) {
            bloqueado = false;

            replace({
              url: "page/gt/exercicio/index.page",
              params: JSON.stringify(p),
            });
          }
        });

        return false;
      }
    };

    const encaminhar = (concluiu, motivo) => {
      if (
        bloqueado ||
        editando ||
        destruido
      ) {
        return;
      }

      bloqueado = true;

      const historico = [
        ...(p.seriesRealizadas || []),
      ];

      if (concluiu) {
        historico.push({
          exercicioId: ex.id,
          exercicioNome: ex.nome,
          serie: p.serie,
          meta: ex.reps,
          repeticoes: reps,
          carga,
          fim: Date.now(),
          motivo,
        });
      }

      const ultima = p.serie >= ex.series;

      const proxima = {
        ...p,
        carga,
        reps: 0,
        seriesRealizadas: historico,
        modelosMovimento: guardarModelo(),
        feitas: p.feitas + (concluiu ? 1 : 0),
        exs: p.exs + (concluiu && ultima ? 1 : 0),
      };

      let destino;
      let dados;

      if (concluiu && !ultima) {
        destino = "descanso";

        dados = {
          ...proxima,
          fase: "descanso",
          serie: p.serie + 1,
          descanso: ex.descanso,
          fimAbs: Date.now() + ex.descanso * 1000,
        };
      } else if (
        p.ex < ficha.exercicios.length - 1
      ) {
        destino = "exercicio";

        dados = {
          ...proxima,
          fase: "exercicio",
          ex: p.ex + 1,
          serie: 1,
        };

        delete dados.carga;
        delete dados.fimAbs;
        delete dados.descanso;
      } else {
        destino = "resumo";

        dados = {
          ...proxima,
          fim: Date.now(),
        };
      }

      const executar = () => {
        try {
          if (concluiu) {
            salvarCarga(ficha, ex, carga);
          }

          if (destino === "resumo") {
            dados = prepararFinalizacao(
              dados,
              criarResultado(dados, ficha)
            );
          } else {
            dados = salvarSessao(dados);
          }

          vibrar("serie");

          replace({
            url: `page/gt/${destino}/index.page`,
            params: JSON.stringify(dados),
          });
        } catch (e) {
          aviso(e.message, executar);
        }
      };

      executar();
    };

    const contar = (quantidade) => {
      if (
        bloqueado ||
        editando ||
        destruido ||
        quantidade < 1
      ) {
        return;
      }

      const antes = reps;

      reps += quantidade;
      atualizar();

      if (!salvar()) return;

      if (
        antes < ex.reps &&
        reps >= ex.reps
      ) {
        det.pausaVibracao(Date.now());
        vibrar("rep");
      }
    };

    atualizar();

    if (!salvar()) return;

    try {
      const acc = new sensor.Accelerometer();
      this.acc = acc;

      try {
        acc.setFreqMode(sensor.FREQ_MODE_HIGH);
      } catch (_) {}

      acc.onChange(() => {
        if (
          bloqueado ||
          editando ||
          destruido
        ) {
          return;
        }

        const a = acc.getCurrent();
        const agora = Date.now();

        if (
          !a ||
          ![a.x, a.y, a.z].every(Number.isFinite)
        ) {
          return;
        }

        const quantidade = det.feed(
          a.x,
          a.y,
          a.z,
          agora
        );

        if (quantidade > 0) {
          contar(quantidade);
        }

        if (agora - ultimoStatus >= 250) {
          ultimoStatus = agora;
          atualizarStatus();
        }

        if (
          !bloqueado &&
          reps > 0 &&
          det.estado(agora).fimSerie
        ) {
          encaminhar(true, "pausa");
        }
      });

      acc.start();
    } catch (e) {
      sub.setProperty(
        hmUI.prop.TEXT,
        "TOQUE PARA CONTAR · COROA ENCERRA"
      );
    }

    onDigitalCrown({
      callback: (key, degree) => {
        teclaCoroa = key;

        if (
          !editando ||
          bloqueado ||
          !Number.isFinite(degree)
        ) {
          return;
        }

        acumulado -= degree;

        if (Math.abs(acumulado) >= 5) {
          mudarPeso(
            alvo + (acumulado > 0 ? 1 : -1)
          );

          acumulado = 0;
        }
      },
    });

    onKey({
      callback: (key, event) => {
        if (
          key !== teclaCoroa ||
          event !== KEY_EVENT_CLICK
        ) {
          return false;
        }

        if (!bloqueado) {
          if (editando) {
            fechar();
          } else {
            encaminhar(true, "coroa");
          }
        }

        return true;
      },
    });

    this.limpar = () => {
      destruido = true;

      if (timerRoda !== null) {
        clearInterval(timerRoda);
      }

      offKey();
      offDigitalCrown();
    };
  },

  onDestroy() {
    if (this.limpar) {
      this.limpar();
    }

    try {
      if (this.acc) {
        this.acc.offChange();
        this.acc.stop();
      }
    } catch (_) {}
  },
});