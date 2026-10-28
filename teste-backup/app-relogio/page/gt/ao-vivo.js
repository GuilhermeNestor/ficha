// Compara, série a série, o que CADA detector contou AO VIVO no relógio (gravado no JSON).
//   node ao-vivo.js gravacoes_treino_XXXX.json [outro.json ...]
import { readFileSync } from "node:fs";
import { contarEventos } from "./multi-detectores.js";
const NOMES = ["picos", "adaptativo", "livre", "vetorial", "vetorial+molde"];
const tot = Object.fromEntries(NOMES.map((n) => [n, { ok: 0, n: 0, erro: 0, falsas: 0 }]));
const cpu = Object.fromEntries(NOMES.map((n) => [n, { ms: 0, chamadas: 0, max: 0, erros: 0 }]));
const vistos = new Set(); let series = 0;
console.log("série".padEnd(30), "reais", NOMES.map((n) => n.slice(0, 8).padEnd(9)).join(""));
for (const f of process.argv.slice(2)) for (const g of JSON.parse(readFileSync(f, "utf8")).gravacoes.sort((a, b) => a.inicio - b.inicio)) {
  if (vistos.has(g.id || g.inicio)) continue; vistos.add(g.id || g.inicio);
  const reais = g.rotulos?.repsReais ?? g.repsReais; if (reais == null) continue;
  const por = g.repsPorDetector || contarEventos(g.eventos || [], g.fimManualMs);
  if (!g.repsPorDetector && !(g.eventos || []).some((e) => e.tipo === "rep_outro")) { /* gravação do detector único: só o principal */ }
  series++;
  const cel = (n) => { const c = por[n]; if (!c) return "-".padEnd(9); const v = c.serie; const t = tot[n]; t.n++; t.erro += Math.abs(v - reais); if (v === reais) t.ok++; if (reais === 0) t.falsas += v; return (String(v) + (c.apos ? `(+${c.apos})` : "") + (v === reais ? "✓" : "")).padEnd(9); };
  console.log(String(g.exercicioNome).slice(0, 29).padEnd(30), String(reais).padEnd(5), NOMES.map(cel).join(""));
  for (const n of NOMES) { const c = g.cpu && g.cpu[n]; if (c) { cpu[n].ms += c.ms; cpu[n].chamadas += c.n; cpu[n].max = Math.max(cpu[n].max, c.max); cpu[n].erros += c.erros; } }
}
console.log("\nRESUMO (ao vivo no relógio)");
for (const n of NOMES) { const t = tot[n]; if (t.n) console.log(n.padEnd(16), `${t.ok}/${t.n} exatas`.padEnd(14), `erro médio ${(t.erro / t.n).toFixed(2)}`.padEnd(18), `reps falsas em séries de 0: ${t.falsas}`); }
console.log("\nCUSTO NO RELÓGIO (soma de todas as séries)");
for (const n of NOMES) { const c = cpu[n]; if (c.chamadas) console.log(n.padEnd(16), `média ${(c.ms / c.chamadas).toFixed(2)} ms por leitura`.padEnd(28), `pior chamada ${c.max} ms`.padEnd(22), c.erros ? `erros: ${c.erros}` : ""); }