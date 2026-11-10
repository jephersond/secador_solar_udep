"""
clima_udp.py - Consulta el clima en Open-Meteo y gestiona una cache local recortada.
Solo guarda en disco las horas de la simulacion para optimizar espacio.

Cada paquete UDP lleva (ademas de clima / nubes / lluvia / hora):
  fecha          "AAAA-MM-DD" a la que corresponden las curvas
  curva_nubes    24 valores (0-1)           curva_precip  24 valores (mm)
  curva_temp     24 valores (grados C)      curva_hr      24 valores (%)
  curva_viento   24 valores (m/s)           curva_pres    24 valores (hPa, superficie)
  curva_rad      24 valores (W/m2, radiacion de onda corta; promedio de la hora previa)
Las horas que no estan en cache van como null.
Los valores son ESTIMADOS por modelo (Open-Meteo), no de una estacion.
"""
import argparse
import json
import math
import os
import socket
import time
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

LAT, LON = -5.1945, -80.6328                   # Piura
TZ = timezone(timedelta(hours=-5))             # Peru: UTC-5

# clave corta que viaja a Godot -> variable de Open-Meteo
EXTRA = {
    "temp": "temperature_2m",
    "hr": "relative_humidity_2m",
    "viento": "wind_speed_10m",
    "pres": "surface_pressure",
    "rad": "shortwave_radiation",
}
VARIABLES = "cloud_cover,precipitation,weather_code," + ",".join(EXTRA.values())

# Ruta del archivo de cache: res://datos/clima_cache.json
DIR_BASE = os.path.dirname(os.path.abspath(__file__))
DIR_DATOS = os.path.join(DIR_BASE, "datos")
CACHE_FILE = os.path.join(DIR_DATOS if os.path.isdir(DIR_DATOS) else DIR_BASE, "clima_cache.json")


def cargar_cache():
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return {}
    return {}


def guardar_cache(cache):
    try:
        with open(CACHE_FILE, "w", encoding="utf-8") as f:
            json.dump(cache, f, indent=2)
    except Exception as e:
        print("[CACHE] Error guardando archivo:", e)


