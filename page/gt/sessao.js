import { LocalStorage } from "@zos/storage";

const CHAVE = "sessao_treino";
const VALIDADE_MS = 6 * 60 * 60 * 1000;   // depois de 6 h, descarta
const storage = new LocalStorage();

export function salvarSessao(dados) {
  try {
    storage.setItem(CHAVE, JSON.stringify({ ...dados, atualizado: Date.now() }));
  } catch (e) {}
}

export function limparSessao() {
  try {
    storage.removeItem(CHAVE);
  } catch (e) {
    try { storage.setItem(CHAVE, ""); } catch (e2) {}
  }
}

export function carregarSessao() {
  try {
    const bruto = storage.getItem(CHAVE);
    if (!bruto) return null;
    const s = JSON.parse(bruto);
    if (!s || !s.atualizado || Date.now() - s.atualizado > VALIDADE_MS) {
      limparSessao();
      return null;
    }
    return s;
  } catch (e) {
    return null;
  }
}