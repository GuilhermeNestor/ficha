import { BaseSideService } from "@zeppos/zml/base-side";

// Deve ser igual ao token em lib/ponte.dart desta instalação.
const TOKEN = "ficha_9a7e2b46d8104f5b8196e032a67c43fd";

AppSideService(BaseSideService({
  onRequest(req, res) {
    if (req.method !== "resultado.salvar" && req.method !== "fichas.obter") {
      res(null, { erro: "Operação desconhecida" });
      return;
    }
    let respondeu = false;
    let timer;
    const responder = (dados) => {
      if (respondeu) return;
      respondeu = true;
      clearTimeout(timer);
      res(null, dados);
    };
    timer = setTimeout(() => responder({
      erro: "Sem resposta. Abra Ficha de Treino no celular e tente novamente.",
    }), 12000);

    const encaminhar = async () => {
      try {
        const requestId = `${Date.now()}_${Math.random().toString(16).slice(2)}`;
        const resposta = await fetch({
          url: "http://127.0.0.1:8765/rpc",
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Ficha-Token": TOKEN,
          },
          body: JSON.stringify({
            versao: 1, requestId, method: req.method, params: req.params,
          }),
        });
        const envelope = typeof resposta.body === "string"
          ? JSON.parse(resposta.body) : resposta.body;
        if (!envelope || envelope.app !== "ficha-treino" ||
            envelope.requestId !== requestId || !envelope.dados) {
          throw new Error("Resposta inválida. Confira a versão do app celular.");
        }
        const dados = envelope.dados;
        if (dados.erro) throw new Error(dados.erro);
        if (dados.versao !== 1) throw new Error("Protocolo incompatível.");
        if (req.method === "resultado.salvar" &&
            (dados.persistido !== true || !req.params ||
             !req.params.resultado ||
             dados.resultadoId !== req.params.resultado.id)) {
          throw new Error("Confirmação do resultado inválida.");
        }
        if (req.method === "fichas.obter" && !dados.pacote) {
          throw new Error("Pacote de fichas ausente.");
        }
        responder(dados);
      } catch (erro) {
        console.log("Sincronização:", String(erro));
        responder({ erro: erro.message || String(erro) });
      }
    };
    encaminhar();
  },
}));
