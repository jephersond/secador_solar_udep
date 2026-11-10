# Modelos 3D del secador solar UDEP (Grupo 5)

**Analogía:** el visor arma el secador "de memoria", como quien arma un Lego sin caja. Estos `.glb` son las
cajas de piezas ya separadas, y `manifest.json` es la hoja de instrucciones: dice dónde va cada caja.

## Qué hay aquí
| Archivo | Contenido |
|---|---|
| `estructura_tubos.glb` | 137 tubos: 4 arcos, largueros, dinteles y jambas de los testeros |
| `cubierta_policarbonato.glb` | Piel translúcida del arco y de los 2 testeros (con hueco de puerta) |
| `mallas_laterales.glb` | Mallas inferiores de 500 mm |
| `piso_concreto.glb` | Losa 6,93 × 0,15 × 7,79 m (textura incrustada) |
| `bandeja_B1.glb … B6.glb` | Cada bandeja: patas, travesaños, ángulos, marco, borde y malla (`B#_malla`) |
| `puerta_1.glb`, `puerta_2.glb` | Dos hojas (`Puerta#_hoja_L` / `_R`), origen en la bisagra |
| `extractores_par_1.glb`, `_par_2.glb` | Extractores 1-2 y 3-4 (placa 380 × 380 mm; aspas = `Extractor_#_aspas`) |
| `sondas_anemometros.glb` | Sondas ID2, ID4–ID9 y anemómetros ID15 (WS200), ID16 (PR-3000) |
| `entorno_terreno.glb`, `entorno_arboles.glb`, `entorno_edificios.glb` | Entorno, separado del secador |
| `manifest.json` | Posición, rotación, escala, caja envolvente y materiales de cada pieza |
| `ejemplo_carga.js` | Cómo cargarlos con GLTFLoader (no modifica el HTML) |
| `herramientas/` | Scripts para volver a generar todo desde el HTML |

## Reglas del modelo
- Unidades: metros. Y arriba. Puerta 1 al norte (−Z); Puerta 2 y extractores al sur (+Z). X: oeste (−) a este (+).
- Las piezas del secador están **sin el giro de 90°** que el visor aplica (`DRY_ROT = π/2`, Puerta 2 hacia +X).
  Para rearmar igual: grupo con `rotation.y = π/2` y ahí todas las piezas con `pertenece_a: "secador"`.
  El entorno va sin giro.
- Bandejas: B1-B3 en x = −1,48 m (B1 junto a la Puerta 1); B4-B6 en x = +1,48 m (B4 lado extractores, B6 Puerta 1).
  Las dos filas están a la misma altura (malla a y = 1,025 m).
- Los nombres son nuevos: el código original **no usa `name`**, usa `userData` (`kind`, `id`, `n`, `key`).
  Eso se guardó como *extras* del glTF y reaparece en `object.userData` al cargar.

## Editar en Blender
1. `Archivo > Importar > glTF 2.0`. No renombres los objetos (el visor y el manifest dependen de ellos).
2. Al exportar: formato **GLB**, **+Y Up**, y activa **Include > Custom Properties** (si no, se pierden `id`, `n`, `kind`).
3. Mantén el origen de cada pieza donde está (bandejas en su centro, puertas en la bisagra, extractores en su placa).
4. Los colores se guardaron con los mismos valores del visor; Blender los mostrará algo más claros (es solo visualización).

## Recargar en el HTML (sin tocarlo todavía)
Ver `ejemplo_carga.js`. Resumen: añadir GLTFLoader r128, servir con un servidor local (`python -m http.server`,
`file://` no deja leer los `.glb`), cargar cada archivo del manifest, convertir materiales a Lambert y
reconstruir `tops`, `sens`, `exts`, `blades`, `doors`, `parts` y `pick` leyendo `userData` y los nombres.

## Pendiente / no exportado
- **Lecho de piedras:** no existe en el código (solo piedras sueltas del entorno, en `entorno_terreno.glb`).
- **Soportes de los anemómetros:** en el código son solo cilindros Ø0,14 × 0,16 m a y = 2,05 m; no hay mástil ni soporte.
- Cielo y neblina (shaders), luces, niebla, rótulos de texto, flujo de aire, cotas y conexiones eléctricas: se siguen creando por código.
- Textura de concreto, arena y huellas: usan `Math.random`; el `.glb` guarda una variante.
