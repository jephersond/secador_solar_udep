"""
puente_datos.py - Puente entre las fuentes de datos del secador y el visor Godot.

FASE 5: Lectura de microSD del ESP32, autodetección de puertos COM físicos
y verificación de salida a internet.

Comunicacion (todo UDP en 127.0.0.1):
  Python -> Godot  puerto 5006   (--puerto-godot)
  Godot  -> Python puerto 5007   (--puerto-cmd)
"""
import argparse
import csv
import glob
import json
import math
import os
import re
import socket
import sys
import threading
import time
from datetime import datetime, timedelta

try:
    from conductor_serial import ConductorSerial
except ImportError:     # sin el archivo, el puente funciona igual (sin serial)
    ConductorSerial = None

IDS_CSV = [1, 2, 4, 5, 6, 7, 8, 9, 15, 16]    # columnas del CSV de registro
ID_BME = 2                                     # el unico con r3 (presion)
LATIDO_S = 2.0                                 # reenvio periodico del estado
TIEMPO_SIN_GODOT_S = 20.0                      # sin pings de Godot durante este tiempo -> el puente se apaga


# ======================================================================
#  CONDUCTORES (cada fuente de datos es una clase)
# ======================================================================
class Conductor(threading.Thread):
    """Base: un hilo que llama a puente.publicar(ids) cada vez que hay lectura."""
    nombre = "base"

    def __init__(self, puente, params):
        super().__init__(daemon=True)
        self.puente = puente
        self.params = params or {}
        self.parar = threading.Event()
        self.detalle = ""

    def detener(self):
        self.parar.set()


def _entero(txt):
    try:
        v = float(txt)
        return None if math.isnan(v) else int(round(v))
    except (ValueError, TypeError):
        return None


class Simulador(Conductor):
    """Repite un CSV respetando los intervalos acelerados por la velocidad."""
    nombre = "sim"

    def __init__(self, puente, params):
        super().__init__(puente, params)
        self.ruta = self.params.get("csv") or puente.csv_por_defecto
        self.velocidad = max(float(self.params.get("velocidad", puente.velocidad)), 0.1)
        self.detalle = os.path.basename(self.ruta)

    def _leer_filas(self):
        filas = []
        with open(self.ruta, newline="", encoding="utf-8-sig") as f:
            lector = csv.DictReader(f)
            for r in lector:
                try:
                    t = datetime.strptime(r["Fecha"].strip(), "%Y-%m-%d %H:%M:%S")
                except (KeyError, ValueError):
                    continue
                ids = {}
                for id_ in IDS_CSV:
                    r1 = _entero(r.get(f"ID{id_}_r1"))
                    r2 = _entero(r.get(f"ID{id_}_r2"))
                    if r1 is None and r2 is None:
                        ids[str(id_)] = None
                        continue
                    regs = [r1, r2]
                    if id_ == ID_BME:
                        regs.append(_entero(r.get(f"ID{id_}_r3")))
                    ids[str(id_)] = regs
                filas.append((t, ids))
        return filas

    def run(self):
        try:
            filas = self._leer_filas()
            if len(filas) < 2:
                raise RuntimeError("el CSV tiene muy pocas filas validas")
        except Exception as e:
            self.puente.fallo(f"Simulador: {e}")
            return
            
        self.puente.en_linea(self)

        # Cada vuelta del CSV se desplaza en el tiempo para que Godot no
        # descarte las lecturas como repetidas (ts <= ultimo ts).
        span = (filas[-1][0] - filas[0][0]).total_seconds()
        paso = span / (len(filas) - 1)
        vuelta = 0

        while not self.parar.is_set():
            desplazo = timedelta(seconds=vuelta * (span + paso))
            vuelta += 1
            for i, (t_fila, ids) in enumerate(filas):
                if self.parar.is_set():
                    return
                # Envia la estampa del archivo para que Godot avance de min 0 a min 60
                self.puente.publicar(ids, fecha_estampa=t_fila + desplazo)
                if i + 1 < len(filas):
                    dt = (filas[i + 1][0] - t_fila).total_seconds()
                    # Espera dividida entre la velocidad elegida (ej. x10, x60)
                    if self.parar.wait(max(dt, 0.02) / self.velocidad):
                        return
                    

CONDUCTORES = {"sim": Simulador}
if ConductorSerial is not None:
    CONDUCTORES["serial"] = ConductorSerial


