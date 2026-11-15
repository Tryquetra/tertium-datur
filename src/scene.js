import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';

/**
 * Balanced ternary state values and visual sector mapping.
 * Sector 0 (top, between 30 deg and 150 deg): state 0 (neutral)
 * Sector 1 (left, between 150 deg and 270 deg): state -1 (negative)
 * Sector 2 (right, between 270 deg and 30 deg): state +1 (positive)
 */
const TRIT_STATES = [-1, 0, 1];
const SECTOR_CONFIG = {
  0: {
    startDeg: 30,
    midDeg: 90,
    endDeg: 150,
    activeColor: 0xe2e8f0,
    activeEmissive: 0x475569,
    inactiveColor: 0x262b36,
    label: '0'
  },
  [-1]: {
    startDeg: 150,
    midDeg: 210,
    endDeg: 270,
    activeColor: 0x38bdf8,
    activeEmissive: 0x0369a1,
    inactiveColor: 0x162436,
    label: '-1'
  },
  1: {
    startDeg: 270,
    midDeg: 330,
    endDeg: 30,
    activeColor: 0xfb923c,
    activeEmissive: 0xc2410c,
    inactiveColor: 0x332018,
    label: '+1'
  }
};

const DEG2RAD = Math.PI / 180;
const SQRT3 = Math.sqrt(3);

/**
 * Converts axial coordinates (q, r) for pointy-top hexagons into 3D (x, z) coordinates.
 */
function axialToXZ(q, r, pitchRadius) {
  const x = pitchRadius * (SQRT3 * q + (SQRT3 * 0.5) * r);
  const z = pitchRadius * (1.5 * r);
  return { x, z };
}

/**
 * Generates the 2D closed THREE.Shape of a single congruent rhombus inside a regular
 * pointy-top hexagon partitioned by a 120-degree Y-junction.
 */
function createRhombusSectorGeometry(radius, inset, depth, stateKey) {
  const cfg = SECTOR_CONFIG[stateKey];
  const pCenter = new THREE.Vector2(0, 0);
  const a1 = cfg.startDeg * DEG2RAD;
  const a2 = cfg.midDeg * DEG2RAD;
  const a3 = cfg.endDeg * DEG2RAD;

  const rOuter = radius - inset;
  const v1 = new THREE.Vector2(Math.cos(a1) * rOuter, Math.sin(a1) * rOuter);
  const v2 = new THREE.Vector2(Math.cos(a2) * rOuter, Math.sin(a2) * rOuter);
  const v3 = new THREE.Vector2(Math.cos(a3) * rOuter, Math.sin(a3) * rOuter);

  // Shrink slightly toward the rhombus centroid so the golden Y arms sit cleanly between sectors.
  const centroid = new THREE.Vector2()
    .add(pCenter)
    .add(v1)
    .add(v2)
    .add(v3)
    .multiplyScalar(0.25);

  const shrink = (pt, factor) => pt.clone().lerp(centroid, factor);
  const s0 = shrink(pCenter, 0.08);
  const s1 = shrink(v1, 0.08);
  const s2 = shrink(v2, 0.04);
  const s3 = shrink(v3, 0.08);

  const shape = new THREE.Shape();
  shape.moveTo(s0.x, s0.y);
  shape.lineTo(s1.x, s1.y);
  shape.lineTo(s2.x, s2.y);
  shape.lineTo(s3.x, s3.y);
  shape.closePath();

  const geom = new THREE.ExtrudeGeometry(shape, {
    depth,
    bevelEnabled: true,
    bevelThickness: 0.025,
    bevelSize: 0.02,
    bevelSegments: 2
  });
  geom.rotateX(-Math.PI / 2);
  return geom;
}

/**
 * Generates an extruded 120-degree isotropic Y-junction geometry matching the user's reference shape:
 * arms extend along 30 deg (top-right), 150 deg (top-left), and 270 deg (bottom-vertical).
 */
