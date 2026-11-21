import { criarDetector } from './detector.js';

const MIN_REPS_APRENDER = 3;
const AMOSTRA_MS = 40;
const JANELA_LATERAL_MS = 700;
const MIN_CONCENTRACAO = 0.70;
const MIN_ALINHAMENTO = 0.90;
const MIN_FRACAO_DIRECAO = 0.60;
const copiar = v => JSON.parse(JSON.stringify(v));
const produto = (a, b) => a.reduce((s, v, i) => s + v * b[i], 0);
const norma = v => Math.sqrt(produto(v, v));
const mediana = lista => lista.slice().sort((a, b) => a - b)[Math.floor(lista.length / 2)];

function lerModelo(m) {
  if (!m || m.versao !== 2 || !Array.isArray(m.direcao) ||
      m.direcao.length !== 3 || !m.direcao.every(Number.isFinite) ||
      !Number.isFinite(m.duracao) || m.duracao < 700 || m.duracao > 8000) return null;
  const n = norma(m.direcao);
  if (n < 0.9 || n > 1.1) return null;
  return { versao: 2, direcao: m.direcao.map(v => v / n), duracao: m.duracao };
}

// Covariância dos três eixos, retirando a média de cada janela.
function covariancia(amostras) {
  if (amostras.length < 6) return null;
  const media = [0, 1, 2].map(k =>
    amostras.reduce((s, a) => s + a.v[k], 0) / amostras.length);
  const c = [[0, 0, 0], [0, 0, 0], [0, 0, 0]];
  amostras.forEach(a => {
    const d = a.v.map((v, k) => v - media[k]);
    for (let i = 0; i < 3; i++)
      for (let j = 0; j < 3; j++) c[i][j] += d[i] * d[j] / amostras.length;
  });
  return c;
}
const aplicar = (c, u) => c.map(linha => produto(linha, u));
const energia = c => c[0][0] + c[1][1] + c[2][2];

function analisarCiclo(amostras) {
  if (amostras.length < 12) return null;
  const duracao = amostras[amostras.length - 1].t - amostras[0].t;
  if (duracao < 700 || duracao > 8000) return null;
  const c = covariancia(amostras);
  const total = energia(c);
  if (total < 900) return null;
  // Começa no eixo com maior variância, evitando um vetor inicial ortogonal.
  let eixo = 0;
  for (let i = 1; i < 3; i++) if (c[i][i] > c[eixo][eixo]) eixo = i;
  let u = [0, 0, 0]; u[eixo] = 1;
  for (let i = 0; i < 10; i++) {
    const v = aplicar(c, u), n = norma(v);
    if (n < 0.0001) return null;
    u = v.map(x => x / n);
  }
  const concentracao = produto(u, aplicar(c, u)) / total;
  if (concentracao < MIN_CONCENTRACAO) return null;
  return { direcao: u, duracao };
}

