import { ler, gravar } from "./armazenamento.js";

const CHAVE = "sessao_treino";
const VALIDADE_MS = 6 * 60 * 60 * 1000;

export function salvarSessao(dados) {
  const atual = ler(CHAVE, null);

  if (
    atual &&
    atual.fase === "finalizacao" &&
    dados.fase !== "finalizacao"
  ) {
    throw new Error("Finalize o resultado pendente primeiro");
  }

  const id =
    dados.id ||
    (atual && atual.inicio === dados.inicio && atual.id) ||
    `treino_${dados.inicio}_${dados.t}`;

  const sessao = {
    ...dados,
    seriesRealizadas:
      dados.seriesRealizadas ||
      (atual && atual.id === id && atual.seriesRealizadas) ||
      [],
    id,
    atualizado: Date.now(),
  };

  gravar(CHAVE, sessao);

  return sessao;
}

export function limparSessao() {
  gravar(CHAVE, null);
}

export function carregarSessao() {
  const s = ler(CHAVE, null);

  if (!s) return null;

  if (!s.atualizado || !Number.isFinite(s.inicio) || !s.fase) {
    throw new Error("Sessão inválida; dados preservados");
  }

  if (
    s.fase !== "finalizacao" &&
    Date.now() - s.atualizado > VALIDADE_MS
  ) {
    limparSessao();
    return null;
  }

  return s;
}

export function prepararFinalizacao(params, resultado) {
  return salvarSessao({
    ...params,
    id: resultado.id,
    fase: "finalizacao",
    resultado,
  });
}