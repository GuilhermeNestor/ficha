import { treinos } from "./dados.js";
import { ler, gravar } from "./armazenamento.js";
import { carregarSessao } from "./sessao.js";

const CHAVE = "fichas_treino_v2";

function texto(v) {
  return typeof v === "string" && v.length > 0 && v.length <= 100;
}

export function validarFichas(fichas, legado = false) {
  if (
    !Array.isArray(fichas) ||
    !fichas.length ||
    fichas.length > 20
  ) {
    throw new Error("Lista de fichas inválida");
  }

  const ids = {};

  return fichas.map((f) => {
    if (!f || !texto(f.id) || !texto(f.nome) || ids[f.id]) {
      throw new Error("ID ou nome de ficha inválido");
    }

    ids[f.id] = true;

    if (
      !Array.isArray(f.exercicios) ||
      !f.exercicios.length ||
      f.exercicios.length > 40
    ) {
      throw new Error("Exercícios inválidos");
    }

    const exIds = {};

    return {
      id: f.id,
      nome: f.nome,

      exercicios: f.exercicios.map((e, i) => {
        if (!e) {
          throw new Error("Exercício inválido");
        }

        const id =
          e.id ||
          (legado ? `${f.id}_ex_${i + 1}` : null);

        if (!texto(id) || exIds[id] || !texto(e.nome)) {
          throw new Error("ID ou nome de exercício inválido");
        }

        exIds[id] = true;

        if (
          !Number.isInteger(e.series) ||
          e.series < 1 ||
          e.series > 50 ||
          !Number.isInteger(e.reps) ||
          e.reps < 1 ||
          e.reps > 200 ||
          !Number.isFinite(e.carga) ||
          e.carga < 0 ||
          e.carga > 500 ||
          !Number.isInteger(e.descanso) ||
          e.descanso < 5 ||
          e.descanso > 3600
        ) {
          throw new Error("Valores do exercício inválidos");
        }

        return {
          id,
          nome: e.nome,
          series: e.series,
          reps: e.reps,
          carga: e.carga,
          descanso: e.descanso,
          ...(legado
            ? { nomeLegado: e.nomeLegado || e.nome }
            : {}),
        };
      }),
    };
  });
}

export function pacoteFichas() {
  let p = ler(CHAVE, null);

  if (!p) {
    p = {
      versao: 1,
      revisao: 0,
      fichas: validarFichas(
        ler("fichas_treino_v1", treinos),
        true
      ),
    };

    gravar(CHAVE, p);
  }

  if (
    p.versao !== 1 ||
    !Number.isInteger(p.revisao) ||
    p.revisao < 0
  ) {
    throw new Error("Versão de fichas inválida");
  }

  validarFichas(p.fichas);

  return p;
}

export function carregarFichas() {
  return pacoteFichas().fichas;
}

export function receberFichas(p) {
  if (carregarSessao()) {
    throw new Error(
      "Finalize ou descarte a sessão antes de atualizar fichas"
    );
  }

  if (
    !p ||
    p.versao !== 1 ||
    !Number.isInteger(p.revisao) ||
    p.revisao < 1
  ) {
    throw new Error("Pacote inválido");
  }

  const fichas = validarFichas(p.fichas);
  const atual = pacoteFichas();

  if (p.revisao < atual.revisao) {
    throw new Error("Revisão antiga");
  }

  if (p.revisao === atual.revisao) {
    if (
      JSON.stringify(fichas) !==
      JSON.stringify(validarFichas(atual.fichas))
    ) {
      throw new Error("Conflito de revisão");
    }

    return { revisao: atual.revisao };
  }

  // Preserva o vínculo com as cargas gravadas pelo app antigo.
  fichas.forEach((f) =>
    f.exercicios.forEach((e) => {
      const af = atual.fichas.find((x) => x.id === f.id);
      const ae = af && af.exercicios.find((x) => x.id === e.id);

      if (ae && ae.nomeLegado) {
        e.nomeLegado = ae.nomeLegado;
      }
    })
  );

  gravar(CHAVE, {
    versao: 1,
    revisao: p.revisao,
    fichas,
  });

  return { revisao: p.revisao };
}

export function salvarFichas(fichas) {
  const atual = pacoteFichas();

  receberFichas({
    versao: 1,
    revisao: atual.revisao + 1,
    fichas,
  });

  return true;
}

export function atualizarFicha(ficha) {
  const fichas = carregarFichas();
  const i = fichas.findIndex((f) => f.id === ficha.id);

  if (i < 0) {
    fichas.push(ficha);
  } else {
    fichas[i] = ficha;
  }

  return salvarFichas(fichas);
}