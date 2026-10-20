// Detector de repetições por acelerômetro (valores em cm/s²).
// 1) suaviza o sinal; 2) acha a direção em que o pulso mais se move;
// 3) conta um ciclo (subida + descida) com limiar que se adapta ao seu movimento.

export function criarDetector(opcoes) {
  const cfg = {
    deltaMin: 60,        // menor oscilação aceita (menor = mais sensível)
    fatorDelta: 0.35,    // limiar adaptativo = 35% da amplitude média das reps
    intervaloMin: 700,   // ms mínimos entre duas reps
    atrasoInicial: 1200, // ms ignorados ao abrir a tela
    tauSuave: 80,        // ms: suavização do ruído
    tauMedia: 4000,      // ms: referência lenta
    tauCov: 5000,        // ms: memória da direção principal
    ocioReset: 8000,     // ms parado: volta ao limiar mínimo
  };
  if (opcoes) {
    for (const k in opcoes) cfg[k] = opcoes[k];
  }

  let tPrev = null, t0 = 0;
  let sx = 0, sy = 0, sz = 0;
  let mx = 0, my = 0, mz = 0;
  let cxx = 0, cxy = 0, cxz = 0, cyy = 0, cyz = 0, czz = 0;
  let ux = 0.577, uy = 0.577, uz = 0.577;

  let dir = 0, ext = 0, lo = 0, hi = 0, vale = 0, pico = 0;
  let ampMedia = 0, ultimaRep = 0, ultAmp = 0, sAtual = 0;
  let amostras = 0, janelaIni = 0, hz = 0;

  const delta = () => Math.max(cfg.deltaMin, cfg.fatorDelta * ampMedia);

  // chame ao voltar de uma pausa (ex.: fechar a roda de peso)
  function reiniciar(agora) {
    t0 = agora;
    dir = 0;
    lo = sAtual;
    hi = sAtual;
  }

  // retorna true quando uma repetição foi detectada
  function feed(x, y, z, agora) {
    amostras++;
    if (janelaIni === 0) janelaIni = agora;
    if (agora - janelaIni >= 1000) {
      hz = Math.round((amostras * 1000) / (agora - janelaIni));
      amostras = 0;
      janelaIni = agora;
    }

    if (tPrev === null) {
      sx = mx = x; sy = my = y; sz = mz = z;
      tPrev = agora;
      t0 = agora;
      return false;
    }

    let dt = agora - tPrev;
    if (dt <= 0) return false;
    if (dt > 200) dt = 200;
    tPrev = agora;

    // suaviza o ruído
    const a = dt / (cfg.tauSuave + dt);
    sx += (x - sx) * a; sy += (y - sy) * a; sz += (z - sz) * a;

    // referência lenta (tira só a parte parada, sem apagar a inclinação das reps)
    const am = dt / (cfg.tauMedia + dt);
    mx += (sx - mx) * am; my += (sy - my) * am; mz += (sz - mz) * am;
    const dx = sx - mx, dy = sy - my, dz = sz - mz;

    // direção principal do movimento (iteração de potência)
    const ac = dt / (cfg.tauCov + dt);
    cxx += (dx * dx - cxx) * ac; cxy += (dx * dy - cxy) * ac; cxz += (dx * dz - cxz) * ac;
    cyy += (dy * dy - cyy) * ac; cyz += (dy * dz - cyz) * ac; czz += (dz * dz - czz) * ac;

    let nx = cxx * ux + cxy * uy + cxz * uz;
    let ny = cxy * ux + cyy * uy + cyz * uz;
    let nz = cxz * ux + cyz * uy + czz * uz;
    const n = Math.sqrt(nx * nx + ny * ny + nz * nz);
    if (n > 1e-6) {
      ux = nx / n; uy = ny / n; uz = nz / n;
    }

    const s = dx * ux + dy * uy + dz * uz;
    sAtual = s;

    if (agora - t0 < cfg.atrasoInicial) {
      lo = s; hi = s; dir = 0;
      return false;
    }

    if (ampMedia > 0 && agora - ultimaRep > cfg.ocioReset) ampMedia = 0;

    const d = delta();
    let rep = false;

    if (dir === 0) {
      if (s < lo) lo = s;
      if (s > hi) hi = s;
      if (s - lo > d) { dir = 1; ext = s; vale = lo; }
      else if (hi - s > d) { dir = -1; ext = s; pico = hi; }
    } else if (dir === 1) {
      if (s > ext) {
        ext = s;
      } else if (ext - s > d) {
        // pico confirmado: um ciclo completo
        pico = ext;
        const amp = pico - vale;
        ultAmp = amp;
        dir = -1;
        ext = s;
        if (agora - ultimaRep >= cfg.intervaloMin) {
          rep = true;
          ultimaRep = agora;
          ampMedia = ampMedia === 0 ? amp : ampMedia * 0.7 + amp * 0.3;
        }
      }
    } else {
      if (s < ext) {
        ext = s;
      } else if (s - ext > d) {
        vale = ext;
        dir = 1;
        ext = s;
      }
    }
    return rep;
  }

  function info() {
    return {
      hz,
      amp: Math.round(ultAmp),
      delta: Math.round(delta()),
      s: Math.round(sAtual),
    };
  }

  return { feed, reiniciar, info };
}