def pedir(url, params):
    q = urllib.parse.urlencode(params)
    with urllib.request.urlopen(url + "?" + q, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


def clasificar(nubes_pct, precip_mm, codigo):
    nub = (nubes_pct or 0) / 100.0
    precip = precip_mm or 0.0

    # Solo es lluvia si hay agua acumulada real (>= 0.5 mm)
    if precip >= 0.5:
        return {
            "clima": "lluvia",
            "nubes": max(nub, 0.85),
            "lluvia": max(0.3, min(1.0, precip / 2.0))
        }

    if nub >= 0.55:
        return {"clima": "nublado", "nubes": nub, "lluvia": 0.0}

    return {"clima": "soleado", "nubes": nub, "lluvia": 0.0}


def _a24(recorte, h_inicio, h_fin):
    """Rellena con None las horas fuera del recorte (hasta tener 24 valores)."""
    return [None] * h_inicio + list(recorte) + [None] * (23 - h_fin)


def clima_actual():
    p = {"latitude": LAT, "longitude": LON,
         "current": "cloud_cover,precipitation,weather_code",
         "hourly": VARIABLES,
         "wind_speed_unit": "ms",
         "forecast_days": 1,
         "timezone": "America/Lima"}
    d = pedir("https://api.open-meteo.com/v1/forecast", p)
    cur = d["current"]
    res = clasificar(cur.get("cloud_cover"), cur.get("precipitation"), cur.get("weather_code"))
    if "hourly" in d:
        h = d["hourly"]
        res["curva_nubes"] = [(c or 0) / 100.0 for c in h["cloud_cover"][:24]]
        res["curva_precip"] = [(pr or 0.0) for pr in h["precipitation"][:24]]
        for clave, var in EXTRA.items():
            res["curva_" + clave] = h[var][:24]
        res["fecha"] = h["time"][0][:10]          # fecha local de hoy
    res["fuente"] = "open-meteo"
    return res


def _desde_cache(c, fecha, hora):
    """Arma la respuesta a partir de una entrada de cache (sirve sin internet)."""
    h_inicio, h_fin = c["h_inicio"], c["h_fin"]
    nubes_rec = c["nubes"]
    precip_rec = c["precip"]
    # Reconstruimos la curva para Godot rellenando los extremos
    n_24 = [nubes_rec[0]] * h_inicio + nubes_rec + [nubes_rec[-1]] * (23 - h_fin)
    p_24 = [precip_rec[0]] * h_inicio + precip_rec + [precip_rec[-1]] * (23 - h_fin)

    i = min(int(hora), 23)
    res = clasificar(n_24[i] * 100.0, p_24[i], 0)
    res["curva_nubes"] = n_24
    res["curva_precip"] = p_24
    for clave in EXTRA:
        if clave in c:                              # caches viejas no las traen
            res["curva_" + clave] = _a24(c[clave], h_inicio, h_fin)
    res["fecha"] = fecha
    res["fuente"] = "cache_local"
    return res


def clima_historico(fecha, hora, duracion_h):
    h_inicio = max(0, min(23, int(math.floor(hora))))
    h_fin = max(h_inicio, min(23, int(math.ceil(hora + duracion_h))))

    cache = cargar_cache()
    c = cache.get(fecha)
    cubre = bool(c) and c.get("h_inicio", 0) <= h_inicio and c.get("h_fin", 23) >= h_fin

    # 1. Cache local completa (con las variables exteriores): no hace falta internet
    if cubre and "temp" in c:
        print(f"[CACHE] Cargando '{fecha}' desde disco (horas {c['h_inicio']} a {c['h_fin']}) [SIN INTERNET OK]")
        return _desde_cache(c, fecha, hora)

    # 2. Consultamos a Open-Meteo (24 horas del dia)
    p = {"latitude": LAT, "longitude": LON, "start_date": fecha, "end_date": fecha,
         "hourly": VARIABLES,
         "wind_speed_unit": "ms",
         "timezone": "America/Lima"}

    for url in ("https://archive-api.open-meteo.com/v1/archive",
                "https://api.open-meteo.com/v1/forecast"):
        try:
            h = pedir(url, p)["hourly"]
            if h["cloud_cover"][h_inicio] is not None:
                # Recortamos SOLO el intervalo de la simulacion para optimizar espacio
                nuevo = {
                    "h_inicio": h_inicio,
                    "h_fin": h_fin,
                    "nubes": [(v or 0) / 100.0 for v in h["cloud_cover"][h_inicio: h_fin + 1]],
                    "precip": [(v or 0.0) for v in h["precipitation"][h_inicio: h_fin + 1]],
                }
                for clave, var in EXTRA.items():
                    nuevo[clave] = h[var][h_inicio: h_fin + 1]
                cache[fecha] = nuevo
                guardar_cache(cache)
                print(f"[CACHE] Descargado de internet. Recortado a horas {h_inicio}-{h_fin} y guardado en disco.")

                res = _desde_cache(nuevo, fecha, hora)
                # la hora exacta se clasifica con los datos crudos, como antes
                res.update(clasificar(h["cloud_cover"][min(int(hora), 23)],
                                      h["precipitation"][min(int(hora), 23)],
                                      h["weather_code"][min(int(hora), 23)]))
                res["fuente"] = "open-meteo"
                return res
        except Exception as e:
            print("Aviso al consultar:", url, "->", e)

    # 3. Sin internet: una cache vieja (sin variables exteriores) es mejor que nada
    if cubre:
        print("[CACHE] Sin internet: uso la cache antigua (sin temperatura/humedad/viento).")
        return _desde_cache(c, fecha, hora)

    raise RuntimeError("sin conexion a internet ni datos en cache para esa fecha")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fecha", help="AAAA-MM-DD")
    ap.add_argument("--hora", type=float, default=12.0)
    ap.add_argument("--duracion", type=float, default=2.0, help="duracion en horas de la prueba")
    ap.add_argument("--puerto", type=int, default=5005)
    ap.add_argument("--cada", type=int, default=600)
    a = ap.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    ultimo = {"clima": "soleado", "nubes": 0.05, "lluvia": 0.0, "fuente": "sin_internet"}
    proxima = 0.0

    print("Enviando a 127.0.0.1:%d" % a.puerto)
    while True:
        if time.time() >= proxima:
            try:
                ultimo = clima_historico(a.fecha, a.hora, a.duracion) if a.fecha else clima_actual()
                proxima = time.time() + a.cada
                print("Clima activo:", ultimo["clima"], f"(Fuente: {ultimo.get('fuente', 'ok')})")
            except Exception as e:
                ultimo = {"clima": "soleado", "nubes": 0.05, "lluvia": 0.0,
                          "fuente": "sin_internet"}
                proxima = time.time() + 60
                print("Sin conexion ni cache (%s). Modo respaldo: soleado" % e)

        msg = dict(ultimo)
        msg["tipo"] = "historico" if a.fecha else "en_vivo"
        if a.fecha:
            msg["hora"] = a.hora
        else:
            n = datetime.now(TZ)
            msg["hora"] = n.hour + n.minute / 60.0

        sock.sendto(json.dumps(msg).encode("utf-8"), ("127.0.0.1", a.puerto))
        time.sleep(5)


if __name__ == "__main__":
    main()