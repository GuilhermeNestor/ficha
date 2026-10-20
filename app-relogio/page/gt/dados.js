export const treinos = [
  {
    id: "peito",
    nome: "PEITO",
    exercicios: [
      { nome: "SUPINO RETO",      series: 4, reps: 10, carga: 20, descanso: 60 },
      { nome: "SUPINO INCLINADO", series: 3, reps: 10, carga: 16, descanso: 60 },
      { nome: "TRÍCEPS CORDA",    series: 3, reps: 10, carga: 25, descanso: 45 },
    ],
  },
  {
    id: "costas",
    nome: "COSTAS",
    exercicios: [
      { nome: "PUXADA FRENTE",   series: 4, reps: 10, carga: 40, descanso: 60 },
      { nome: "REMADA CURVADA",  series: 3, reps: 12, carga: 30, descanso: 60 },
      { nome: "ROSCA DIRETA",    series: 3, reps: 12, carga: 12, descanso: 45 },
    ],
  },
  {
    id: "perna",
    nome: "PERNA",
    exercicios: [
      { nome: "AGACHAMENTO",       series: 4, reps: 10, carga: 40,  descanso: 90 },
      { nome: "LEG PRESS",         series: 4, reps: 12, carga: 100, descanso: 90 },
      { nome: "CADEIRA EXTENSORA", series: 3, reps: 12, carga: 35,  descanso: 60 },
    ],
  },
];

// Texto de resumo mostrado na home: "3 exercícios · 24 min"
export function infoTreino(t) {
  const n = t.exercicios.length;
  const segundos = t.exercicios.reduce(
    (soma, e) => soma + e.series * (45 + e.descanso),
    0
  );
  return `${n} exercícios · ${Math.round(segundos / 60)} min`;
}