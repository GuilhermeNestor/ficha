
import { LocalStorage } from "@zos/storage";
import { treinos } from "./dados.js";

const storage = new LocalStorage();

const CHAVE_FICHAS = "fichas_treino_v1";

// Carrega as fichas salvas no relógio.
// Na primeira execução, usa as fichas atuais como base.
export function carregarFichas() {
  try {
    const salvo = storage.getItem(CHAVE_FICHAS);

    if (salvo) {
      const fichas = JSON.parse(salvo);

      if (Array.isArray(fichas)) {
        return fichas;
      }
    }
  } catch (erro) {
    console.log("Erro ao carregar fichas:", erro);
  }

  return treinos.map((ficha) => ({
    ...ficha,
    exercicios: ficha.exercicios.map((exercicio) => ({
      ...exercicio,
    })),
  }));
}

// Salva todas as fichas no armazenamento local.
export function salvarFichas(fichas) {
  try {
    if (!Array.isArray(fichas)) {
      return false;
    }

    storage.setItem(CHAVE_FICHAS, JSON.stringify(fichas));
    return true;
  } catch (erro) {
    console.log("Erro ao salvar fichas:", erro);
    return false;
  }
}

// Atualiza uma ficha existente ou adiciona uma nova.
export function atualizarFicha(ficha) {
  if (!ficha || !ficha.id) {
    return false;
  }

  const fichas = carregarFichas();
  const indice = fichas.findIndex(
    (item) => item.id === ficha.id
  );

  if (indice >= 0) {
    fichas[indice] = ficha;
  } else {
    fichas.push(ficha);
  }

  return salvarFichas(fichas);
}