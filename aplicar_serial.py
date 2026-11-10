"""
aplicar_serial.py - Agrega el conductor serial a TU puente_datos.py actual.

Modifica solo 5 puntos pequenos (no toca tus otros cambios) y guarda una copia
de respaldo (puente_datos.py.bak). Se puede correr una sola vez; si ya esta aplicado, avisa.

Uso (en la carpeta donde estan puente_datos.py y conductor_serial.py):
    python aplicar_serial.py
    python aplicar_serial.py ruta\\a\\puente_datos.py
"""
import os
import shutil
import sys

ruta = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "puente_datos.py")
if not os.path.isfile(ruta):
    sys.exit(f"No encuentro {ruta}")
if not os.path.isfile(os.path.join(os.path.dirname(os.path.abspath(ruta)), "conductor_serial.py")):
    sys.exit("Falta conductor_serial.py en la misma carpeta que puente_datos.py")

s = open(ruta, encoding="utf-8").read()
if "conductor_serial" in s:
    sys.exit("Ya estaba aplicado: no hice cambios.")

CAMBIOS = [
    # 1) importar el conductor
    ("from datetime import datetime\n",
     "from datetime import datetime\n\ntry:\n    from conductor_serial import ConductorSerial\nexcept ImportError:     # sin el archivo, el puente funciona igual (sin serial)\n    ConductorSerial = None\n"),
    # 2) registrarlo
    ('CONDUCTORES = {"sim": Simulador}\n',
     'CONDUCTORES = {"sim": Simulador}\nif ConductorSerial is not None:\n    CONDUCTORES["serial"] = ConductorSerial\n'),
    # 3) el estado "online" debe llevar el id completo de la fuente (p. ej. serial:COM10)
    ('self.cambiar_estado("online", conductor.nombre, conductor.detalle)',
     'self.cambiar_estado("online", self.fuente or conductor.nombre, conductor.detalle)'),
    # 4) "serial:COM10" -> conductor "serial" con puerto COM10
    ("        clase = CONDUCTORES.get(fuente)\n",
     '        clase = CONDUCTORES.get(fuente.split(":", 1)[0])\n        params = dict(params or {})\n        if ":" in fuente:\n            params.setdefault("puerto", fuente.split(":", 1)[1])\n'),
    # 5) los puertos detectados ya se pueden conectar
    ('"detalle": descripcion_puerto(p), "soportado": False})',
     '"detalle": descripcion_puerto(p), "soportado": ConductorSerial is not None})'),
]

for viejo, nuevo in CAMBIOS:
    if s.count(viejo) != 1:
        sys.exit("No pude aplicar el cambio porque no encontre (o hay varias veces) este texto:\n"
                 f"    {viejo.strip()[:90]}\nTu puente_datos.py es distinto al esperado. No modifique nada.")
    s = s.replace(viejo, nuevo)

shutil.copy2(ruta, ruta + ".bak")
open(ruta, "w", encoding="utf-8").write(s)
print("Listo. Respaldo en", ruta + ".bak")
print("Falta pyserial?  pip install pyserial")
