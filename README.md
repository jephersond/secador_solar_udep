# Visor Secador UDEP

Visor 3D (Godot 4.8) con puente en Python para el monitoreo del secador solar
de la UDEP. Proyecto del curso Proyectos IME, Grupo 5 (parte de instrumentación).

Muestra las temperaturas de las 6 bandejas y del aire, el clima, gráficas y
diagnóstico, y permite controlar los extractores del ESP32.

## Arquitectura

```
ESP32 (Modbus RTU, 10 sensores)
   │ USB serial 115200
   ▼
puente_datos.py  +  conductor_serial.py      (Python)
   │ UDP 127.0.0.1: 5006 (datos) / 5007 (comandos)
   ▼
Godot (visor)  ◄── clima_udp.py (Open-Meteo, UDP 5005)
```

| Archivo | Función |
|---|---|
| `principal.gd`, `interfaz.gd` | Escena 3D, interfaz, tarjetas y rótulos |
| `datos_sensores.gd` | Registros y modo en vivo; estados de los sensores (en vivo, retenido, sin señal, NaN) |
| `enlace_datos.gd` | Habla con el puente Python por UDP |
| `panel_conexion.gd` | Panel Conexión: registros, ESP32 en vivo, carpeta de registros |
| `panel_extractores.gd` | Control de extractores (modo, fuente, límites) |
| `puente_datos.py`, `conductor_serial.py` | Puente: serial, simulador, SD, grabación de sesiones |
| `clima_udp.py`, `clima.gd` | Clima real (Open-Meteo) y modos Auto, Manual, Registro, PC |
| `PROTOCOLO_EXTRACTORES.md` | Comandos Godot → ESP32 para los extractores |

## Cómo funciona

- Al abrir no hay datos: rótulos en NaN y bandejas grises.
- **Registro:** se carga un `.csv`/`.txt` desde Conexión; el clima pasa a Registro.
- **En vivo:** "Activar" en el ESP32; el clima pasa a Auto. Si un sensor tarda
  entre ciclos se retiene su último valor; pasado un tiempo se marca sin señal.
- **Extractores:** Godot solo envía modo y límites. El ESP32 decide y tiene el control final.

## Requisitos

- Godot 4.8 para abrir el proyecto.
- Python 3 y `pip install pyserial` para el modo en vivo.
- Internet solo para el clima real.

## Exportar

Proyecto → Exportar → Windows Desktop. Junto al `.exe` copiar
`puente_datos.py`, `conductor_serial.py` y `clima_udp.py`.
Guía para el usuario final: [`docs/LEEME.txt`](docs/LEEME.txt).

## Datos

Las sesiones y los registros abiertos se guardan en `registros/`, junto al
ejecutable (o a la raíz del proyecto en el editor). Las sesiones en vivo se
llaman `EnVivo_AAAAMMDD_HHMMSS.csv`. La carpeta no se sube a Git.
Se puede cambiar desde Conexión → "Cambiar carpeta…".
