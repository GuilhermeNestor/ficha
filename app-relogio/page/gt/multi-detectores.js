import { criarDetectorAdaptativo as criarPicos } from './detector-novo.js';

export const NOME_PRINCIPAL = 'picos';

// Os nomes antigos servem para ler registros já gravados.
// Eles não carregam nem executam os outros detectores.
export const ABREVIACOES = {
  picos: 'pic',
  'vetorial+molde': 'v+m',
  adaptativo: 'adp',
};

// Mantém o nome usado pela tela de exercício.
// Agora cria apenas um detector por série.
export function criarMultiplos(salvo) {
  const principal = criarPicos({ modelo: salvo && salvo.modelo });
  const leitura = { quantidade: 0, parciais: {} };

  return {
    principal,
    nomes: [NOME_PRINCIPAL],

    alimentar(x, y, z, agora) {
      leitura.quantidade = principal.feed(x, y, z, agora);
      return leitura;
    },

    suspender: t => principal.suspender(t),

    pausaVibracao: t => principal.pausaVibracao(t),

    modelos(id, antigo) {
      const entrada = { ...(antigo || {}), exercicioId: id };
      const modelo = principal.exportarModelo();
      if (modelo) entrada.modelo = modelo;
      return entrada;
    },

    // O modo de treino não mede o tempo de CPU por leitura.
    cpu: () => ({}),
  };
}

// Compatibilidade com os registros de comparação anteriores.
export function contarEventos(eventos, limiteMs, nomes) {
  const lim = limiteMs === undefined || limiteMs === null
    ? Infinity
    : limiteMs;

  const r = {};

  (nomes || Object.keys(ABREVIACOES)).forEach(n => {
    r[n] = { serie: 0, apos: 0 };
  });

  const somar = (nome, t, q) => {
    if (!r[nome]) r[nome] = { serie: 0, apos: 0 };
    if (t <= lim) r[nome].serie += q;
    else r[nome].apos += q;
  };

  for (const e of eventos) {
    if (e.tipo === 'rep_detector') {
      somar(NOME_PRINCIPAL, e.t, e.quantidade);
    } else if (e.tipo === 'rep_outro') {
      somar(e.detector, e.t, e.quantidade);
    }
  }

  return r;
}

export function resumoTexto(porDetector) {
  return Object.keys(ABREVIACOES)
    .filter(n => porDetector[n])
    .map(n => `${ABREVIACOES[n]} ${porDetector[n].serie}`)
    .join(' · ');
}f