export function criarDetectorAdaptativo(opcoes = {}) {
  let modelo = lerModelo(opcoes.modelo);
  let detectorLivre, detectorEixo, suave, anterior, inicio;
  let janela, ciclo, candidatos, ultimaColeta, ultimoValido;
  let ativo, fim, lateral, fracao, ciclosValidos;
  let bloqueadoAte = 0;

  const novoLivre = () => criarDetector({ deltaMin: 60, fatorDelta: 0.35,
    intervaloMin: 700, atrasoInicial: 1200 });
  const novoEixo = () => criarDetector({ deltaMin: 60, fatorDelta: 0.35,
    intervaloMin: 700, atrasoInicial: 300 });

  function reiniciar() {
    detectorLivre = novoLivre(); detectorEixo = novoEixo();
    suave = null; anterior = null; inicio = null;
    janela = []; ciclo = []; candidatos = [];
    ultimaColeta = null; ultimoValido = null;
    ativo = false; fim = false; lateral = false; fracao = 1; ciclosValidos = 0;
  }
  reiniciar();

  // Maior que a duração de uma repetição típica; nunca menor que 5 segundos.
  const limitePausa = () => Math.max(5000,
    Math.min(18000, modelo ? modelo.duracao * 2 + 1500 : 5000));

  function aprender(amostras) {
    const c = analisarCiclo(amostras);
    if (!c) { candidatos = []; return; }
    if (candidatos.some(a =>
      Math.abs(produto(a.direcao, c.direcao)) < MIN_ALINHAMENTO ||
      c.duracao / a.duracao < 0.5 || c.duracao / a.duracao > 2)) candidatos = [];
    candidatos.push(c);
    if (candidatos.length < MIN_REPS_APRENDER) return;
    const referencia = candidatos[0].direcao;
    const soma = [0, 0, 0];
    candidatos.forEach(a => {
      const sinal = produto(a.direcao, referencia) < 0 ? -1 : 1;
      a.direcao.forEach((v, k) => { soma[k] += v * sinal; });
    });
    const n = norma(soma);
    modelo = { versao: 2, direcao: soma.map(v => v / n),
      duracao: mediana(candidatos.map(a => a.duracao)) };
    // A direção fica fixa até terminar este treino/exercício.
    detectorEixo = novoEixo(); candidatos = [];
  }

  function feed(x, y, z, agora) {
    if (![x, y, z, agora].every(Number.isFinite) || fim || agora < bloqueadoAte) return 0;
    if (anterior !== null && agora <= anterior) return 0;
    if (anterior !== null && agora - anterior > 1000) reiniciar();
    const dt = anterior === null ? 40 : agora - anterior;
    anterior = agora;
    if (inicio === null) inicio = agora;
    if (!suave) suave = [x, y, z];
    const alfa = dt / (80 + dt);
    [x, y, z].forEach((v, k) => { suave[k] += (v - suave[k]) * alfa; });
    if (ultimaColeta === null || agora - ultimaColeta >= AMOSTRA_MS) {
      const a = { t: agora, v: suave.slice() };
      janela.push(a); ciclo.push(a); ultimaColeta = agora;
      while (janela.length && agora - janela[0].t > JANELA_LATERAL_MS) janela.shift();
      if (ciclo.length && agora - ciclo[0].t > 10000) { ciclo = [a]; candidatos = []; }
      lateral = false; fracao = 1;
      if (modelo && janela.length >= 6) {
        const c = covariancia(janela), total = energia(c);
        if (total >= 400) {
          fracao = Math.max(0, Math.min(1,
            produto(modelo.direcao, aplicar(c, modelo.direcao)) / total));
          lateral = fracao < MIN_FRACAO_DIRECAO;
        }
      }
    }
    let repeticao = false;
    if (!modelo) {
      // Contagem imediata enquanto aprende; sem bloqueio por três repetições.
      repeticao = detectorLivre.feed(x, y, z, agora);
      if (repeticao) aprender(ciclo);
    } else {
      const projecao = produto([x, y, z], modelo.direcao);
      const detectou = detectorEixo.feed(projecao, 0, 0, agora);
      if (lateral || agora - inicio < 1200) {
        // Movimento lateral invalida o ciclo e não renova o cronômetro.
        detectorEixo.reiniciar(agora);
      } else {
        repeticao = detectou;
      }
    }
    if (repeticao) {
      ativo = true; ultimoValido = agora; ciclosValidos++;
      ciclo = [{ t: agora, v: suave.slice() }];
    }
    if (ativo && ultimoValido !== null && agora - ultimoValido >= limitePausa()) fim = true;
    return repeticao ? 1 : 0;
  }

  function suspender(agora, duracao = 0) {
    reiniciar(); bloqueadoAte = agora + duracao;
  }
  function pausaVibracao(agora) {
    const estavaAtivo = ativo, quantidade = ciclosValidos;
    reiniciar(); ativo = estavaAtivo; ciclosValidos = quantidade;
    bloqueadoAte = agora + 450;
    ultimoValido = estavaAtivo ? bloqueadoAte : null;
  }
  function estado(agora) {
    return { aprendeu: !!modelo, fase: fim ? 'fim' : modelo ? 'serie' : 'aprendendo',
      amostrasModelo: modelo ? MIN_REPS_APRENDER : candidatos.length,
      lateral, fracaoNaDirecao: fracao,
      direcao: modelo ? modelo.direcao.slice() : null,
      pausaMs: limitePausa(),
      restanteMs: ativo && ultimoValido !== null
        ? Math.max(0, limitePausa() - (agora - ultimoValido)) : null,
      fimSerie: fim };
  }
  return { feed, estado, suspender, pausaVibracao,
    exportarModelo: () => modelo ? copiar(modelo) : null };
}
