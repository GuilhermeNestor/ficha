import { ler, gravar } from "./armazenamento.js";
import { ultimaCarga } from "./cargas.js";

const CHAVE = "resultado_treino_v2";

function estado() {
  let e = ler(CHAVE, null);

  if (!e) {
    const antigos = ler("resultados_treino_v1", []);

    if (
      !Array.isArray(antigos) ||
      antigos.some(
        (r) => !r || typeof r.id !== "string" || !r.id
      )
    ) {
      throw new Error("Resultados antigos inválidos");
    }

    const ids = {};

    const migrados = antigos.filter((r) => {
      if (ids[r.id]) return false;
      ids[r.id] = true;
      return true;
    });

    e = {
      versao: 1,
      ultimo: null,

      // Exceção temporária: preserva todos os pendentes antigos.
      legados: migrados.map((r) => ({
        ...r,
        estado: "pendente",
      })),
    };

    gravar(CHAVE, e);
  }

  if (
    e.versao !== 1 ||
    !Array.isArray(e.legados) ||
    (e.ultimo &&
      !["pendente", "sincronizado"].includes(e.ultimo.estado))
  ) {
    throw new Error("Resultado salvo inválido");
  }

  return e;
}

export function carregarResultadosPendentes() {
  const e = estado();

  return [
    ...e.legados,
    ...(e.ultimo && e.ultimo.estado === "pendente"
      ? [e.ultimo]
      : []),
  ];
}

export function ultimoResultado() {
  return estado().ultimo;
}

export function podeIniciarTreino() {
  return carregarResultadosPendentes().length === 0;
}

export function criarResultado(p, ficha) {
  if (
    !Number.isFinite(p.inicio) ||
    !Number.isFinite(p.fim) ||
    p.fim < p.inicio
  ) {
    throw new Error("Horários inválidos");
  }

  return {
    versao: 1,
    id: p.id || `treino_${p.inicio}_${p.t}`,
    fichaId: ficha.id,
    fichaNome: ficha.nome,
    inicio: p.inicio,
    fim: p.fim,
    duracaoMs: p.fim - p.inicio,
    seriesConcluidas: p.feitas || 0,
    exerciciosConcluidos: p.exs || 0,

    cargas: ficha.exercicios.map((ex) => ({
      exercicioId: ex.id,
      exercicioNome: ex.nome,
      ultimaCarga: ultimaCarga(ficha, ex),
    })),

    estado: "pendente",
  };
}

export function salvarResultado(r) {
  if (
    !r ||
    typeof r.id !== "string" ||
    !r.id ||
    !r.fichaId ||
    !Array.isArray(r.cargas) ||
    !Number.isFinite(r.inicio) ||
    !Number.isFinite(r.fim) ||
    r.fim < r.inicio ||
    !Number.isInteger(r.seriesConcluidas) ||
    r.seriesConcluidas < 0 ||
    !Number.isInteger(r.exerciciosConcluidos) ||
    r.exerciciosConcluidos < 0
  ) {
    throw new Error("Resultado inválido");
  }

  const e = estado();

  if (e.ultimo && e.ultimo.id === r.id) {
    return true;
  }

  if (e.legados.some((x) => x.id === r.id)) {
    return true;
  }

  if (
    e.legados.length ||
    (e.ultimo && e.ultimo.estado === "pendente")
  ) {
    throw new Error("Sincronize o resultado anterior");
  }

  gravar(CHAVE, {
    ...e,
    ultimo: {
      ...r,
      estado: "pendente",
    },
  });

  return true;
}

export function confirmarResultado(ack) {
  if (
    !ack ||
    ack.versao !== 1 ||
    ack.persistido !== true ||
    typeof ack.resultadoId !== "string"
  ) {
    throw new Error("Confirmação inválida");
  }

  const e = estado();
  const i = e.legados.findIndex(
    (r) => r.id === ack.resultadoId
  );

  if (i >= 0) {
    e.legados.splice(i, 1);
    gravar(CHAVE, e);
    return;
  }

  if (!e.ultimo || e.ultimo.id !== ack.resultadoId) {
    throw new Error("Confirmação de outro treino");
  }

  gravar(CHAVE, {
    ...e,
    ultimo: {
      ...e.ultimo,
      estado: "sincronizado",
      sincronizadoEm: Date.now(),
    },
  });
}