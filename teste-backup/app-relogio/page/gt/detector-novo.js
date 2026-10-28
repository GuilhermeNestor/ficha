// Detector de repetições por picos numa janela (acelerômetro em cm/s², gravidade ≈ 981).
// Acha o eixo do movimento a cada 100 ms, marca os picos e só começa a contar quando
// 3 picos seguidos têm ritmo e amplitude parecidos (a subida até a corda não conta sozinha).
// API (igual à do detector antigo): feed, estado, suspender, pausaVibracao, exportarModelo.
// feed(x,y,z,agora) -> quantas reps somar agora (0, 1, ou vários na confirmação do início)

const RAD = 180 / Math.PI;
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const nrm = (a) => Math.sqrt(dot(a, a));
const unit = (a) => { const n = nrm(a); return n > 1e-9 ? [a[0] / n, a[1] / n, a[2] / n] : [0, 0, 1]; };
const angulo = (a, b) => Math.acos(Math.max(-1, Math.min(1, dot(unit(a), unit(b))))) * RAD;
const mediana = (v) => { const s = [...v].sort((a, b) => a - b); const n = s.length; return n ? (n % 2 ? s[(n - 1) >> 1] : (s[n / 2 - 1] + s[n / 2]) / 2) : 0; };

export function criarDetectorAdaptativo(opcoes = {}) {
  const cfg = {
    janela: 10000,
    passaAlta: 900,      // ms (meia-largura) da média que separa o movimento da parte lenta        // ms de histórico usados para eixo e picos
    tauSuave: 70,        // ms
    deltaMin: 50,        // menor oscilação aceita (cm/s²)
    fatorInicial: 0.22,  // sem referência: histerese = 22% da faixa da janela
    fatorDelta: 0.30,    // com referência: histerese = 30% da amplitude típica
    passo: 100,          // ms entre recálculos
    cadeiaMin: 3,        // picos parecidos seguidos para começar a contar
    razaoInt: [0.65, 1.55],
    razaoAmpCadeia: [0.5, 2.0],
    posturaCadeia: 90,
    meioCiclo: 0.55,     // ciclo só conta se vier ≥ 55% do período após o último
    ampRej: [0.30, 3.0],
    posturaRej: 80,
    reaprender: 3,
    ampAbs: 350,          // amplitude mínima (pico a vale, cm/s²) para começar a contar
    lacuna: [1.65, 2.6], // intervalo (em períodos) que indica rep fraca perdida no meio
    primeiroInt: 1.3,     // 1º intervalo > 130% do 2º: era a subida até a corda
    primeiroPostura: 999, // graus
    primeiroFator: 2.5,
    pausaMin: 5000,
    pausaPeriodos: 3.2,
    ...opcoes,
  };

  const buf = [];                // {t, s:[x,y,z]}
  let sp = null, tPrev = null, t0 = null, ultimoCalculo = 0, bloqueadoAte = 0;
  let u = [0.577, 0.577, 0.577];
  let fase = "PREPARANDO", reps = 0, lastCount = 0, ref = null, sig = null;
  const feitos = [];             // tempos de picos já decididos
  let foraSeguidos = 0, atividade = 0;
  const log = [];
  const nota = (t, tipo, extra) => { log.push({ t, tipo, ...extra }); if (log.length > 80) log.shift(); };

  const m0 = opcoes.modelo;
  if (m0 && Array.isArray(m0.ax) && m0.ax.length === 3 && m0.ax.every(Number.isFinite) &&
      Array.isArray(m0.po) && m0.po.length === 3 && m0.po.every(Number.isFinite)) {
    sig = { ax: unit(m0.ax), po: unit(m0.po) };
    u = sig.ax;
  }

  // eixo principal da janela (potência) a partir do sinal sem a parte lenta
  // (tira troca de postura/subida lenta); mantém o sinal por continuidade
  function eixo(ini, fim) {
    const n = fim - ini;
    if (n < 10) return null;
    const m = [0, 0, 0];
    for (let i = ini; i < fim; i++) { const s = buf[i].s; m[0] += s[0]; m[1] += s[1]; m[2] += s[2]; }
    m[0] /= n; m[1] /= n; m[2] /= n;
    const pre = [[0, 0, 0]];
    for (let i = ini; i < fim; i++) { const s = buf[i].s, q = pre[pre.length - 1]; pre.push([q[0] + s[0], q[1] + s[1], q[2] + s[2]]); }
    const c = [0, 0, 0, 0, 0, 0];
    let lo = 0, hi = 0;
    for (let i = 0; i < n; i++) {
      const t = buf[ini + i].t;
      while (buf[ini + lo].t < t - cfg.passaAlta) lo++;
      while (hi < n && buf[ini + hi].t <= t + cfg.passaAlta) hi++;
      const k = hi - lo; if (k < 3) continue;
      const s = buf[ini + i].s;
      const a = s[0] - (pre[hi][0] - pre[lo][0]) / k, b = s[1] - (pre[hi][1] - pre[lo][1]) / k, d = s[2] - (pre[hi][2] - pre[lo][2]) / k;
      c[0] += a * a; c[1] += a * b; c[2] += a * d; c[3] += b * b; c[4] += b * d; c[5] += d * d;
    }
    let v = u;
    for (let k = 0; k < 20; k++) {
      const nx = c[0] * v[0] + c[1] * v[1] + c[2] * v[2];
      const ny = c[1] * v[0] + c[3] * v[1] + c[4] * v[2];
      const nz = c[2] * v[0] + c[4] * v[1] + c[5] * v[2];
      const l = Math.sqrt(nx * nx + ny * ny + nz * nz);
      if (l < 1e-9) break;
      v = [nx / l, ny / l, nz / l];
    }
    if (dot(v, u) < 0) v = [-v[0], -v[1], -v[2]];
    return { v, m };
  }

  // zigue-zague com histerese: devolve extremos confirmados e o pendente
  function zigzag(ts, ps, delta) {
    const out = [];
    let dir = 0, hi = ps[0], hiT = ts[0], lo = ps[0], loT = ts[0];
    for (let i = 1; i < ps.length; i++) {
      const p = ps[i], t = ts[i];
      if (p > hi) { hi = p; hiT = t; }
      if (p < lo) { lo = p; loT = t; }
      if (dir === 0) {
        if (hi - p >= delta) { out.push({ t: hiT, p: hi, k: "P" }); dir = -1; lo = p; loT = t; }
        else if (p - lo >= delta) { out.push({ t: loT, p: lo, k: "V" }); dir = 1; hi = p; hiT = t; }
      } else if (dir === 1) {
        if (hi - p >= delta) { out.push({ t: hiT, p: hi, k: "P" }); dir = -1; lo = p; loT = t; }
      } else if (p - lo >= delta) { out.push({ t: loT, p: lo, k: "V" }); dir = 1; hi = p; hiT = t; }
    }
    const pend = dir === 1 ? { t: hiT, p: hi, k: "P" } : dir === -1 ? { t: loT, p: lo, k: "V" } : null;
    return { out, pend };
  }

  function postura(t, meia = 250) {
    const a = t - meia, b = t + meia; let n = 0; const m = [0, 0, 0];
    for (const x of buf) if (x.t >= a && x.t <= b) { m[0] += x.s[0]; m[1] += x.s[1]; m[2] += x.s[2]; n++; }
    return n ? unit(m) : null;
  }

  const jaFeito = (t, tol) => feitos.some((f) => Math.abs(f - t) < tol);
  const guardarFeito = (t) => { feitos.push(t); if (feitos.length > 80) feitos.shift(); };

  function atualizarRef(T, amp, po) {
    if (!ref) { ref = { T, amp, po }; return; }
    ref.T += (T - ref.T) * 0.3;
    ref.amp += (amp - ref.amp) * 0.25;
    if (po) ref.po = unit([ref.po[0] * 0.7 + po[0] * 0.3, ref.po[1] * 0.7 + po[1] * 0.3, ref.po[2] * 0.7 + po[2] * 0.3]);
  }

  function processar(agora) {
    const ini0 = buf.findIndex((b) => b.t >= agora - cfg.janela);
    if (ini0 < 0) return 0;
    const n = buf.length - ini0;
    if (n < 25 || agora - t0 < 2000) return 0;
    const e = eixo(ini0, buf.length);
    if (!e) return 0;
    u = e.v;
    const ts = [], ps = [];
    let mx = -1e9, mn = 1e9;
    for (let i = ini0; i < buf.length; i++) {
      const s = buf[i].s;
      const p = (s[0] - e.m[0]) * u[0] + (s[1] - e.m[1]) * u[1] + (s[2] - e.m[2]) * u[2];
      ts.push(buf[i].t); ps.push(p);
      if (p > mx) mx = p; if (p < mn) mn = p;
    }
    let ampEst = mx - mn;
    if (!ref) {
      const faixas = [];
      for (let a0 = 0; a0 + 1 < ts.length;) {
        let a1 = a0, lo = ps[a0], hi = ps[a0];
        while (a1 < ts.length && ts[a1] - ts[a0] < 2000) { lo = Math.min(lo, ps[a1]); hi = Math.max(hi, ps[a1]); a1++; }
        if (ts[a1 - 1] - ts[a0] > 1500) faixas.push(hi - lo);
        a0 = a1;
      }
      if (faixas.length) ampEst = mediana(faixas);
    }
    const delta = ref ? Math.max(cfg.deltaMin, cfg.fatorDelta * ref.amp) : Math.max(cfg.deltaMin, cfg.fatorInicial * ampEst);
    const z = zigzag(ts, ps, delta);
    const ex = z.out.slice();
    if (z.pend) ex.push({ ...z.pend, pend: true });

    // picos confirmados com amplitude (pico - média dos vales vizinhos)
    const picos = [];
    const inicioJanela = ts[0];
    for (let i = 0; i < ex.length; i++) {
      const x = ex[i];
      if (x.k !== "P" || x.pend) continue;
      if (inicioJanela > t0 + 100 && x.t < inicioJanela + 200) continue; // extremo colado na borda
      const vs = [];
      if (i > 0 && ex[i - 1].k === "V") vs.push(ex[i - 1].p);
      if (i + 1 < ex.length && ex[i + 1].k === "V") vs.push(ex[i + 1].p);
      if (!vs.length) continue;
      picos.push({ t: x.t, amp: x.p - vs.reduce((a, b) => a + b, 0) / vs.length });
    }
    if (!picos.length) return 0;

    if (fase === "CONTANDO") return contando(agora, picos);
    return preparando(agora, picos);
  }

  function preparando(agora, picos) {
    if (!picos.some((p) => !jaFeito(p.t, 300))) return 0;
    // cadeia de picos parecidos terminando no último pico
    let j = picos.length - 1;
    while (j > 0) {
      const i1 = picos[j].t - picos[j - 1].t;
      if (i1 < 500 || i1 > 4500) break;
      const ra = picos[j].amp / picos[j - 1].amp;
      if (ra < cfg.razaoAmpCadeia[0] || ra > cfg.razaoAmpCadeia[1]) break;
      if (j < picos.length - 1) {
        const i2 = picos[j + 1].t - picos[j].t, r = i1 / i2;
        if (r < cfg.razaoInt[0] || r > cfg.razaoInt[1]) break;
      }
      j--;
    }
    let cad = picos.slice(j);
    if (cad.length < cfg.cadeiaMin) return 0;
    // tira do começo os picos com postura muito diferente dos últimos (subida até a corda)
    const posDe = (p) => postura(p.t) || null;
    for (;;) {
      if (cad.length < cfg.cadeiaMin) { nota(agora, "cadeia-postura", {}); return 0; }
      const fim3 = cad.slice(-3).map(posDe).filter(Boolean);
      const poF = unit(fim3.reduce((a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]], [0, 0, 0]));
      const p0 = posDe(cad[0]);
      if (p0 && angulo(p0, poF) > cfg.posturaCadeia) cad = cad.slice(1); else break;
    }
    const ints = []; for (let i = 1; i < cad.length; i++) ints.push(cad[i].t - cad[i - 1].t);
    const T = mediana(ints), amp = mediana(cad.map((p) => p.amp));
    if (amp < cfg.ampAbs) { nota(agora, "cadeia-fraca", { amp: Math.round(amp) }); return 0; }
    const pos = cad.map(posDe).filter(Boolean);
    const po = unit(pos.reduce((a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]], [0, 0, 0]));
    // 1º pico costuma ser a subida até a corda: descarta se destoa dos seguintes
    let descartado = null;
    if (cad.length >= 3 && !jaFeito(cad[0].t, 300)) {
      const i1 = cad[1].t - cad[0].t, i2 = cad[2].t - cad[1].t;
      const refPo = unit(cad.slice(1, 4).map((p) => postura(p.t, 100) || po).reduce((a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]], [0, 0, 0]));
      const dev0 = angulo(postura(cad[0].t, 100) || po, refPo);
      const devs = cad.slice(1, 4).map((p) => angulo(postura(p.t, 100) || po, refPo));
      if (i1 > cfg.primeiroInt * i2) descartado = "intervalo " + (i1 / i2).toFixed(2);
      else if (dev0 > cfg.primeiroPostura && dev0 > cfg.primeiroFator * Math.max(2, mediana(devs))) descartado = "postura " + Math.round(dev0);
    }
    let novos = 0;
    for (const p of cad) {
      if (jaFeito(p.t, 300)) continue;
      guardarFeito(p.t);
      if (descartado && p === cad[0]) { nota(p.t, "descarta-1o", { mot: descartado }); continue; }
      novos++;
    }
    if (!novos) return 0;
    reps += novos; lastCount = cad[cad.length - 1].t; atividade = agora; fase = "CONTANDO"; foraSeguidos = 0;
    ref = { T, amp, po };
    nota(agora, "confirma", { novos, reps, T: Math.round(T), amp: Math.round(amp), picos: cad.map((p) => p.t - t0), amps: cad.map((p) => Math.round(p.amp)), ang: pos.map((q) => Math.round(angulo(q, po))) });
    return novos;
  }

  function contando(agora, picos) {
    let out = 0;
    for (const p of picos) {
      if (jaFeito(p.t, 0.4 * ref.T)) continue;
      const dt = p.t - lastCount;
      if (dt < 0) { guardarFeito(p.t); continue; }
      if (dt > Math.max(cfg.pausaMin, cfg.pausaPeriodos * ref.T)) {
        fase = "PREPARANDO"; ref = null; nota(agora, "retoma-pausa", {});
        return out + preparando(agora, picos);
      }
      guardarFeito(p.t);
      if (dt < cfg.meioCiclo * ref.T) { nota(p.t, "meio-ciclo", { dt: Math.round(dt) }); continue; }
      const ra = p.amp / ref.amp;
      if (ra < cfg.ampRej[0] || ra > cfg.ampRej[1]) { nota(p.t, "descarta", { mot: "amp " + ra.toFixed(2) }); continue; }
      const q = postura(p.t);
      const ang = q ? angulo(q, ref.po) : 0;
      if (ang > cfg.posturaRej) {
        nota(p.t, "descarta", { mot: "postura " + Math.round(ang) });
        if (++foraSeguidos >= cfg.reaprender) { fase = "PREPARANDO"; ref = null; foraSeguidos = 0; nota(agora, "reaprende", {}); return out; }
        continue;
      }
      foraSeguidos = 0;
      // rep fraca que não passou da histerese: intervalo ≈ 2 períodos entre dois picos válidos
      const razao = dt / ref.T;
      if (razao >= cfg.lacuna[0] && razao <= cfg.lacuna[1]) {
        const falta = Math.min(2, Math.round(razao) - 1);
        reps += falta; out += falta;
        nota(p.t, "preenche-lacuna", { falta, razao: +razao.toFixed(2) });
      }
      reps++; out++;
      atualizarRef(Math.min(dt, 2 * ref.T), p.amp, q);
      lastCount = p.t; atividade = agora;
      nota(p.t, "conta", { reps, dt: Math.round(dt), amp: Math.round(p.amp) });
    }
    return out;
  }

  function feed(x, y, z, agora) {
    if (tPrev === null) { sp = [x, y, z]; tPrev = agora; t0 = agora; lastCount = agora; atividade = agora; return 0; }
    let dt = agora - tPrev;
    if (dt <= 0) return 0;
    if (dt > 250) dt = 250;
    tPrev = agora;
    const a = dt / (cfg.tauSuave + dt);
    sp = [sp[0] + (x - sp[0]) * a, sp[1] + (y - sp[1]) * a, sp[2] + (z - sp[2]) * a];
    if (agora < bloqueadoAte) return 0;
    buf.push({ t: agora, s: sp });
    while (buf.length && buf[0].t < agora - cfg.janela - 500) buf.shift();
    if (agora - ultimoCalculo < cfg.passo) return 0;
    ultimoCalculo = agora;
    return processar(agora);
  }

  const limite = () => Math.max(cfg.pausaMin, cfg.pausaPeriodos * (ref ? ref.T : 1300));

  // Limpa o que já foi lido (ex.: depois de mexer no peso), mantendo só a assinatura.
  function suspender(agora, duracao = 0) {
    buf.length = 0; feitos.length = 0;
    sp = null; tPrev = null; t0 = null; ultimoCalculo = 0;
    fase = "PREPARANDO"; ref = null; foraSeguidos = 0; reps = 0;
    bloqueadoAte = agora + duracao; atividade = agora;
  }

  return {
    feed,
    suspender,
    pausaVibracao(agora) { bloqueadoAte = agora + 450; atividade = agora + 450; },
    estado(agora) {
      const restante = fase === "CONTANDO" ? Math.max(0, limite() - (agora - atividade)) : null;
      return {
        aprendeu: fase === "CONTANDO",
        fase: fase === "CONTANDO" ? (restante === 0 ? "fim" : "serie") : "preparando",
        amostrasModelo: 0,
        restanteMs: restante,
        pausaMs: limite(),
        fimSerie: fase === "CONTANDO" && restante === 0,
      };
    },
    exportarModelo() {
      if (!ref || reps < 3) return null;
      return { T: ref.T, amp: ref.amp, ax: [u[0], u[1], u[2]], po: [ref.po[0], ref.po[1], ref.po[2]] };
    },
    log,
  };
}