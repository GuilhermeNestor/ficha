import { criarDetector } from "./detector.js";

const MIN_REPS_APRENDER = 3;
const AMOSTRA_MS = 40;
// Janela usada para decidir se o movimento é lateral. Com 700 ms ela pegava
// só um pedaço da repetição e rejeitava reps verdadeiras (tremor, movimento sutil).
const JANELA_LATERAL_MS = 1500;

// Quanto da variação precisa se concentrar em uma direção
// para que ela possa ser aprendida.
const MIN_CONCENTRACAO = 0.70;

// Semelhança entre as direções dos ciclos de aprendizado.
const MIN_ALINHAMENTO = 0.90;

// Depois de aprender, pelo menos 60% da variação precisa
// acompanhar a direção do exercício.
const MIN_FRACAO_DIRECAO = 0.60;

const copiar = (valor) =>
  JSON.parse(JSON.stringify(valor));

const produto = (a, b) =>
  a.reduce(
    (soma, valor, i) => soma + valor * b[i],
    0
  );

const norma = (vetor) =>
  Math.sqrt(produto(vetor, vetor));

const mediana = (lista) =>
  lista
    .slice()
    .sort((a, b) => a - b)[
      Math.floor(lista.length / 2)
    ];

function lerModelo(modelo) {
  if (
    !modelo ||
    modelo.versao !== 2 ||
    !Array.isArray(modelo.direcao) ||
    modelo.direcao.length !== 3 ||
    !modelo.direcao.every(Number.isFinite) ||
    !Number.isFinite(modelo.duracao) ||
    modelo.duracao < 700 ||
    modelo.duracao > 8000
  ) {
    return null;
  }

  const tamanho = norma(modelo.direcao);

  if (tamanho < 0.9 || tamanho > 1.1) {
    return null;
  }

  return {
    versao: 2,

    direcao: modelo.direcao.map(
      (valor) => valor / tamanho
    ),

    duracao: modelo.duracao,
  };
}

// Mede como os três eixos variam juntos.
// A média da janela é retirada antes do cálculo.
function covariancia(amostras) {
  if (amostras.length < 6) return null;

  const media = [0, 1, 2].map(
    (eixo) =>
      amostras.reduce(
        (soma, amostra) =>
          soma + amostra.v[eixo],
        0
      ) / amostras.length
  );

  const matriz = [
    [0, 0, 0],
    [0, 0, 0],
    [0, 0, 0],
  ];

  amostras.forEach((amostra) => {
    const diferenca = amostra.v.map(
      (valor, eixo) => valor - media[eixo]
    );

    for (let i = 0; i < 3; i++) {
      for (let j = 0; j < 3; j++) {
        matriz[i][j] +=
          (diferenca[i] * diferenca[j]) /
          amostras.length;
      }
    }
  });

  return matriz;
}

const aplicar = (matriz, vetor) =>
  matriz.map(
    (linha) => produto(linha, vetor)
  );

const energia = (matriz) =>
  matriz[0][0] +
  matriz[1][1] +
  matriz[2][2];

// Encontra a direção predominante de um ciclo.
function analisarCiclo(amostras) {
  if (amostras.length < 12) return null;

  const duracao =
    amostras[amostras.length - 1].t -
    amostras[0].t;

  if (duracao < 700 || duracao > 8000) {
    return null;
  }

  const matriz = covariancia(amostras);
  const total = energia(matriz);

  if (total < 900) return null;

  // Começa no eixo com maior variação.
  let eixo = 0;

  for (let i = 1; i < 3; i++) {
    if (matriz[i][i] > matriz[eixo][eixo]) {
      eixo = i;
    }
  }

  let direcao = [0, 0, 0];
  direcao[eixo] = 1;

  // Estima a componente principal da variação.
  for (let i = 0; i < 10; i++) {
    const proxima = aplicar(matriz, direcao);
    const tamanho = norma(proxima);

    if (tamanho < 0.0001) return null;

    direcao = proxima.map(
      (valor) => valor / tamanho
    );
  }

  const concentracao =
    produto(
      direcao,
      aplicar(matriz, direcao)
    ) / total;

  if (concentracao < MIN_CONCENTRACAO) {
    return null;
  }

  return {
    direcao,
    duracao,
  };
}