# ======================================================================
#  AYUDANTES DE DETECCION (SD del ESP32, internet, puertos serie)
# ======================================================================
# sin_rtc.csv se excluye de la regex: no contiene fechas reales de calendario
DIA_SD = re.compile(r"^\d{4}-\d{2}-\d{2}\.csv$", re.IGNORECASE)
IDS_SD = [2, 4, 5, 6, 7, 8, 9, 15, 16]          # el ESP32 no guarda el ID1
COLS_SD = {                                      # id: (columna T, columna HR)
    2: ("T_amb_C", "HR_amb_pct"), 6: ("T_b1_C", "HR_b1_pct"), 5: ("T_b2_C", "HR_b2_pct"),
    4: ("T_b3_C", "HR_b3_pct"), 7: ("T_b4_C", "HR_b4_pct"), 8: ("T_b5_C", "HR_b5_pct"),
    9: ("T_b6_C", "HR_b6_pct"),
}
COLS_VIENTO = {15: "v_ws200_ms", 16: "v_pr3000_ms"}
INVERTIDOS_RAW = {6}                             # ID6: registros en orden T, HR
BEAUFORT = [0.3, 1.6, 3.4, 5.5, 8.0, 10.8, 13.9, 17.2, 20.8, 24.5, 28.5, 32.7]

VID_PID = {
    (0x10C4, 0xEA60): "CP210x, tipico de ESP32",
    (0x1A86, 0x7523): "CH340, tipico de ESP32/Arduino",
    (0x1A86, 0x55D4): "CH9102, tipico de ESP32",
    (0x0403, 0x6001): "FTDI (convertidor USB-serie)",
}


def descripcion_puerto(p):
    pista = VID_PID.get((p.vid, p.pid), "")
    if not pista and p.vid == 0x2341:
        pista = "Arduino"
    if not pista and p.vid == 0x303A:
        pista = "ESP32 (USB nativo)"
    return " · ".join(x for x in (p.description, pista) if x)


def hay_internet():
    try:
        socket.create_connection(("api.open-meteo.com", 443), timeout=1.5).close()
        return True
    except OSError:
        return False


def raices_extraibles(extra=None):
    raices = []
    if extra and os.path.isdir(extra):
        raices.append(extra)
    if sys.platform.startswith("win"):
        try:
            import ctypes
            mascara = ctypes.windll.kernel32.GetLogicalDrives()
            for i in range(26):
                letra = f"{chr(65 + i)}:\\"
                if mascara & (1 << i) and ctypes.windll.kernel32.GetDriveTypeW(letra) == 2:
                    raices.append(letra)
        except Exception:
            pass
    else:
        for base in ("/media", "/run/media", "/Volumes", "/mnt"):
            raices += [d for d in sorted(glob.glob(base + "/*") + glob.glob(base + "/*/*"))
                       if os.path.isdir(d)]
    return raices


def archivos_sd(raiz):
    try:
        return sorted(n for n in os.listdir(raiz) if DIA_SD.match(n))
    except OSError:
        return []


def hay_sin_rtc(raiz):
    return os.path.isfile(os.path.join(raiz, "sin_rtc.csv"))


def _x10(txt):
    try:
        v = float(str(txt).strip())
        return None if math.isnan(v) else int(round(v * 10))
    except (ValueError, TypeError):
        return None

