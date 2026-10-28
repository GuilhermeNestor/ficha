// Roda vários detectores ao mesmo tempo sobre as MESMAS leituras do acelerômetro, para comparar.
// O detector principal ("picos") é o que conta na tela. Os outros só são gravados.
import { criarDetectorAdaptativo as criarAdaptativo } from './detector-adaptativo.js';
import { criarDetectorAdaptativo as criarPicos } from './detector-novo.js';
import { criarDetectorVetorial } from './detector-vetorial.js';

// Detectores que rodam juntos. O PRINCIPAL conta na tela e encerra a série; os outros só são gravados.
// Para trocar o principal, mude só a linha abaixo para 'picos', 'vetorial+molde' ou 'adaptativo'.
export const NOME_PRINCIPAL = 'picos';
export const ABREVIACOES = { picos: 'pic', 'vetorial+molde': 'v+m', adaptativo: 'adp' };

// chave: onde o modelo de cada detector fica guardado na sessão (por exercício)
const FABRICAS = {
  picos: { chave: 'modelo', criar: (m) => criarPicos({ modelo: m }) },
  'vetorial+molde': { chave: 'modeloV', criar: (m) => criarDetectorVetorial({ modelo: m, usarMolde: true }) },
  adaptativo: { chave: 'modeloA', criar: (m) => criarAdaptativo({ modelo: m }) },
};

// salvo: entrada guardada na sessão para este exercício ({modelo, modeloV, modeloA}) ou undefined
export function criarMultiplos(salvo) {
  const s = salvo || {};
  const nomes = Object.keys(FABRICAS);
  const dets = {};
  nomes.forEach((n) => { dets[n] = FABRICAS[n].criar(s[FABRICAS[n].chave]); });
  const principal = dets[NOME_PRINCIPAL];
  const outros = nomes.filter((n) => n !== NOME_PRINCIPAL);
  const cpu = {};
  nomes.forEach((n) => { cpu[n] = { ms: 0, max: 0, n: 0, erros: 0 }; });

  const medir = (nome, fn) => {
    const c = cpu[nome], t0 = Date.now();
    let r = 0;
    try { r = fn(); } catch (_) { c.erros++; }
    const d = Date.now() - t0;
    c.ms += d; c.n++; if (d > c.max) c.max = d;
    return r === true ? 1 : (Number.isFinite(r) ? r : 0);
  };

  return {
    principal,
    nomes: [NOME_PRINCIPAL, ...outros],
    // alimenta todos; devolve {quantidade (principal), parciais: {nome: n}}
    alimentar(x, y, z, agora) {
      const quantidade = medir(NOME_PRINCIPAL, () => principal.feed(x, y, z, agora));
      const parciais = {};
      for (const n of outros) {
        const q = medir(n, () => dets[n].feed(x, y, z, agora));
        if (q > 0) parciais[n] = q;
      }
      return { quantidade, parciais };
    },
    suspender(agora) {
      for (const n of nomes) { try { dets[n].suspender(agora); } catch (_) {} }
    },
    pausaVibracao(agora) {
      for (const n of nomes) { try { dets[n].pausaVibracao(agora); } catch (_) {} }
    },
    // entrada para guardar na sessão (mantém modelos antigos se a série não gerou novos)
    modelos(id, antigo) {
      const e = { exercicioId: id };
      const a = antigo || {};
      for (const n of nomes) {
        const k = FABRICAS[n].chave;
        let m = null;
        try { m = dets[n].exportarModelo ? dets[n].exportarModelo() : null; } catch (_) {}
        if (m) e[k] = m; else if (a[k]) e[k] = a[k];
      }
      return e;
    },
    cpu() {
      const r = {};
      for (const n in cpu) r[n] = { ms: cpu[n].ms, max: cpu[n].max, n: cpu[n].n, erros: cpu[n].erros };
      return r;
    },
  };
}

// Conta as reps de cada detector a partir dos eventos gravados.
// limiteMs: reps até esse instante contam como "da série"; as seguintes, como "após".
export function contarEventos(eventos, limiteMs, nomes) {
  const lim = limiteMs === undefined || limiteMs === null ? Infinity : limiteMs;
  const r = {};
  (nomes || Object.keys(ABREVIACOES)).forEach((n) => { r[n] = { serie: 0, apos: 0 }; });
  const somar = (nome, t, q) => {
    if (!r[nome]) r[nome] = { serie: 0, apos: 0 };
    if (t <= lim) r[nome].serie += q; else r[nome].apos += q;
  };
  for (const e of eventos) {
    if (e.tipo === 'rep_detector') somar(NOME_PRINCIPAL, e.t, e.quantidade);
    else if (e.tipo === 'rep_outro') somar(e.detector, e.t, e.quantidade);
  }
  return r;
}

export function resumoTexto(porDetector) {
  return Object.keys(ABREVIACOES)
    .filter((n) => porDetector[n])
    .map((n) => `${ABREVIACOES[n]} ${porDetector[n].serie}`)
    .join(' · ');
}