export function criarDetectorAdaptativo(opcoes = {}) {
  let modelo = lerModelo(opcoes.modelo);

  let detectorLivre;
  let detectorEixo;
  let suave;
  let anterior;
  let inicio;

  let janela;
  let ciclo;
  let candidatos;

  let ultimaColeta;
  let ultimoValido;

  let ativo;
  let fim;
  let lateral;
  let fracao;
  let ciclosValidos;

  let bloqueadoAte = 0;

  const novoLivre = () =>
    criarDetector({
      deltaMin: 60,
      fatorDelta: 0.35,
      intervaloMin: 700,
      atrasoInicial: 1200,
    });

  const novoEixo = () =>
    criarDetector({
      deltaMin: 60,
      fatorDelta: 0.35,
      intervaloMin: 700,
      atrasoInicial: 300,
    });

  function reiniciar() {
    detectorLivre = novoLivre();
    detectorEixo = novoEixo();

    suave = null;
    anterior = null;
    inicio = null;

    janela = [];
    ciclo = [];
    candidatos = [];

    ultimaColeta = null;
    ultimoValido = null;

    ativo = false;
    fim = false;
    lateral = false;
    fracao = 1;
    ciclosValidos = 0;
  }

  reiniciar();

  // Dá mais tempo para exercícios com repetições lentas.
  // O intervalo fica entre 5 e 18 segundos.
  const limitePausa = () =>
    Math.max(
      5000,
      Math.min(
        18000,
        modelo
          ? modelo.duracao * 2 + 1500
          : 5000
      )
    );

  function aprender(amostras) {
    const candidato = analisarCiclo(amostras);

    if (!candidato) {
      candidatos = [];
      return;
    }

    const diferente = candidatos.some((outro) => {
      const alinhamento = Math.abs(
        produto(
          outro.direcao,
          candidato.direcao
        )
      );

      const proporcaoTempo =
        candidato.duracao / outro.duracao;

      return (
        alinhamento < MIN_ALINHAMENTO ||
        proporcaoTempo < 0.5 ||
        proporcaoTempo > 2
      );
    });

    if (diferente) {
      candidatos = [];
    }

    candidatos.push(candidato);

    if (candidatos.length < MIN_REPS_APRENDER) {
      return;
    }

    const referencia = candidatos[0].direcao;
    const soma = [0, 0, 0];

    candidatos.forEach((item) => {
      // Uma direção e sua inversa representam o mesmo eixo.
      const sinal =
        produto(item.direcao, referencia) < 0
          ? -1
          : 1;

      item.direcao.forEach((valor, eixo) => {
        soma[eixo] += valor * sinal;
      });
    });

    const tamanho = norma(soma);

    // direções que se anulam não formam um eixo confiável
    if (tamanho < 0.0001) {
      candidatos = [];
      return;
    }

    modelo = {
      versao: 2,

      direcao: soma.map(
        (valor) => valor / tamanho
      ),

      duracao: mediana(
        candidatos.map(
          (item) => item.duracao
        )
      ),
    };

    // A direção aprendida não acompanha movimentos laterais.
    detectorEixo = novoEixo();
    candidatos = [];
  }

  function feed(x, y, z, agora) {
    if (
      ![x, y, z, agora].every(Number.isFinite) ||
      fim ||
      agora < bloqueadoAte
    ) {
      return 0;
    }

    if (
      anterior !== null &&
      agora <= anterior
    ) {
      return 0;
    }

    // Interrupção das leituras não é uma pausa comprovada.
    if (
      anterior !== null &&
      agora - anterior > 1000
    ) {
      reiniciar();
    }

    const dt =
      anterior === null
        ? 40
        : agora - anterior;

    anterior = agora;

    if (inicio === null) {
      inicio = agora;
    }

    if (!suave) {
      suave = [x, y, z];
    }

    const alfa = dt / (80 + dt);

    [x, y, z].forEach((valor, eixo) => {
      suave[eixo] +=
        (valor - suave[eixo]) * alfa;
    });

    if (
      ultimaColeta === null ||
      agora - ultimaColeta >= AMOSTRA_MS
    ) {
      const amostra = {
        t: agora,
        v: suave.slice(),
      };

      janela.push(amostra);
      ciclo.push(amostra);
      ultimaColeta = agora;

      while (
        janela.length &&
        agora - janela[0].t > JANELA_LATERAL_MS
      ) {
        janela.shift();
      }

      // Limita o tamanho dos dados de aprendizado.
      if (
        ciclo.length &&
        agora - ciclo[0].t > 10000
      ) {
        ciclo = [amostra];
        candidatos = [];
      }

      lateral = false;
      fracao = 1;

      if (modelo && janela.length >= 6) {
        const matriz = covariancia(janela);
        const total = energia(matriz);

        // Em repouso, o ruído não deve decidir a direção.
        if (total >= 400) {
          const energiaNaDirecao = produto(
            modelo.direcao,
            aplicar(
              matriz,
              modelo.direcao
            )
          );

          fracao = Math.max(
            0,
            Math.min(
              1,
              energiaNaDirecao / total
            )
          );

          lateral =
            fracao < MIN_FRACAO_DIRECAO;
        }
      }
    }

    let repeticao = false;

    if (!modelo) {
      // Conta normalmente enquanto aprende.
      repeticao = detectorLivre.feed(
        x,
        y,
        z,
        agora
      );

      if (repeticao) {
        aprender(ciclo);
      }
    } else {
      // Usa apenas a parte do sinal na direção aprendida.
      const projecao = produto(
        [x, y, z],
        modelo.direcao
      );

      const detectou = detectorEixo.feed(
        projecao,
        0,
        0,
        agora
      );

      if (
        lateral ||
        agora - inicio < 1200
      ) {
        // Descarta o ciclo lateral.
        // Não atualiza ultimoValido.
        detectorEixo.reiniciar(agora);
      } else {
        repeticao = detectou;
      }
    }

    if (repeticao) {
      ativo = true;
      ultimoValido = agora;
      ciclosValidos++;

      ciclo = [{
        t: agora,
        v: suave.slice(),
      }];
    }

    if (
      ativo &&
      ultimoValido !== null &&
      agora - ultimoValido >= limitePausa()
    ) {
      fim = true;
    }

    return repeticao ? 1 : 0;
  }

  function suspender(agora, duracao = 0) {
    // Mantém a direção, mas limpa os ciclos incompletos.
    reiniciar();
    bloqueadoAte = agora + duracao;
  }

  function pausaVibracao(agora) {
    // Só ignora as leituras durante a vibração. Não recria os detectores
    // (isso zerava a janela lateral e cegava o detector por ~1,6 s).
    bloqueadoAte = agora + 450;
    anterior = null;
    if (ativo) ultimoValido = bloqueadoAte;
  }

  function estado(agora) {
    return {
      aprendeu: !!modelo,

      fase: fim
        ? "fim"
        : modelo
          ? "serie"
          : "aprendendo",

      amostrasModelo: modelo
        ? MIN_REPS_APRENDER
        : candidatos.length,

      lateral,
      fracaoNaDirecao: fracao,

      direcao: modelo
        ? modelo.direcao.slice()
        : null,

      pausaMs: limitePausa(),

      restanteMs:
        ativo && ultimoValido !== null
          ? Math.max(
              0,
              limitePausa() -
                (agora - ultimoValido)
            )
          : null,

      fimSerie: fim,
    };
  }

  return {
    feed,
    estado,
    suspender,
    pausaVibracao,

    exportarModelo: () =>
      modelo ? copiar(modelo) : null,
  };
}