"""
conductor_serial.py - Lee por USB serial lo que el ESP32 imprime en cada ciclo del bus.

El firmware (Nodo_Final_PME.ino, monitor serie a 115200) imprime UNA linea por ciclo:

    ID1: 0 0 | ID2: 267 432 1007 | ID6: 461 370 | ID5: 382 411 | ... | ID16: 0 0

con los registros CRUDOS de cada sensor. Si un sensor falla, en lugar de numeros
imprime un texto ("sin respuesta", "sin trama valida", "CRC mal", "otro ID",
"excepcion"). Ese texto se convierte en null (= el sensor no respondio).

Tambien acepta lineas JSON del protocolo v1, por si el firmware cambia:
    {"v":1,"tipo":"datos","ids":{"2":[267,432,1007],"4":null}}

Lo demas que imprime el ESP32 (arranque, "Guardado en ...", "Evento: ...", los
mensajes de depuracion "[ID6] 5 bytes sin trama valida: ...") se ignora.

Uso: lo carga puente_datos.py (ver aplicar_serial.py). Es independiente del puente:
solo necesita un objeto con publicar(ids), en_linea(conductor) y fallo(texto).
"""
import json
import re
import threading
import time

SEGMENTO = re.compile(r"ID(\d+):\s*([^|]*)")
ENTERO = re.compile(r"-?\d+")
MIN_IDS = 3                 # un ciclo con menos sensores se descarta (linea cortada)
ESPERA_INICIAL_S = 60.0     # Le da 1 minuto al ESP32 para su primer ciclo sin alarmar
SIN_DATOS_S = 90.0          # Tolera ciclos espaciados


class LectorCiclos:
    """Va recibiendo lineas de texto y devuelve los ciclos completos como
    {"2": [r1, r2, r3], "6": [r1, r2], "9": None, ...}."""

    def __init__(self):
        self.actual = {}

    def alimentar(self, linea):
        salida = []
        l = linea.strip()
        if not l:
            return salida

        if l.startswith("{"):                              # JSON v1
            try:
                m = json.loads(l)
            except ValueError:
                return salida
            if isinstance(m, dict) and m.get("tipo") == "datos" and isinstance(m.get("ids"), dict):
                salida.append({str(k): (list(v) if isinstance(v, list) else None)
                               for k, v in m["ids"].items()})
            return salida

        if l.startswith("["):                              # depuracion: "[ID6] 5 bytes ..."
            return salida

        hubo = False
        for m in SEGMENTO.finditer(l):
            hubo = True
            id_ = m.group(1)
            fichas = m.group(2).split()
            regs = None
            if fichas and all(ENTERO.fullmatch(f) for f in fichas):
                regs = [int(f) for f in fichas]
                if any(not -32768 <= v <= 65535 for v in regs):
                    regs = None                             # basura del puerto
            if id_ in self.actual:                          # empezo un ciclo nuevo sin cerrar el anterior
                salida.append(self.actual)
                self.actual = {}
            self.actual[id_] = regs
        # el firmware cierra el ciclo con "\n" (sin " | " al final)
        if hubo and not l.endswith("|"):
            salida.append(self.actual)
            self.actual = {}
        return salida


class ConductorSerial(threading.Thread):
    nombre = "serial"

    def __init__(self, puente, params, abrir=None):
        super().__init__(daemon=True)
        self.puente = puente
        self.params = params or {}
        self.parar = threading.Event()
        self.puerto = str(self.params.get("puerto", ""))
        self.baudios = int(self.params.get("baudios", 115200))
        self.detalle = f"{self.puerto} · {self.baudios}"
        self._abrir = abrir or self._abrir_pyserial

    def detener(self):
        self.parar.set()

    def _abrir_pyserial(self):
        try:
            import serial
        except ImportError:
            raise RuntimeError("falta pyserial: ejecuta  pip install pyserial")
        s = serial.Serial()
        s.port = self.puerto
        s.baudrate = self.baudios
        s.timeout = 0.5
        # Muchas placas ESP32 se reinician cuando DTR/RTS cambian al abrir el puerto.
        # Se dejan en bajo ANTES de abrir para intentar evitarlo.
        s.dtr = False
        s.rts = False
        s.open()
        return s

    def run(self):
        try:
            ser = self._abrir()
        except Exception as e:
            self.puente.fallo(f"No pude abrir {self.puerto}: {e}")
            return

        lector = LectorCiclos()
        t_inicio = time.time()
        t_ultimo = None
        online = False
        avisado = False
        primera = True
        try:
            while not self.parar.is_set():
                try:
                    crudo = ser.readline()
                except Exception as e:
                    self.puente.fallo(f"Se perdio el puerto {self.puerto}: {e}")
                    return
                if crudo:
                    if primera:                 # la primera linea suele llegar cortada
                        primera = False
                        continue
                    texto = crudo.decode("utf-8", errors="ignore")
                    for ciclo in lector.alimentar(texto):
                        if len(ciclo) < MIN_IDS:
                            continue
                        if not online:
                            online = True
                            avisado = False
                            self.puente.en_linea(self)
                        t_ultimo = time.time()
                        self.puente.publicar(ciclo)

                ahora = time.time()
                if online and ahora - t_ultimo > SIN_DATOS_S:
                    online = False
                    self.puente.fallo(f"Sin datos desde hace {int(SIN_DATOS_S)} s en {self.puerto}")
                elif not online and t_ultimo is None and not avisado and ahora - t_inicio > ESPERA_INICIAL_S:
                    avisado = True
                    self.puente.fallo(f"No llegan datos de {self.puerto} a {self.baudios} baudios. "
                                      f"El firmware imprime a 115200: revisa los baudios en Ajustes.")
        finally:
            try:
                ser.close()
            except Exception:
                pass
