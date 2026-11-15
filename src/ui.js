import { mountTernaryFpgaScene } from './scene.js';

const MODE_DESCRIPTIONS = {
  cell: 'Hexagon partitioned by a 120-degree Y-junction: each rhombus encodes -1, 0, or +1.',
  tryte6: '7-cell hexagonal rosette: 6 data trits surrounding a central carry core.',
  word21: '21-trit Word21 fabric: 3 rosettes of 7 cells joined by the central Y-bus.',
  compare: '90-degree orthogonal square matrix on the left compared to 120-degree Hex-Y fabric on the right.'
};

/**
 * Attaches the 3D scene controller to the DOM controls and telemetry readout.
 */
export function initTernaryFpgaUi() {
  const container = document.getElementById('viewport-container');
  const canvas = document.getElementById('fpga-canvas');
  const modeButtons = Array.from(document.querySelectorAll('[data-mode]'));
  const clockBtn = document.getElementById('btn-clock');
  const resetBtn = document.getElementById('btn-reset');
  const modeNoteEl = document.getElementById('mode-note');
  const decimalEl = document.getElementById('stat-decimal');
  const vectorEl = document.getElementById('stat-vector');
  const energyEl = document.getElementById('stat-energy');

  if (!container || !canvas) return null;

  const controller = mountTernaryFpgaScene({
    container,
    canvas,
    initialMode: 'cell',
    onTelemetryChange: (t) => {
      if (decimalEl) decimalEl.textContent = t.decimal;
      if (vectorEl) {
        vectorEl.textContent = t.statesString.length > 14
          ? `${t.statesString.slice(0, 7)}..${t.statesString.slice(-7)}`
          : t.statesString;
        vectorEl.title = `Trits: ${t.statesString}`;
      }
      if (energyEl) {
        energyEl.textContent = `${t.totalEnergyDeltaV2.toFixed(2)} Vdd^2`;
      }
    }
  });

  function setActiveButton(selectedMode) {
    for (const btn of modeButtons) {
      const isSelected = btn.getAttribute('data-mode') === selectedMode;
      btn.setAttribute('aria-pressed', String(isSelected));
      btn.classList.toggle('bg-[var(--primary)]', isSelected);
      btn.classList.toggle('text-[var(--primary-foreground)]', isSelected);
      btn.classList.toggle('border-[var(--primary)]', isSelected);
      btn.classList.toggle('bg-transparent', !isSelected);
      btn.classList.toggle('text-[var(--muted-foreground)]', !isSelected);
      btn.classList.toggle('border-[var(--card-border)]', !isSelected);
    }
    if (modeNoteEl) {
      modeNoteEl.textContent = MODE_DESCRIPTIONS[selectedMode] || '';
    }
  }

  for (const btn of modeButtons) {
    btn.addEventListener('click', () => {
      const mode = btn.getAttribute('data-mode');
      controller.setMode(mode);
      setActiveButton(mode);
    });
  }

  if (clockBtn) {
    clockBtn.addEventListener('click', () => {
      const running = controller.toggleClock();
      clockBtn.textContent = running ? 'Pause Pulse' : 'Ternary Pulse';
      clockBtn.setAttribute('aria-pressed', String(running));
    });
  }

  if (resetBtn) {
    resetBtn.addEventListener('click', () => {
      controller.resetCamera();
    });
  }

  setActiveButton('cell');
  return controller;
}

if (typeof document !== 'undefined') {
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initTernaryFpgaUi, { once: true });
  } else {
    initTernaryFpgaUi();
  }
}