function createYJunctionGeometry(armLength, armWidth, height) {
  const halfW = armWidth * 0.5;
  const rInner = (2 * halfW) / SQRT3;
  const armAngles = [30, 150, 270];
  const crotchAngles = [90, 210, 330];

  const shape = new THREE.Shape();
  for (let i = 0; i < 3; i++) {
    const theta = armAngles[i] * DEG2RAD;
    const ux = Math.cos(theta);
    const uy = Math.sin(theta);
    const nx = -uy;
    const ny = ux;

    const pRightX = ux * armLength - nx * halfW;
    const pRightY = uy * armLength - ny * halfW;
    const pLeftX = ux * armLength + nx * halfW;
    const pLeftY = uy * armLength + ny * halfW;

    const cTheta = crotchAngles[i] * DEG2RAD;
    const cX = Math.cos(cTheta) * rInner;
    const cY = Math.sin(cTheta) * rInner;

    if (i === 0) {
      shape.moveTo(pRightX, pRightY);
    } else {
      shape.lineTo(pRightX, pRightY);
    }
    shape.lineTo(pLeftX, pLeftY);
    shape.lineTo(cX, cY);
  }
  shape.closePath();

  const geom = new THREE.ExtrudeGeometry(shape, {
    depth: height,
    bevelEnabled: true,
    bevelThickness: 0.02,
    bevelSize: 0.015,
    bevelSegments: 2
  });
  geom.rotateX(-Math.PI / 2);
  return geom;
}

/**
 * Generates a subtle hexagonal base socket underneath each ternary cell.
 */
function createHexBaseGeometry(radius, height) {
  const shape = new THREE.Shape();
  for (let i = 0; i < 6; i++) {
    const angle = (30 + i * 60) * DEG2RAD;
    const x = Math.cos(angle) * radius;
    const y = Math.sin(angle) * radius;
    if (i === 0) shape.moveTo(x, y);
    else shape.lineTo(x, y);
  }
  shape.closePath();

  const geom = new THREE.ExtrudeGeometry(shape, {
    depth: height,
    bevelEnabled: true,
    bevelThickness: 0.02,
    bevelSize: 0.02,
    bevelSegments: 1
  });
  geom.rotateX(-Math.PI / 2);
  return geom;
}

/**
 * Builds the axial coordinates for a 7-cell rosette (center + 6 neighbors).
 */
function getRosetteCoords(centerQ = 0, centerR = 0) {
  const offsets = [
    [0, 0],
    [1, 0],
    [1, -1],
    [0, -1],
    [-1, 0],
    [-1, 1],
    [0, 1]
  ];
  return offsets.map(([dq, dr], idx) => ({
    q: centerQ + dq,
    r: centerR + dr,
    isCenter: idx === 0,
    localIndex: idx
  }));
}

/**
 * Builds the 21-cell Word21 cluster: three 7-cell rosettes symmetrically arranged
 * at 120 degrees around an empty origin cavity housing the main golden Y-bus.
 */
function getWord21Coords() {
  const rosetteCenters = [
    { q: 2, r: -1, cluster: 0 }, // 30 deg branch (top-right)
    { q: -1, r: -1, cluster: 1 }, // 150 deg branch (top-left)
    { q: -1, r: 2, cluster: 2 } // 270 deg branch (bottom)
  ];
  const cells = [];
  let bitIndex = 0;
  for (const rc of rosetteCenters) {
    for (const c of getRosetteCoords(rc.q, rc.r)) {
      cells.push({
        q: c.q,
        r: c.r,
        isCenter: c.isCenter,
        cluster: rc.cluster,
        tritIndex: bitIndex++
      });
    }
  }
  return cells;
}

/**
 * Decomposes a BigInt decimal integer into `count` balanced trits {-1, 0, +1},
 * ordered from least-significant trit (index 0 = 3^0) upward.
 */
function decimalToBalancedTrits(valueBigInt, count) {
  let n = valueBigInt;
  const trits = new Array(count).fill(0);
  for (let i = 0; i < count; i++) {
    if (n === 0n) break;
    const rem = ((n % 3n) + 3n) % 3n;
    if (rem === 0n) {
      trits[i] = 0;
      n = n / 3n;
    } else if (rem === 1n) {
      trits[i] = 1;
      n = (n - 1n) / 3n;
    } else {
      trits[i] = -1;
      n = (n + 1n) / 3n;
    }
  }
  return trits;
}

/**
 * Computes balanced ternary decimal value and weighted delta-V^2 switching energy.
 */
function computeTelemetry(cells, lastDeltaV2) {
  let value = 0n;
  let pow3 = 1n;
  const counts = { [-1]: 0, 0: 0, 1: 0 };
  for (let i = 0; i < cells.length; i++) {
    const t = BigInt(cells[i].state);
    value += t * pow3;
    pow3 *= 3n;
    counts[cells[i].state] += 1;
  }
  return {
    decimal: value.toString(),
    counts,
    lastDeltaV2
  };
}

