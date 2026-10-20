import { BaseSideService } from "@zeppos/zml/base-side";

AppSideService(BaseSideService({
  onRequest(req, res) {
    if (
      req.method === "resultado.salvar" ||
      req.method === "fichas.obter"
    ) {
      res(null, {
        erro: "Ponte com o aplicativo Android ainda não configurada",
      });
    } else {
      res(null, {
        erro: "Operação desconhecida",
      });
    }
  },
}));