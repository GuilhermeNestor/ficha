import { lerCarga, gravarCarga } from "./armazenamento.js";

const chave = (ficha, ex) =>
  `carga_v2_${JSON.stringify([ficha.id, ex.id])}`;

export function ultimaCarga(ficha, ex) {
  let v = lerCarga(chave(ficha, ex));

  if (
    (v === undefined || v === null || v === "") &&
    ex.nomeLegado
  ) {
    v = lerCarga(`ultimo_${ex.nomeLegado}`);
  }

  if (v === undefined || v === null || v === "") {
    return ex.carga;
  }

  const n = Number(v);

  if (!Number.isFinite(n) || n < 0 || n > 500) {
    throw new Error("Carga salva inválida");
  }

  return n;
}

export function salvarCarga(ficha, ex, carga) {
  gravarCarga(chave(ficha, ex), carga);
}