def convertir_sd(ruta, dir_salida):
    """CSV del ESP32 -> archivo de registros crudos (formato de MATLAB)."""
    filas, saltadas = [], 0
    with open(ruta, newline="", encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            try:
                t = datetime.strptime((r.get("fecha_hora") or "").strip(), "%Y-%m-%d %H:%M:%S")
            except ValueError:
                saltadas += 1
                continue
            ids = {}
            for id_, (col_t, col_h) in COLS_SD.items():
                T, H = _x10(r.get(col_t)), _x10(r.get(col_h))
                if id_ == 2:
                    regs = [H, T, _entero(r.get("P_amb_hPa"))]
                elif id_ in INVERTIDOS_RAW:
                    regs = [T, H]
                else:
                    regs = [H, T]
                ids[str(id_)] = None if all(v is None for v in regs) else regs
            for id_, col in COLS_VIENTO.items():
                v = _x10(r.get(col))
                ids[str(id_)] = None if v is None else [v, sum(1 for b in BEAUFORT if v / 10.0 >= b)]
            filas.append((t, ids))
            
    if not filas:
        raise ValueError("no tiene filas con fecha valida (¿el ESP32 estaba sin RTC?)")
        
    os.makedirs(dir_salida, exist_ok=True)
    # Evita que Godot escanee esta carpeta
    with open(os.path.join(dir_salida, ".gdignore"), "a") as f_ign:
        pass

    # Guardamos como .txt para evitar que Godot cree archivos .translation
    nombre_base = os.path.splitext(os.path.basename(ruta))[0] + ".txt"
    destino = os.path.join(dir_salida, "SD_" + nombre_base)
    
    with open(destino, "w", newline="", encoding="utf-8") as g:
        w = csv.writer(g, lineterminator="\n")
        w.writerow(["Fecha"] + [f"ID{i}_r{k}" for i in IDS_SD for k in (1, 2, 3)])
        for t, ids in filas:
            fila = [f"{t:%Y-%m-%d %H:%M:%S}"]
            for i in IDS_SD:
                regs = ids.get(str(i)) or []
                for k in range(3):
                    v = regs[k] if k < len(regs) else None
                    fila.append("NaN" if v is None else v)
            w.writerow(fila)
    return destino, len(filas), saltadas


# ======================================================================
#  PUENTE
# ======================================================================
# Unicos comandos que se aceptan hacia el ESP32 (ver PROTOCOLO_EXTRACTORES.md)
COMANDO_EXT = re.compile(
    r"^(X[12] (MODO (OFF|ON|AUTO)|FUENTE (EXT|AMB)|LIM \d{1,3}(\.\d)? \d{1,3}(\.\d)?)|X\?)$")


class Puente:
    def __init__(self, a):
        self.csv_por_defecto = a.csv
        self.velocidad = a.velocidad
        self.registrar = a.registrar
        self.dir_registros = a.carpeta_registros
        self.carpeta_sd = a.carpeta_sd
        self.destino = ("127.0.0.1", a.puerto_godot)
        self.tx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.rx.bind(("127.0.0.1", a.puerto_cmd))
        self.rx.settimeout(0.5)
        self.lock = threading.Lock()
        self.conductor = None
        self.estado = "desconectado"
        self.fuente = ""
        self.detalle = ""
        self.lecturas = 0
        self.archivo_csv = None
        self.escritor = None
        self.ultimo_latido = 0.0

    # ---------- envio ----------
    def enviar(self, msg):
        msg.setdefault("v", 1)
        try:
            self.tx.sendto(json.dumps(msg, separators=(",", ":")).encode("utf-8"), self.destino)
        except OSError as e:
            print("[PUENTE] No pude enviar a Godot:", e)

    def enviar_estado(self):
        self.enviar({"tipo": "enlace", "estado": self.estado, "fuente": self.fuente,
                     "detalle": self.detalle, "lecturas": self.lecturas})

    def cambiar_estado(self, estado, fuente="", detalle=""):
        with self.lock:
            self.estado, self.fuente, self.detalle = estado, fuente, detalle
        print(f"[PUENTE] estado = {estado} {fuente} {detalle}".rstrip())
        self.enviar_estado()

    # ---------- deteccion de fuentes ----------
    def detectar(self):
        lista = [{"id": "sim", "tipo": "archivo", "nombre": "Simulador (CSV)",
                  "detalle": os.path.basename(self.csv_por_defecto), "soportado": True}]
        try:
            from serial.tools import list_ports
            for p in sorted(list_ports.comports(), key=lambda x: x.device):
                # Filtra puertos Bluetooth virtuales de Windows
                if "bluetooth" in (p.description or "").lower() or (p.hwid or "").upper().startswith("BTHENUM"):
                    continue
                lista.append({"id": "serial:" + p.device, "tipo": "serial", "nombre": p.device,
                              "detalle": descripcion_puerto(p), "soportado": ConductorSerial is not None})
        except ImportError:
            pass
        for raiz in self.raices_sd():
            nombres = archivos_sd(raiz)
            sin_rtc = hay_sin_rtc(raiz)
            if not nombres and not sin_rtc:
                continue
            es_carpeta = raiz == self.carpeta_sd
            etiqueta = os.path.basename(raiz.rstrip("\\/")) or raiz.rstrip("\\/")
            
            detalle = (f"{len(nombres)} dia(s): {nombres[0][:-4]} … {nombres[-1][:-4]}" if nombres
                       else "Solo hay sin_rtc.csv (el ESP32 no tenia hora): no se puede importar")
            if nombres and sin_rtc:
                detalle += " · sin_rtc.csv omitido"

            lista.append({
                "id": "sd:" + raiz, "tipo": "sd",
                "nombre": ("Carpeta " + etiqueta) if es_carpeta else f"microSD ({raiz.rstrip(chr(92) + '/')})",
                "detalle": detalle,
                "soportado": bool(nombres), "accion": "importar", "opciones": {"archivo": nombres}})
        return lista

    def raices_sd(self):
        return raices_extraibles(self.carpeta_sd)

    def enviar_fuentes(self):
        def tarea():
            lista = self.detectar()
            ok = hay_internet()
            lista.append({"id": "internet", "tipo": "internet", "nombre": "Internet",
                          "detalle": "Con salida a la red (clima Open-Meteo)" if ok
                          else "Sin conexion a internet", "soportado": False, "info": True, "ok": ok})
            self.enviar({"tipo": "fuentes", "lista": lista})
        threading.Thread(target=tarea, daemon=True).start()

    def aviso(self, texto, error=False):
        print(("[PUENTE] AVISO: " if error else "[PUENTE] ") + texto)
        self.enviar({"tipo": "aviso", "error": error, "texto": texto})

    def importar(self, fuente, params):
        raiz = fuente[3:] if fuente.startswith("sd:") else ""
        nombre = os.path.basename(str(params.get("archivo", "")))
        ruta = os.path.join(raiz, nombre)
        if raiz not in self.raices_sd() or not DIA_SD.match(nombre) or not os.path.isfile(ruta):
            self.aviso("No encuentro ese archivo en la SD. Pulsa «Buscar de nuevo».", True)
            return
        try:
            destino, n, saltadas = convertir_sd(ruta, self.dir_registros)
        except Exception as e:
            self.aviso(f"No pude importar {nombre}: {e}", True)
            return
        extra = f" ({saltadas} filas sin hora valida se omitieron)" if saltadas else ""
        self.aviso(f"{nombre}: {n} lecturas convertidas{extra}")
        self.enviar({"tipo": "archivo_listo", "ruta": os.path.abspath(destino),
                     "origen": nombre, "filas": n, "saltadas": saltadas})

    # ---------- ciclo de vida de una conexion ----------
    def conectar(self, fuente, params):
        self.desconectar(silencioso=True)
        clase = CONDUCTORES.get(fuente.split(":", 1)[0])
        params = dict(params or {})
        if ":" in fuente:
            params.setdefault("puerto", fuente.split(":", 1)[1])
        if clase is None:
            self.cambiar_estado("error", fuente, "fuente no soportada todavia")
            return
        self.cambiar_estado("buscando", fuente, "")
        self.lecturas = 0
        self._abrir_registro()
        self.conductor = clase(self, params)
        self.conductor.start()

    # ---------- control de extractores (comandos de texto hacia el ESP32) ----------
    def extractor(self, linea):
        linea = str(linea).strip()
        if not COMANDO_EXT.match(linea):
            self.aviso(f"Comando de extractor no valido: {linea}", True)
            return
        c = self.conductor
        if self.estado != "online" or c is None or not hasattr(c, "enviar"):
            self.aviso("Activa el modo en vivo con el ESP32 antes de controlar los extractores.", True)
            return
        if not c.enviar(linea):
            self.aviso("No pude escribir en el puerto serial.", True)

    def linea_extractor(self, texto):
        self.enviar({"tipo": "extractores", "linea": texto})

    def en_linea(self, conductor):
        self.cambiar_estado("online", self.fuente or conductor.nombre, conductor.detalle)

    def fallo(self, texto):
        self.cambiar_estado("error", self.fuente, texto)

    def desconectar(self, silencioso=False):
        if self.conductor is not None:
            self.conductor.detener()
            self.conductor.join(timeout=2.0)
            self.conductor = None
        self._cerrar_registro()
        if not silencioso:
            self.cambiar_estado("desconectado", "", "")

    # ---------- datos ----------
    def publicar(self, ids, fecha_estampa=None):
        if fecha_estampa is not None:
            ahora = fecha_estampa
            t = f"{ahora:%Y-%m-%d %H:%M:%S}.000"
        else:
            ahora = datetime.now()
            t = f"{ahora:%Y-%m-%d %H:%M:%S}.{ahora.microsecond // 1000:03d}"
            
        self.lecturas += 1
        self.enviar({"tipo": "datos", "t": t, "ids": ids})
        if self.escritor is not None:
            fila = [f"{ahora:%Y-%m-%d %H:%M:%S}"]
            for id_ in IDS_CSV:
                r = ids.get(str(id_)) or []
                for k in range(3):
                    v = r[k] if k < len(r) and r[k] is not None else None
                    fila.append("NaN" if v is None else v)
            self.escritor.writerow(fila)
            self.archivo_csv.flush()

    def _abrir_registro(self):
        if not self.registrar:
            return
        os.makedirs(self.dir_registros, exist_ok=True)
        # Evita que Godot importe los CSV de esta carpeta como traducciones
        with open(os.path.join(self.dir_registros, ".gdignore"), "a"):
            pass
        ruta = os.path.join(self.dir_registros, f"Registro_{datetime.now():%Y%m%d_%H%M%S}.csv")
        self.archivo_csv = open(ruta, "w", newline="", encoding="utf-8")
        self.escritor = csv.writer(self.archivo_csv, lineterminator="\n")
        cab = ["Fecha"] + [f"ID{i}_r{k}" for i in IDS_CSV for k in (1, 2, 3)]
        self.escritor.writerow(cab)
        print("[PUENTE] Guardando registro en", ruta)

    def _cerrar_registro(self):
        if self.archivo_csv is not None:
            self.archivo_csv.close()
        self.archivo_csv = None
        self.escritor = None

    # ---------- comandos ----------
    def atender(self, texto):
        try:
            c = json.loads(texto)
        except json.JSONDecodeError:
            return
        cmd = c.get("cmd")
        if cmd == "buscar":
            self.enviar_fuentes()
            self.enviar_estado()
        elif cmd == "conectar":
            self.conectar(c.get("fuente", ""), c.get("params") or {})
        elif cmd == "desconectar":
            self.desconectar()
        elif cmd == "importar":
            threading.Thread(target=self.importar, daemon=True,
                             args=(str(c.get("fuente", "")), c.get("params") or {})).start()
        elif cmd == "extractor":
            self.extractor(c.get("linea", ""))
        elif cmd == "ping":
            self.enviar_estado()

    def bucle(self, auto):
        print(f"[PUENTE] Escuchando comandos en 127.0.0.1:{self.rx.getsockname()[1]} "
              f"| enviando a Godot en {self.destino[0]}:{self.destino[1]}")
        self.enviar_fuentes()
        self.enviar_estado()
        if auto:
            self.conectar(auto, {})
            
        t_ultimo_contacto = time.time()

        try:
            while True:
                ahora = time.time()
                try:
                    datos, _ = self.rx.recvfrom(65535)
                    self.atender(datos.decode("utf-8", errors="replace"))
                    t_ultimo_contacto = ahora   # Godot está vivo
                except socket.timeout:
                    pass
                except ConnectionResetError:
                    pass

                # Latido hacia Godot
                if ahora - self.ultimo_latido >= LATIDO_S:
                    self.ultimo_latido = ahora
                    self.enviar_estado()

                # AUTO-CIERRE: Si Godot se cierra o lo detienes con el botón rojo,
                # tras TIEMPO_SIN_GODOT_S sin comandos ni pings, Python se apaga solo.
                # (No aplica con --auto: ahi se prueba sin Godot.)
                if not auto and ahora - t_ultimo_contacto > TIEMPO_SIN_GODOT_S:
                    print("[PUENTE] Godot se cerró. Apagando puente Python...")
                    break
                    
        except KeyboardInterrupt:
            print("\n[PUENTE] Cerrando.")
        finally:
            self.desconectar(silencioso=True)
            os._exit(0)   # Mata todos los hilos secundarios y no deja zombies

def main():
    base = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description="Puente de datos del secador -> Godot")
    ap.add_argument("--csv", default=os.path.join(base, "datos", "Registro_60_min.txt"),
                    help="CSV que repite el simulador")
    ap.add_argument("--velocidad", type=float, default=10.0,
                    help="factor de velocidad del simulador (1 = tiempo real)")
    ap.add_argument("--puerto-godot", type=int, default=5006)
    ap.add_argument("--puerto-cmd", type=int, default=5007)
    ap.add_argument("--carpeta-sd", default=None,
                    help="carpeta con los CSV del ESP32 (si copiaste la SD al disco)")
    ap.add_argument("--registrar", action="store_true",
                    help="guardar cada sesion en un CSV (mismo formato que MATLAB)")
    ap.add_argument("--carpeta-registros", default=os.path.join(base, "registros_puente"))
    ap.add_argument("--auto", choices=list(CONDUCTORES), default=None,
                    help="conectar solo al iniciar (para pruebas sin Godot; con esto no se apaga solo)")
    a = ap.parse_args()
    Puente(a).bucle(a.auto)


if __name__ == "__main__":
    main()