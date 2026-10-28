import { LocalStorage } from "@zos/storage";

const storage = new LocalStorage();

export function ler(chave, inicial) {
  const bruto = storage.getItem(chave);

  if (bruto === null || bruto === undefined || bruto === "") {
    return inicial;
  }

  try {
    return JSON.parse(bruto);
  } catch (e) {
    throw new Error("Dados inválidos: " + chave);
  }
}

export function gravar(chave, valor) {
  const texto = JSON.stringify(valor);

  storage.setItem(chave, texto);

  if (storage.getItem(chave) !== texto) {
    throw new Error("Falha ao confirmar gravação");
  }
}

export function lerCarga(chave) {
  return storage.getItem(chave);
}

export function gravarCarga(chave, carga) {
  const texto = String(carga);

  storage.setItem(chave, texto);

  if (storage.getItem(chave) !== texto) {
    throw new Error("Falha ao salvar carga");
  }
}