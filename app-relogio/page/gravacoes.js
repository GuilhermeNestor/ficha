import { LocalStorage } from '@zos/storage';
import { ler, gravar } from './armazenamento.js';

export const TESTE = true;
export const MAX_AMOSTRAS = 6000;
export const MAX_DURACAO = 90000;
export const VAGAS = 8;   // cada série gravada ocupa uma vaga até sincronizar
// Uma gravação por arquivo: os sinais não entram no arquivo da sessão.
function arquivo(slot) { return new LocalStorage(`coleta_v2_${slot}.json`); }
const chave = (slot, parte) => `coleta_v1_${slot}_${parte}`;

// Integridade do transporte (não é assinatura de segurança).
export function checksum(texto) {
  let h = 2166136261;
  for (let i = 0; i < texto.length; i++) {
    h ^= texto.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return h.toString(16).padStart(8, '0');
}
export function listarGravacoes() {
  const lista = [];
  for (let slot = 0; slot < VAGAS; slot++) {
    const meta = ler(chave(slot, 'meta'), null);
    if (meta) lista.push({slot, ...meta});
  }
  return lista;
}
export function salvarGravacao(g) {
  const lista = listarGravacoes();
  const existente = lista.find(m => m.id === g.id);
  if (existente) return;
  const slot = Array.from({length: VAGAS}, (_, i) => i).find(s => !lista.some(m => m.slot === s));
  if (slot === undefined) throw new Error(`Sincronize as ${VAGAS} gravações antes de gravar outra.`);
  if (!Array.isArray(g.amostras) || !g.amostras.length) throw new Error('Gravação sem leituras.');
  const dados = arquivo(slot), texto = JSON.stringify(g);
  dados.setItem('registro', texto);
  if (dados.getItem('registro') !== texto) throw new Error('Falha ao salvar gravação.');
  const {amostras, ...meta} = g;
  // O índice só é publicado depois do conteúdo. Repetir após falha é seguro.
  gravar(chave(slot, 'meta'), {...meta, arquivo: true, partes: 0, quantidade: amostras.length});
}
export function carregarGravacao(slot) {
  const meta = ler(chave(slot, 'meta'), null);
  if (!meta) throw new Error('Gravação ausente.');
  if (meta.arquivo === true) {
    const bruto = arquivo(slot).getItem('registro');
    if (typeof bruto !== 'string') throw new Error('Gravação ausente; índice preservado.');
    const g = JSON.parse(bruto);
    if (g.id !== meta.id || !Array.isArray(g.amostras) || g.amostras.length !== meta.quantidade)
      throw new Error('Gravação inválida; dados preservados.');
    return g;
  }
  // Compatibilidade com as coletas já salvas em blocos pela versão anterior.
  const amostras = [];
  for (let i = 0; i < meta.partes; i++) {
    const parte = ler(chave(slot, i), null);
    if (!Array.isArray(parte)) throw new Error('Gravação incompleta; dados preservados.');
    amostras.push(...parte);
  }
  if (amostras.length !== meta.quantidade) throw new Error('Quantidade de amostras inválida.');
  const {partes, quantidade, ...g} = meta;
  return {...g, amostras};
}
export async function enviarGravacoes(pedir, mostrar, ativo = () => true) {
  for (const meta of listarGravacoes()) {
    const g = carregarGravacao(meta.slot);
    const texto = JSON.stringify(g), hash = checksum(texto);
    const total = Math.ceil(texto.length / 1024);
    let confirmado = false;
    for (let indice = 0; indice < total; indice++) {
      if (!ativo()) return;
      mostrar(`GRAVAÇÕES\n${g.exercicioNome}\nBloco ${indice + 1}/${total}`);
      const ack = await pedir({method: 'gravacao.parte', params: {
        versao: 1, id: g.id, hash, total, indice, tamanho: texto.length,
        conteudo: texto.slice(indice * 1024, (indice + 1) * 1024),
      }});
      if (!ack || ack.versao !== 1 || ack.id !== g.id || ack.hash !== hash || ack.indice !== indice)
        throw new Error('Confirmação da gravação inválida.');
      if (ack.completa === true && ack.persistido === true) { confirmado = true; break; }
    }
    if (!confirmado) throw new Error('Gravação ainda não confirmada no celular.');
    // Libera a vaga só após a confirmação persistente do celular.
    gravar(chave(meta.slot, 'meta'), null);
    if (meta.arquivo === true) arquivo(meta.slot).removeItem('registro');
    else for (let i = 0; i < meta.partes; i++) gravar(chave(meta.slot, i), null);
  }
}