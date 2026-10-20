import * as sensor from "@zos/sensor";

// Um único vibrador para o app todo
let vib = null;
let ultimoErro = "";

const obter = () => {
  if (!vib) vib = new sensor.Vibrator();
  return vib;
};

// forma C do teste: curta
const curta = () => {
  const v = obter();
  v.stop();
  v.start({ mode: sensor.VIBRATOR_SCENE_DURATION });
};

// forma D do teste: longa (padrão do relógio)
const longa = () => {
  const v = obter();
  v.stop();
  v.start();
};

// "rep"   = a cada repetição contada (curta)
// "serie" = série concluída (longa)
// "fim"   = descanso acabou (longa)
export function vibrar(tipo) {
  try {
    if (tipo === "rep") curta();
    else longa();
    ultimoErro = "";
  } catch (e) {
    ultimoErro = String(e && e.message ? e.message : e).slice(0, 14);
    console.log("ERRO VIBRAR:", ultimoErro);
  }
}

export function erroVibracao() {
  return ultimoErro;
}