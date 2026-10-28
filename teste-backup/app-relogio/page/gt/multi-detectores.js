// Roda vários detectores ao mesmo tempo sobre as MESMAS leituras do acelerômetro, para comparar.
// O detector principal ("picos") é o que conta na tela. Os outros só são gravados.
import { criarDetector as criarLivre } from './detector.js';
import { criarDetectorAdaptativo as criarAdaptativo } from './detector-adaptativo.js';
import { criarDetectorAdaptativo as criarPicos } from './detector-novo.js';
import { criarDetectorVetorial } from './detector-vetorial.js';

export const NOME_PRINCIPAL = 'picos';
export const ABREVIACOES = { picos: 'pic', adaptativo: 'adp', livre: 'liv', vetorial: 'vet', 'vetorial+molde': 'v+m' };

// salvo: entrada guardada na sessão para este exercício ({modelo, modeloA, modeloV}) ou undefined
export function criarMultiplos(salvo) {
  const s = salvo || {};
  const principal = criarPicos({ modelo: s.modelo });
  const outros = [
    { nome: 'adaptativo', chave: 'modeloA', det: criarAdaptativo({ modelo: s.modeloA }) },
    { nome: 'livre', chave: null, det: criarLivre({ deltaMin: 60, fatorDelta: 0.35, intervaloMin: 700, atrasoInicial: 1200 }) },
    { nome: 'vetorial', chave: null, det: criarDetectorVetorial({ usarMolde: false }) },
    { nome: 'vetorial+molde', chave: 'modeloV', det: criarDetectorVetorial({ modelo: s.modeloV, usarMolde: true }) },
  ];
  const cpu = {};
  [NOME_PRINCIPAL, ...outros.map((o) => o.nome)].forEach((n) => { cpu[n] = { ms: 0, max: 0, n: 0, erros: 0 }; });

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
    nomes: [NOME_PRINCIPAL, ...outros.map((o) => o.nome)],
    // alimenta todos; devolve {quantidade (principal), parciais: {nome: n}}
    alimentar(x, y, z, agora) {
      const quantidade = medir(NOME_PRINCIPAL, () => principal.feed(x, y, z, agora));
      const parciais = {};
      for (const o of outros) {
        const q = medir(o.nome, () => o.det.feed(x, y, z, agora));
        if (q > 0) parciais[o.nome] = q;
      }
      return { quantidade, parciais };
    },
    suspender(agora) {
      principal.suspender(agora);
      for (const o of outros) {
        try { if (o.det.suspender) o.det.suspender(agora); else if (o.det.reiniciar) o.det.reiniciar(agora); } catch (_) {}
      }
    },
    pausaVibracao(agora) {
      principal.pausaVibracao(agora);
      for (const o of outros) { try { if (o.det.pausaVibracao) o.det.pausaVibracao(agora); } catch (_) {} }
    },
    // entrada para guardar na sessão (mantém modelos antigos se a série não gerou novos)
    modelos(id, antigo) {
      const e = { exercicioId: id };
      const a = antigo || {};
      const m = principal.exportarModelo();
      if (m) e.modelo = m; else if (a.modelo) e.modelo = a.modelo;
      for (const o of outros) {
        if (!o.chave) continue;
        let mm = null;
        try { mm = o.det.exportarModelo ? o.det.exportarModelo() : null; } catch (_) {}
        if (mm) e[o.chave] = mm; else if (a[o.chave]) e[o.chave] = a[o.chave];
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