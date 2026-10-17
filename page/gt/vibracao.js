import * as sensor from "@zos/sensor";

// Um único vibrador para o app todo (evita ser descartado ao trocar de tela)
let vib = null;
let ultimoErro = "";

// Cenas mais longas que os 20 ms antigos, para dar para sentir no pulso
const CENAS = {
  rep: sensor.VIBRATOR_SCENE_SHORT_STRONG,       // toque curto a cada repetição
  serie: sensor.VIBRATOR_SCENE_STRONG_REMINDER,  // 4 pulsos: série concluída
  fim: sensor.VIBRATOR_SCENE_DURATION,           // 600 ms: descanso acabou
};

export function vibrar(tipo) {
  try {
    const cena = CENAS[tipo];
    if (cena === undefined) {
      ultimoErro = "cena?";
      return;
    }
    if (!vib) vib = new sensor.Vibrator();
    vib.stop();
    vib.setMode({ mode: cena });
    vib.start();
    ultimoErro = "";
  } catch (e) {
    ultimoErro = String(e && e.message ? e.message : e).slice(0, 14);
    console.log("ERRO VIBRAR:", ultimoErro);
  }
}

export function erroVibracao() {
  return ultimoErro;
}