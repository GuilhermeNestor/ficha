
import { LocalStorage } from "@zos/storage";

const CHAVE = "sessao_treino";
const VALIDADE_MS = 6 * 60 * 60 * 1000;

const storage = new LocalStorage();

export function salvarSessao(dados) {
  try {
    const sessao = {
      ...dados,
      atualizado: Date.now(),
    };

    storage.setItem(CHAVE, JSON.stringify(sessao));
  } catch (e) {
    console.log("Erro ao salvar sessão:", e);
  }
}

export function limparSessao() {
  try {
    storage.removeItem(CHAVE);
  } catch (e) {
    try {
      storage.setItem(CHAVE, "");
    } catch (erro) {
      console.log("Erro ao limpar sessão:", erro);
    }
  }
}

export function carregarSessao() {
  try {
    const bruto = storage.getItem(CHAVE);

    if (!bruto) return null;

    const sessao = JSON.parse(bruto);

    if (
      !sessao ||
      !sessao.atualizado ||
      Date.now() - sessao.atualizado > VALIDADE_MS
    ) {
      limparSessao();
      return null;
    }

    return sessao;
  } catch (e) {
    console.log("Erro ao carregar sessão:", e);
    return null;
  }
}
