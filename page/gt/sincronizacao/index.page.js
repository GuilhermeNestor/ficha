import * as hmUI from "@zos/ui";
import { px } from "@zos/utils";
import { replace } from "@zos/router";
import { BasePage } from "@zeppos/zml/base-page";
import { DEVICE_WIDTH, DEVICE_HEIGHT } from "../layout.js";
import {
  carregarResultadosPendentes,
  ultimoResultado,
  confirmarResultado,
} from "../resultados.js";
import { receberFichas, pacoteFichas } from "../ficha.js";

Page(BasePage({
  build() {
    this.ativo = true;
    this.ocupado = false;

    hmUI.createWidget(hmUI.widget.FILL_RECT, {
      x: 0, y: 0, w: DEVICE_WIDTH, h: DEVICE_HEIGHT,
      color: 0x000000,
    });

    this.rotulo = hmUI.createWidget(hmUI.widget.TEXT, {
      x: px(45), y: px(65),
      w: DEVICE_WIDTH - px(90), h: px(215),
      text: "",
      text_size: px(18), color: 0xffffff,
      text_style: hmUI.text_style.WRAP,
      align_h: hmUI.align.CENTER_H,
      align_v: hmUI.align.CENTER_V,
    });

    const botao = (y, text, click_func) =>
      hmUI.createWidget(hmUI.widget.BUTTON, {
        x: px(95), y: px(y),
        w: DEVICE_WIDTH - px(190), h: px(48),
        text, text_size: px(17),
        normal_color: 0xb6ff00,
        press_color: 0x8fc700,
        color: 0x000000,
        click_func,
      });

    botao(290, "SINCRONIZAR", () => this.sincronizar());
    botao(346, "VER RESULTADO", () => this.detalhes());

    botao(402, "VOLTAR", () => {
      if (!this.ocupado) {
        replace({ url: "page/gt/home/index.page" });
      }
    });

    this.atualizar();
  },

  mostrar(texto) {
    if (this.ativo) {
      this.rotulo.setProperty(hmUI.prop.TEXT, texto);
    }
  },

  atualizar() {
    try {
      const p = carregarResultadosPendentes();

      this.mostrar(
        `SINCRONIZAÇÃO\n` +
        `${p.length} resultado(s) pendente(s)\n` +
        `${p.length
          ? "Sincronize para liberar novo treino."
          : "Pronto para treinar."}\n` +
        `Abra o Zepp no celular.`
      );
    } catch (e) {
      this.mostrar(e.message);
    }
  },

  detalhes() {
    if (this.ocupado) return;

    try {
      const lista = carregarResultadosPendentes();

      if (!lista.length) {
        const ultimo = ultimoResultado();
        if (ultimo) lista.push(ultimo);
      }

      if (!lista.length) {
        this.mostrar("Nenhum resultado salvo.");
        return;
      }

      const paginas = [];

      lista.forEach((r) => {
        const d = new Date(r.inicio);

        paginas.push(
          `${r.fichaNome}\n` +
          `${d.getDate()}/${d.getMonth() + 1}/${d.getFullYear()}` +
          ` · ${Math.round(r.duracaoMs / 60000)} min\n` +
          `${r.seriesConcluidas} séries · ` +
          `${r.exerciciosConcluidos} exercícios\n` +
          `${r.estado}\n` +
          `Toque VER RESULTADO para avançar.`
        );

        (r.cargas || []).forEach((c) => {
          paginas.push(
            `${r.fichaNome}\n` +
            `${c.exercicioNome}\n` +
            `Última carga: ${
              c.ultimaCarga === null
                ? "indisponível"
                : c.ultimaCarga + " kg"
            }\n` +
            `Toque VER RESULTADO para avançar.`
          );
        });
      });

      this.indice = (this.indice || 0) % paginas.length;
      this.mostrar(paginas[this.indice++]);
    } catch (e) {
      this.mostrar(e.message);
    }
  },

  async sincronizar() {
    if (this.ocupado) return;

    this.ocupado = true;

    try {
      this.mostrar("Conectando ao celular...");

      const p = carregarResultadosPendentes();

      for (const resultado of p) {
        const ack = await this.pedir({
          method: "resultado.salvar",
          params: {
            versao: 1,
            resultado,
          },
        });

        if (!ack || ack.resultadoId !== resultado.id) {
          throw new Error(
            "Confirmação não corresponde ao treino"
          );
        }

        confirmarResultado(ack);
      }

      const atual = pacoteFichas();

      const resposta = await this.pedir({
        method: "fichas.obter",
        params: {
          versao: 1,
          revisao: atual.revisao,
        },
      });

      if (!resposta || resposta.versao !== 1) {
        throw new Error("Resposta de fichas inválida");
      }

      if (resposta.pacote) {
        receberFichas(resposta.pacote);
      } else if (resposta.semAlteracoes !== true) {
        throw new Error("Resposta incompleta");
      }

      this.mostrar(
        "SINCRONIZAÇÃO CONCLUÍDA\n" +
        "Resultados confirmados.\n" +
        "Volte para iniciar o treino."
      );
    } catch (e) {
      this.mostrar(
        `Não foi possível concluir.\n` +
        `${e.message || e}\n` +
        `Pendências preservadas.`
      );
    } finally {
      this.ocupado = false;
    }
  },

  pedir(req) {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error("Sem resposta do celular")),
        15000
      );

      this.request(req).then(
        (r) => {
          clearTimeout(timer);

          if (r && r.erro) {
            reject(new Error(r.erro));
          } else {
            resolve(r);
          }
        },
        (e) => {
          clearTimeout(timer);
          reject(e);
        }
      );
    });
  },

  onDestroy() {
    this.ativo = false;
  },
}));