/**
 * Main interactive 3D Ternary FPGA scene controller.
 */
export function mountTernaryFpgaScene(options) {
  const {
    container,
    canvas,
    onTelemetryChange,
    initialMode = 'cell'
  } = options;

  const renderer = new THREE.WebGLRenderer({
    canvas,
    antialias: true,
    alpha: true,
    powerPreference: 'high-performance'
  });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.15;

  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(40, 1, 0.1, 200);
  camera.position.set(0, 6.2, 6.8);

  const controls = new OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.dampingFactor = 0.07;
  controls.maxPolarAngle = Math.PI * 0.47;
  controls.minDistance = 2.4;
  controls.maxDistance = 32;

  // Lighting rig tailored for metallic gold Y-junctions and faceted translucent/satin sectors.
  const hemiLight = new THREE.HemisphereLight(0xf8fafc, 0x1e293b, 1.0);
  scene.add(hemiLight);

  const keyLight = new THREE.DirectionalLight(0xfffbeb, 2.2);
  keyLight.position.set(6, 12, 8);
  scene.add(keyLight);

  const rimLight = new THREE.DirectionalLight(0x38bdf8, 1.1);
  rimLight.position.set(-8, 6, -6);
  scene.add(rimLight);

  const warmFill = new THREE.PointLight(0xf59e0b, 1.4, 30);
  warmFill.position.set(0, 4, 2);
  scene.add(warmFill);

  // Shared materials and geometries
  const goldMaterial = new THREE.MeshPhysicalMaterial({
    color: 0xf5c542,
    emissive: 0x3a2500,
    emissiveIntensity: 0.45,
    metalness: 0.88,
    roughness: 0.18,
    clearcoat: 0.75,
    clearcoatRoughness: 0.12
  });

  const baseDarkMaterial = new THREE.MeshStandardMaterial({
    color: 0x111827,
    metalness: 0.35,
    roughness: 0.65
  });

  const edgeLineMaterial = new THREE.LineBasicMaterial({
    color: 0x94a3b8,
    transparent: true,
    opacity: 0.35
  });

  const binaryTileActiveMat = new THREE.MeshStandardMaterial({
    color: 0x86efac,
    emissive: 0x16a34a,
    emissiveIntensity: 0.42,
    roughness: 0.35,
    metalness: 0.15
  });

  const binaryTileIdleMat = new THREE.MeshStandardMaterial({
    color: 0x1e3a2f,
    emissive: 0x052e16,
    emissiveIntensity: 0.15,
    roughness: 0.6,
    metalness: 0.1
  });

  const HEX_RADIUS = 0.96;
  const PITCH_RADIUS = 1.05;
  const SECTOR_DEPTH = 0.14;
  const Y_HEIGHT = 0.24;

  const sharedHexBaseGeom = createHexBaseGeometry(HEX_RADIUS, 0.08);
  const sharedBaseEdges = new THREE.EdgesGeometry(sharedHexBaseGeom, 15);
  const sharedYGeom = createYJunctionGeometry(HEX_RADIUS * 0.94, 0.11, Y_HEIGHT);
  const sharedSectorGeoms = {
    [-1]: createRhombusSectorGeometry(HEX_RADIUS, 0.04, SECTOR_DEPTH, -1),
    0: createRhombusSectorGeometry(HEX_RADIUS, 0.04, SECTOR_DEPTH, 0),
    1: createRhombusSectorGeometry(HEX_RADIUS, 0.04, SECTOR_DEPTH, 1)
  };
  const sharedSectorEdges = {
    [-1]: new THREE.EdgesGeometry(sharedSectorGeoms[-1], 20),
    0: new THREE.EdgesGeometry(sharedSectorGeoms[0], 20),
    1: new THREE.EdgesGeometry(sharedSectorGeoms[1], 20)
  };

  const rootGroup = new THREE.Group();
  scene.add(rootGroup);

  let currentMode = initialMode;
  let cells = [];
  let binaryTiles = [];
  let interactiveMeshes = [];
  let energyWaves = [];
  let totalEnergyDeltaV2 = 0;
  let lastTransitionCost = 0;
  let isClockRunning = false;
  let clockAccumulator = 0;
  let clockCursor = 0;

  /**
   * Updates materials and ambient lighting when the host toggles light/dark mode.
   */
  function syncTheme() {
    const isLight = document.documentElement.classList.contains('light');
    hemiLight.intensity = isLight ? 1.35 : 0.95;
    baseDarkMaterial.color.setHex(isLight ? 0x334155 : 0x0f172a);
    edgeLineMaterial.color.setHex(isLight ? 0x475569 : 0x94a3b8);
    edgeLineMaterial.opacity = isLight ? 0.45 : 0.32;
  }

  /**
   * Creates a single tripartite hexagonal ternary CLB cell (T-CLB) with three
   * interactive rhombus sectors and a central 120-degree golden Y-junction.
   */
  function createTernaryHexCell(cellMeta) {
    const cellGroup = new THREE.Group();
    cellGroup.position.set(cellMeta.x, 0, cellMeta.z);

    const baseMesh = new THREE.Mesh(sharedHexBaseGeom, baseDarkMaterial);
    baseMesh.position.y = -0.06;
    cellGroup.add(baseMesh);

    const baseWire = new THREE.LineSegments(sharedBaseEdges, edgeLineMaterial);
    baseWire.position.y = -0.06;
    cellGroup.add(baseWire);

    const yMesh = new THREE.Mesh(sharedYGeom, goldMaterial);
    yMesh.position.y = 0.02;
    cellGroup.add(yMesh);

    const sectors = {};
    for (const s of TRIT_STATES) {
      const cfg = SECTOR_CONFIG[s];
      const mat = new THREE.MeshPhysicalMaterial({
        color: cfg.inactiveColor,
        emissive: 0x000000,
        emissiveIntensity: 0,
        metalness: 0.18,
        roughness: 0.28,
        clearcoat: 0.45
      });

      const sectorMesh = new THREE.Mesh(sharedSectorGeoms[s], mat);
      sectorMesh.position.y = 0.02;
      sectorMesh.userData = { cellIndex: cellMeta.index, isHexCell: true };

      const sectorWire = new THREE.LineSegments(sharedSectorEdges[s], edgeLineMaterial);
      sectorMesh.add(sectorWire);

      cellGroup.add(sectorMesh);
      interactiveMeshes.push(sectorMesh);
      sectors[s] = { mesh: sectorMesh, mat, targetY: 0.02 };
    }

    const cell = {
      ...cellMeta,
      group: cellGroup,
      yMesh,
      sectors,
      state: cellMeta.initialState ?? 0
    };
    applyCellVisuals(cell, true);
    rootGroup.add(cellGroup);
    return cell;
  }

  /**
   * Updates sector materials and target elevations for a ternary cell's state.
   */
  function applyCellVisuals(cell, immediate = false) {
    for (const s of TRIT_STATES) {
      const sector = cell.sectors[s];
      const cfg = SECTOR_CONFIG[s];
      const active = cell.state === s;
      sector.mat.color.setHex(active ? cfg.activeColor : cfg.inactiveColor);
      sector.mat.emissive.setHex(active ? cfg.activeEmissive : 0x000000);
      sector.mat.emissiveIntensity = active ? 0.65 : 0;
      sector.targetY = active ? 0.11 : 0.015;
      if (immediate) {
        sector.mesh.position.y = sector.targetY;
      }
    }
  }

  /**
   * Spawns a transient expanding ring indicating dynamic switching energy (0.25 or 1.00 Vdd^2).
   */
  function spawnEnergyWave(x, z, cost) {
    const isFullSwing = cost >= 1.0;
    const ringGeom = new THREE.RingGeometry(0.28, 0.36, 6);
    ringGeom.rotateX(-Math.PI / 2);
    ringGeom.rotateY(Math.PI / 6);
    const ringMat = new THREE.MeshBasicMaterial({
      color: isFullSwing ? 0xf97316 : 0x38bdf8,
      transparent: true,
      opacity: 0.9,
      side: THREE.DoubleSide
    });
    const ring = new THREE.Mesh(ringGeom, ringMat);
    ring.position.set(x, 0.3, z);
    rootGroup.add(ring);
    energyWaves.push({ mesh: ring, mat: ringMat, geom: ringGeom, age: 0 });
  }

  /**
   * Cycles a ternary cell through {-1 -> 0 -> +1 -> -1} and logs delta-V^2 cost.
   */
  function cycleCellState(cell) {
    const prev = cell.state;
    const next = prev === -1 ? 0 : prev === 0 ? 1 : -1;
    cell.state = next;

    // Half-swing (0 <-> +/-1) dissipates 0.25 Vdd^2; full-swing (-1 <-> +1) dissipates 1.00 Vdd^2.
    const cost = Math.abs(next - prev) === 2 ? 1.0 : 0.25;
    totalEnergyDeltaV2 += cost;
    lastTransitionCost = cost;
    applyCellVisuals(cell, false);
    spawnEnergyWave(cell.x, cell.z, cost);
    emitTelemetry();
  }

  function emitTelemetry() {
    if (!onTelemetryChange) return;
    const t = computeTelemetry(cells, lastTransitionCost);
    onTelemetryChange({
      mode: currentMode,
      cellCount: cells.length,
      decimal: t.decimal,
      counts: t.counts,
      totalEnergyDeltaV2,
      lastTransitionCost,
      statesString: cells.map((c) => (c.state === 1 ? '+' : c.state === -1 ? '-' : '0')).join('')
    });
  }

  /**
   * Clears existing meshes from the scene root before building a new geometry mode.
   */
  function clearSceneGroup() {
    for (const w of energyWaves) {
      w.geom.dispose();
      w.mat.dispose();
    }
    energyWaves = [];
    for (const c of cells) {
      for (const s of TRIT_STATES) {
        c.sectors[s].mat.dispose();
      }
    }
    cells = [];
    binaryTiles = [];
    interactiveMeshes = [];
    while (rootGroup.children.length > 0) {
      rootGroup.remove(rootGroup.children[0]);
    }
  }

  /**
   * Resets camera framing for the active geometric mode.
   */
  function resetCameraForMode(mode) {
    controls.target.set(0, 0, 0);
    if (mode === 'cell') {
      camera.position.set(0, 3.2, 3.4);
    } else if (mode === 'tryte6') {
      camera.position.set(0, 6.2, 6.2);
    } else if (mode === 'word21') {
      camera.position.set(0, 10.6, 10.2);
    } else {
      camera.position.set(0, 8.2, 8.8);
    }
    controls.update();
  }

  /**
   * Builds one of the four architectural views: 'cell', 'tryte6', 'word21', or 'compare'.
   */
  function setMode(mode) {
    currentMode = mode;
    totalEnergyDeltaV2 = 0;
    lastTransitionCost = 0;
    clearSceneGroup();

    if (mode === 'cell') {
      cells.push(createTernaryHexCell({ index: 0, x: 0, z: 0, initialState: 0 }));
    } else if (mode === 'tryte6') {
      const coords = getRosetteCoords(0, 0);
      const pattern = [0, 1, -1, 0, 1, -1, 1];
      coords.forEach((c, idx) => {
        const { x, z } = axialToXZ(c.q, c.r, PITCH_RADIUS);
        cells.push(createTernaryHexCell({ index: idx, x, z, initialState: pattern[idx] }));
      });
    } else if (mode === 'word21') {
      const coords = getWord21Coords();
      coords.forEach((c, idx) => {
        const { x, z } = axialToXZ(c.q, c.r, PITCH_RADIUS);
        const seed = ((idx % 3) - 1);
        cells.push(createTernaryHexCell({ index: idx, x, z, initialState: seed }));
      });
      // Central macro Y-bus inside the origin cavity linking the 3 rosettes at 120 deg.
      const macroYGeom = createYJunctionGeometry(HEX_RADIUS * 2.1, 0.18, 0.34);
      const macroY = new THREE.Mesh(macroYGeom, goldMaterial);
      macroY.position.set(0, 0.04, 0);
      rootGroup.add(macroY);
    } else if (mode === 'compare') {
      // Left bank: 4x4 orthogonal square binary FPGA grid (inspired by user's first image).
      const boxGeom = new THREE.BoxGeometry(0.95, 0.16, 0.95);
      const boxWireGeom = new THREE.EdgesGeometry(boxGeom, 15);
      const squareGroup = new THREE.Group();
      squareGroup.position.set(-3.8, 0, 0);

      for (let row = 0; row < 4; row++) {
        for (let col = 0; col < 4; col++) {
          const active = (row + col) % 2 === 0 || (row === 0 && col === 3);
          const tile = new THREE.Mesh(boxGeom, active ? binaryTileActiveMat : binaryTileIdleMat);
          const x = (col - 1.5) * 1.16;
          const z = (row - 1.5) * 1.16;
          tile.position.set(x, active ? 0.12 : 0.06, z);
          tile.userData = { isBinaryTile: true, active, index: row * 4 + col };
          const wire = new THREE.LineSegments(boxWireGeom, edgeLineMaterial);
          tile.add(wire);
          squareGroup.add(tile);
          binaryTiles.push(tile);
          interactiveMeshes.push(tile);
        }
      }
      rootGroup.add(squareGroup);

      // Right bank: 7-cell hexagonal rosette with 120-degree Y-junctions.
      const coords = getRosetteCoords(0, 0);
      const hexOffsetX = 3.5;
      const pattern = [0, 1, -1, 0, 1, -1, 1];
      coords.forEach((c, idx) => {
        const { x, z } = axialToXZ(c.q, c.r, PITCH_RADIUS * 0.92);
        const cell = createTernaryHexCell({
          index: idx,
          x: x + hexOffsetX,
          z,
          initialState: pattern[idx]
        });
        cell.group.scale.setScalar(0.92);
      });
    }

    resetCameraForMode(mode);
    emitTelemetry();
  }

  // Raycaster interaction: click any hex cell to cycle its trit, or binary square to toggle bit.
  const raycaster = new THREE.Raycaster();
  const pointer = new THREE.Vector2();
  let pointerDownPos = { x: 0, y: 0 };

  function handlePointerDown(ev) {
    pointerDownPos = { x: ev.clientX, y: ev.clientY };
  }

  function handlePointerUp(ev) {
    const dx = ev.clientX - pointerDownPos.x;
    const dy = ev.clientY - pointerDownPos.y;
    if (Math.hypot(dx, dy) > 6) return; // Ignore orbit drag gestures.

    const rect = canvas.getBoundingClientRect();
    pointer.x = ((ev.clientX - rect.left) / rect.width) * 2 - 1;
    pointer.y = -((ev.clientY - rect.top) / rect.height) * 2 + 1;

    raycaster.setFromCamera(pointer, camera);
    const hits = raycaster.intersectObjects(interactiveMeshes, false);
    if (hits.length === 0) return;

    const hitData = hits[0].object.userData;
    if (hitData.isHexCell) {
      const targetCell = cells[hitData.cellIndex];
      if (targetCell) cycleCellState(targetCell);
    } else if (hitData.isBinaryTile) {
      const tile = binaryTiles[hitData.index];
      if (tile) {
        tile.userData.active = !tile.userData.active;
        tile.material = tile.userData.active ? binaryTileActiveMat : binaryTileIdleMat;
        tile.position.y = tile.userData.active ? 0.12 : 0.06;
        // Traditional binary switching always consumes full 1.00 Vdd^2 rail swing.
        totalEnergyDeltaV2 += 1.0;
        lastTransitionCost = 1.0;
        emitTelemetry();
      }
    }
  }

  canvas.addEventListener('pointerdown', handlePointerDown);
  canvas.addEventListener('pointerup', handlePointerUp);

  // Resize handling
  function handleResize() {
    const w = container.clientWidth || window.innerWidth || 640;
    const h = container.clientHeight || window.innerHeight || 320;
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    renderer.setSize(w, h, false);
  }
  const resizeObserver = new ResizeObserver(handleResize);
  resizeObserver.observe(container);
  window.addEventListener('resize', handleResize);
  handleResize();

  // Animation loop with visibility-aware pausing (contentvisibilityautostatechange + IO fallback).
  let rafId = null;
  let lastTime = performance.now();
  let isPaused = false;

  function animate(now) {
    if (isPaused) return;
    rafId = requestAnimationFrame(animate);

    const dt = Math.min((now - lastTime) / 1000, 0.1);
    lastTime = now;

    if (isClockRunning && cells.length > 0) {
      clockAccumulator += dt;
      if (clockAccumulator >= 0.35) {
        clockAccumulator = 0;
        const target = cells[clockCursor % cells.length];
        cycleCellState(target);
        clockCursor = (clockCursor + 1) % cells.length;
      }
    }

    // Smoothly interpolate sector elevation
    for (const c of cells) {
      for (const s of TRIT_STATES) {
        const sec = c.sectors[s];
        sec.mesh.position.y += (sec.targetY - sec.mesh.position.y) * Math.min(1, dt * 12);
      }
    }

    // Animate energy pulse rings
    for (let i = energyWaves.length - 1; i >= 0; i--) {
      const w = energyWaves[i];
      w.age += dt;
      const progress = w.age / 0.65;
      if (progress >= 1) {
        rootGroup.remove(w.mesh);
        w.geom.dispose();
        w.mat.dispose();
        energyWaves.splice(i, 1);
      } else {
        const scale = 1 + progress * 2.2;
        w.mesh.scale.set(scale, 1, scale);
        w.mat.opacity = 0.85 * (1 - progress);
      }
    }

    controls.update();
    renderer.render(scene, camera);
  }

  function startRenderLoop() {
    if (!isPaused && rafId === null) {
      lastTime = performance.now();
      rafId = requestAnimationFrame(animate);
    }
  }

  function stopRenderLoop() {
    if (rafId !== null) {
      cancelAnimationFrame(rafId);
      rafId = null;
    }
  }

  // Modern content-visibility lifecycle hook with IntersectionObserver fallback
  const hasContentVisibility = 'contentVisibility' in document.documentElement.style;
  let fallbackObserver = null;

  function onContentVisibilityChange(event) {
    if (event.skipped) {
      isPaused = true;
      stopRenderLoop();
    } else {
      isPaused = false;
      startRenderLoop();
    }
  }
  container.addEventListener('contentvisibilityautostatechange', onContentVisibilityChange);

  if (!hasContentVisibility && typeof IntersectionObserver !== 'undefined') {
    fallbackObserver = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          isPaused = !entry.isIntersecting;
          if (isPaused) stopRenderLoop();
          else startRenderLoop();
        }
      },
      { rootMargin: '200px' }
    );
    fallbackObserver.observe(container);
  }

  /**
   * Plots a signed decimal integer across the hexagonal cells in balanced ternary,
   * expanding the fabric mode automatically if the magnitude exceeds current capacity.
   */
  function setDecimalValue(rawInput) {
    let n = typeof rawInput === 'bigint' ? rawInput : BigInt(rawInput);
    const MAX_TRYTE7 = 1093n;
    const MAX_WORD21 = 5230176601n;
    if (n > MAX_WORD21) n = MAX_WORD21;
    if (n < -MAX_WORD21) n = -MAX_WORD21;

    const absN = n < 0n ? -n : n;
    if (absN > 1n && currentMode === 'cell') {
      setMode(absN <= MAX_TRYTE7 ? 'tryte6' : 'word21');
    } else if (absN > MAX_TRYTE7 && (currentMode === 'tryte6' || currentMode === 'compare')) {
      setMode('word21');
    }

    const trits = decimalToBalancedTrits(n, cells.length);
    for (let i = 0; i < cells.length; i++) {
      const cell = cells[i];
      const prev = cell.state;
      const next = trits[i];
      if (prev !== next) {
        cell.state = next;
        const cost = Math.abs(next - prev) === 2 ? 1.0 : 0.25;
        totalEnergyDeltaV2 += cost;
        lastTransitionCost = cost;
        applyCellVisuals(cell, false);
        spawnEnergyWave(cell.x, cell.z, cost);
      }
    }
    emitTelemetry();
    return currentMode;
  }

  window.addEventListener('themechange', syncTheme);
  syncTheme();
  setMode(initialMode);
  startRenderLoop();

  return {
    setMode,
    setDecimalValue,
    resetCamera: () => resetCameraForMode(currentMode),
    toggleClock: (forceState) => {
      isClockRunning = typeof forceState === 'boolean' ? forceState : !isClockRunning;
      return isClockRunning;
    },
    destroy: () => {
      stopRenderLoop();
      resizeObserver.disconnect();
      window.removeEventListener('resize', handleResize);
      if (fallbackObserver) fallbackObserver.disconnect();
      container.removeEventListener('contentvisibilityautostatechange', onContentVisibilityChange);
      window.removeEventListener('themechange', syncTheme);
      canvas.removeEventListener('pointerdown', handlePointerDown);
      canvas.removeEventListener('pointerup', handlePointerUp);
      renderer.dispose();
    }
  };
}
