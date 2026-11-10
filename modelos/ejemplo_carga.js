// EJEMPLO (no modifica el HTML). Requiere THREE r128 + THREE.GLTFLoader r128 (examples/js/loaders/GLTFLoader.js)
// y servir la carpeta por http (p. ej. `python -m http.server`), porque file:// bloquea fetch/GLB.
// `scene` es la THREE.Scene del visor (en el HTML se llama S).

// El visor usa MeshLambertMaterial; los .glb traen PBR (rugosidad 1, metálico 0) que se ve casi igual.
// Para recuperar exactamente el mismo sombreado se vuelve a Lambert. depthWrite=false en los translúcidos (<0,5),
// igual que skinMat / paneles de puerta / vidrio del invernadero.
function aLambert(m) {
  if (Array.isArray(m)) return m.map(aLambert);
  if (!m.isMeshStandardMaterial) return m;                      // Basic (huellas, sombras, camino) y líneas se dejan
  return new THREE.MeshLambertMaterial({
    color: m.color, map: m.map, transparent: m.transparent, opacity: m.opacity, side: m.side,
    alphaTest: m.alphaTest, vertexColors: m.vertexColors, depthWrite: !(m.transparent && m.opacity < 0.5)
  });
}

async function cargarModelos(scene, base = 'modelos/') {
  const man = await (await fetch(base + 'manifest.json')).json();
  const loader = new THREE.GLTFLoader();
  const cargar = f => new Promise((ok, err) => loader.load(base + f, ok, undefined, err));

  // Mismo giro que el visor (DRY_ROT = π/2): solo el secador gira; el entorno no.
  const DRY = new THREE.Group(); DRY.rotation.y = man.grupos.secador.rotacion_y_rad; scene.add(DRY);
  const env = new THREE.Group(); scene.add(env);

  // Referencias que el visor necesita (mismos nombres que en el código original)
  const refs = { tops: {}, sens: [], exts: [], blades: [], doors: { p1: {}, p2: {} },
                 parts: { L: [], U: [], S: [], P: [], M: [], B: [] }, pick: [] };
  const sufijo = { patas: 'L', travesanos: 'U', angulos: 'S', marco: 'P', malla_grupo: 'M', borde: 'B' };

  for (const p of man.piezas) {
    const root = (await cargar(p.archivo)).scene.children[0];   // nodo raíz con la posición del manifest
    root.traverse(o => { if (o.material) o.material = aLambert(o.material); });
    (p.pertenece_a === 'secador' ? DRY : env).add(root);

    root.traverse(o => {
      const u = o.userData || {};
      if (u.kind === 'tray')                          { refs.tops[u.id] = o; refs.pick.push(o); }          // colorear por ID de sonda
      else if (u.kind === 'sensor' || u.kind === 'anem') { refs.sens.push(o); refs.pick.push(o); }        // u.id, u.ex, u.y0
      else if (u.kind === 'ext')                      { refs.exts[u.n - 1] = o; refs.pick.push(o); }
      else if (u.kind === 'door')                     { refs.doors[u.key][/_L$/.test(o.name) ? 'L' : 'R'] = o; refs.pick.push(o); } // gira en rotation.y
      if (/^Extractor_\d_aspas$/.test(o.name))        refs.blades[+o.name.match(/Extractor_(\d)/)[1] - 1] = o;  // gira en rotation.z
      const m = o.name.match(/^B\d_(patas|travesanos|angulos|marco|malla_grupo|borde)$/);
      if (m) refs.parts[sufijo[m[1]]].push(o);                                                            // vista despiece (userData.tn)
    });
  }
  return refs;   // luego: tops[id].material.color = ..., doors.p1.L.rotation.y = ..., blades[n].rotation.z += ...
}
