// Red Square Keyrox TKL - Full Windows Parity macOS App Controller with Profile Persistence

(function() {
  'use strict';

  // Profile Storage State
  const defaultProfiles = {
    0: { mode: 1, dir: 0, brightness: 4, speed: 2, fgColor: { r: 255, g: 0, b: 0 }, bgColor: { r: 0, g: 102, b: 255 }, matrixColor: { r: 0, g: 255, b: 0 }, remaps: {}, matrixColors: {} },
    1: { mode: 0, dir: 0, brightness: 4, speed: 2, fgColor: { r: 0, g: 255, b: 0 }, bgColor: { r: 255, g: 0, b: 0 }, matrixColor: { r: 0, g: 255, b: 0 }, remaps: {}, matrixColors: {} },
    2: { mode: 8, dir: 0, brightness: 3, speed: 2, fgColor: { r: 0, g: 102, b: 255 }, bgColor: { r: 255, g: 255, b: 0 }, matrixColor: { r: 0, g: 255, b: 0 }, remaps: {}, matrixColors: {} },
    3: { mode: 9, dir: 0, brightness: 4, speed: 1, fgColor: { r: 255, g: 0, b: 255 }, bgColor: { r: 0, g: 255, b: 255 }, matrixColor: { r: 0, g: 255, b: 0 }, remaps: {}, matrixColors: {} }
  };

  let profiles = defaultProfiles;
  try {
    const saved = localStorage.getItem('keyrox_profiles');
    if (saved) {
      profiles = Object.assign({}, defaultProfiles, JSON.parse(saved));
    }
  } catch (e) {
    console.error('[Keyrox] Error reading profiles from localStorage', e);
  }

  // Active Runtime State
  const state = {
    connected: false,
    currentProfile: 0,
    currentMode: 1,
    currentDir: 0,
    currentBrightness: 4,
    currentSpeed: 2,
    activeLayer: 'fg', // 'fg' | 'bg'
    fgColor: { r: 255, g: 0, b: 0 },
    bgColor: { r: 0, g: 102, b: 255 },
    matrixColor: { r: 0, g: 255, b: 0 },
    selectedKeys: new Set(),
    activeRemapKey: null,
    activeRemapType: 'single',
    remaps: new Map(), // keyIdx -> { type, label, code }
    keyCustomColors: new Map() // keyIdx -> { r, g, b }
  };

  // DOM Elements
  const canvas = document.getElementById('keyboard-canvas');
  const selectedCountText = document.getElementById('keys-selected-count');
  const modeSelect = document.getElementById('mode-select');
  const sliderBrightness = document.getElementById('slider-brightness');
  const sliderSpeed = document.getElementById('slider-speed');
  const valBrightness = document.getElementById('val-brightness');
  const valSpeed = document.getElementById('val-speed');
  
  // LED Palette elements
  const btnLayerFg = document.getElementById('btn-layer-fg');
  const btnLayerBg = document.getElementById('btn-layer-bg');
  const colorPreview = document.getElementById('color-preview');
  const colorHex = document.getElementById('color-hex');
  const sliderR = document.getElementById('slider-r');
  const sliderG = document.getElementById('slider-g');
  const sliderB = document.getElementById('slider-b');
  const valR = document.getElementById('val-r');
  const valG = document.getElementById('val-g');
  const valB = document.getElementById('val-b');

  // Matrix Palette elements
  const matrixColorPreview = document.getElementById('matrix-color-preview');
  const matrixColorHex = document.getElementById('matrix-color-hex');
  const matrixSliderR = document.getElementById('matrix-slider-r');
  const matrixSliderG = document.getElementById('matrix-slider-g');
  const matrixSliderB = document.getElementById('matrix-slider-b');
  const matrixValR = document.getElementById('matrix-val-r');
  const matrixValG = document.getElementById('matrix-val-g');
  const matrixValB = document.getElementById('matrix-val-b');

  // Remap elements
  const remapKeyName = document.getElementById('remap-key-name');
  const remapKeyCode = document.getElementById('remap-key-code');
  const selectSingleKey = document.getElementById('select-single-key');
  const selectMediaKey = document.getElementById('select-media-key');
  const selectShortcutKey = document.getElementById('select-shortcut-key');
  const remapActiveList = document.getElementById('remap-active-list');

  // Status elements
  const statusDot = document.getElementById('status-dot');
  const statusText = document.getElementById('status-text');
  const infoFw = document.getElementById('info-fw-version');

  // Native Bridge Helper
  function sendToNative(payload) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.keyrox) {
      window.webkit.messageHandlers.keyrox.postMessage(payload);
    } else {
      console.log('[NativeBridge Mock]', payload);
    }
  }

  // Toast Helper
  function showToast(msg) {
    const toast = document.getElementById('toast-notification');
    if (toast) {
      toast.textContent = msg;
      toast.classList.add('show');
      clearTimeout(toast._timer);
      toast._timer = setTimeout(() => toast.classList.remove('show'), 2600);
    }
  }

  // 1. Render Keyboard Keys
  function renderKeyboard() {
    if (!canvas || typeof KEYROX_KEYS === 'undefined') return;
    canvas.innerHTML = '';

    KEYROX_KEYS.forEach(k => {
      const el = document.createElement('div');
      el.className = 'keycap';
      el.id = `key-${k.idx}`;
      el.dataset.idx = k.idx;
      el.dataset.name = k.name;
      el.style.left = `${k.x}px`;
      el.style.top = `${k.y}px`;
      el.style.width = `${k.w}px`;
      el.style.height = `${k.h}px`;

      // Display key name
      let displayName = k.name;
      if (displayName === 'LeftShift' || displayName === 'LeftShif') displayName = 'Shift';
      if (displayName === 'RightShift') displayName = 'Shift';
      if (displayName === 'LeftCtrl') displayName = 'Ctrl';
      if (displayName === 'RightCtrl') displayName = 'Ctrl';
      if (displayName === 'LeftWin') displayName = 'Win';
      if (displayName === 'LeftAlt' || displayName === 'LeftAtl') displayName = 'Alt';
      if (displayName === 'RightAlt') displayName = 'Alt';
      if (displayName === 'Spacebar') displayName = ' ';
      if (displayName === 'PrintScreen') displayName = 'PrtSc';
      if (displayName === 'ScrollLock') displayName = 'ScrLk';
      if (displayName === 'CapsLock') displayName = 'Caps';
      if (displayName === 'Backspace') displayName = '⌫';
      if (displayName === 'Enter') displayName = '↵';
      if (displayName === 'Insert') displayName = 'Ins';
      if (displayName === 'Home') displayName = 'Hm';
      if (displayName === 'PageUp') displayName = 'PgUp';
      if (displayName === 'PageDown') displayName = 'PgDn';
      if (displayName === 'ArrowUp') displayName = '▲';
      if (displayName === 'ArrowDown') displayName = '▼';
      if (displayName === 'ArrowLeft') displayName = '◀';
      if (displayName === 'ArrowRight') displayName = '▶';

      el.textContent = displayName;
      el.title = `${k.name} (HID: 0x${k.val.toString(16).toUpperCase()}, Индекс: ${k.idx})`;

      // Click handler
      el.addEventListener('click', () => {
        const currentActiveTab = document.querySelector('.tab-btn.active')?.dataset.tab;
        if (currentActiveTab === 'remap') {
          setActiveRemapKey(k);
          return;
        }

        if (state.selectedKeys.has(k.idx)) {
          state.selectedKeys.delete(k.idx);
          el.classList.remove('selected');
        } else {
          state.selectedKeys.add(k.idx);
          el.classList.add('selected');
        }
        updateSelectedCount();
      });

      canvas.appendChild(el);
    });

    const defaultKey = KEYROX_KEYS.find(k => k.name === 'Spacebar') || KEYROX_KEYS[0];
    if (defaultKey) setActiveRemapKey(defaultKey);

    if (selectSingleKey) {
      selectSingleKey.innerHTML = '';
      KEYROX_KEYS.forEach(k => {
        const opt = document.createElement('option');
        opt.value = k.val;
        opt.textContent = `${k.name} (0x${k.val.toString(16).toUpperCase()})`;
        selectSingleKey.appendChild(opt);
      });
    }
  }

  function setActiveRemapKey(k) {
    state.activeRemapKey = k;
    if (remapKeyName) remapKeyName.textContent = k.name;
    if (remapKeyCode) remapKeyCode.textContent = `[Индекс: ${k.idx}, HID: 0x${k.val.toString(16).toUpperCase()}]`;

    document.querySelectorAll('.keycap').forEach(el => el.classList.remove('remap-target'));
    const targetEl = document.getElementById(`key-${k.idx}`);
    if (targetEl) targetEl.classList.add('remap-target');

    if (selectSingleKey) selectSingleKey.value = k.val;
  }

  function updateSelectedCount() {
    if (selectedCountText) {
      selectedCountText.textContent = `Выбрано клавиш: ${state.selectedKeys.size}`;
    }
  }

  // 2. Selection Helpers
  function clearSelection() {
    state.selectedKeys.clear();
    document.querySelectorAll('.keycap.selected').forEach(el => el.classList.remove('selected'));
    updateSelectedCount();
  }

  function selectKeysByFilter(filterFn) {
    clearSelection();
    KEYROX_KEYS.forEach(k => {
      if (filterFn(k)) {
        state.selectedKeys.add(k.idx);
        const el = document.getElementById(`key-${k.idx}`);
        if (el) el.classList.add('selected');
      }
    });
    updateSelectedCount();
  }

  document.getElementById('btn-select-all')?.addEventListener('click', () => {
    selectKeysByFilter(() => true);
  });

  document.getElementById('btn-select-clear')?.addEventListener('click', () => {
    clearSelection();
  });

  document.getElementById('btn-select-wasd')?.addEventListener('click', () => {
    const targets = new Set(['W', 'A', 'S', 'D', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight']);
    selectKeysByFilter(k => targets.has(k.name));
  });

  document.getElementById('btn-select-fkeys')?.addEventListener('click', () => {
    selectKeysByFilter(k => k.name.startsWith('F') || ['Esc', 'PrintScreen', 'ScrollLock', 'Pause'].includes(k.name));
  });

  document.getElementById('btn-select-numrow')?.addEventListener('click', () => {
    const nums = new Set(['~', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=']);
    selectKeysByFilter(k => nums.has(k.name));
  });

  // 3. Tab Switching
  document.querySelectorAll('.tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
      document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));

      btn.classList.add('active');
      const targetId = `tab-panel-${btn.dataset.tab}`;
      const panel = document.getElementById(targetId);
      if (panel) panel.classList.add('active');

      if (btn.dataset.tab === 'remap' && state.activeRemapKey) {
        setActiveRemapKey(state.activeRemapKey);
      }
    });
  });

  // 4. Profile Management & Persistence
  function saveCurrentProfile() {
    const p = state.currentProfile;
    profiles[p] = {
      mode: state.currentMode,
      dir: state.currentDir,
      brightness: state.currentBrightness,
      speed: state.currentSpeed,
      fgColor: { ...state.fgColor },
      bgColor: { ...state.bgColor },
      matrixColor: { ...state.matrixColor },
      remaps: Object.fromEntries(state.remaps),
      matrixColors: Object.fromEntries(state.keyCustomColors)
    };

    // 1. Save to browser localStorage
    try {
      localStorage.setItem('keyrox_profiles', JSON.stringify(profiles));
    } catch (e) {
      console.error('Failed to save to localStorage', e);
    }

    // 2. Save to file on macOS filesystem
    sendToNative({
      action: 'saveProfileToFile',
      data: profiles
    });

    // 3. Commit to physical keyboard hardware Flash
    sendToNative({ action: 'saveSettings' });

  }

  function loadProfile(p) {
    state.currentProfile = p;

    // Update active profile button in UI
    document.querySelectorAll('.profile-btn').forEach(btn => {
      btn.classList.toggle('active', parseInt(btn.dataset.profile, 10) === p);
    });

    // 1. Send single profile switch command to hardware
    sendToNative({ action: 'setProfile', profile: p });

    // 2. Query hardware status after MCU completes EEPROM profile switch (150ms)
    setTimeout(() => {
      sendToNative({ action: 'getStatus' });
    }, 150);

    // 3. Restore any profile saved custom colors/remaps from local profiles store
    const prof = profiles[p];
    if (prof) {
      if (prof.fgColor) state.fgColor = { ...prof.fgColor };
      if (prof.bgColor) state.bgColor = { ...prof.bgColor };
      if (prof.matrixColor) state.matrixColor = { ...prof.matrixColor };
      state.remaps.clear();
      if (prof.remaps) {
        Object.entries(prof.remaps).forEach(([k, v]) => state.remaps.set(parseInt(k, 10), v));
      }
      state.keyCustomColors.clear();
      document.querySelectorAll('.keycap').forEach(el => el.style.backgroundColor = '');
      if (prof.matrixColors) {
        Object.entries(prof.matrixColors).forEach(([k, v]) => {
          const idx = parseInt(k, 10);
          state.keyCustomColors.set(idx, v);
          const el = document.getElementById(`key-${idx}`);
          if (el) el.style.backgroundColor = `rgb(${v.r}, ${v.g}, ${v.b})`;
        });
      }
      updatePaletteUI();
      updateMatrixPaletteUI();
      updateRemapList();
    }

    showToast(`Переключено на профиль P${p + 1}`);
  }

  // Profile button clicks
  document.querySelectorAll('.profile-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.profile-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      const p = parseInt(btn.dataset.profile, 10);
      loadProfile(p);
    });
  });

  // Dedicated Save & Load Profile Buttons
  document.getElementById('btn-save-current-profile')?.addEventListener('click', () => {
    saveCurrentProfile();
  });

  document.getElementById('btn-load-current-profile')?.addEventListener('click', () => {
    loadHardwareAndProfileSettings();
  });

  document.getElementById('btn-reload-hardware-settings')?.addEventListener('click', () => {
    loadHardwareAndProfileSettings();
  });

  document.getElementById('btn-status-revive')?.addEventListener('click', () => {
    showToast('⚡ Отправка USB Bus Reset в контроллер...');
    sendToNative({ action: 'reviveDevice' });
  });

  // 5. Lighting Mode & Direction Controls
  modeSelect?.addEventListener('change', () => {
    const mode = parseInt(modeSelect.value, 10);
    state.currentMode = mode;
    sendToNative({ action: 'setMode', mode: mode, dir: state.currentDir });
  });

  document.querySelectorAll('.dir-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.dir-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      const dir = parseInt(btn.dataset.dir, 10);
      state.currentDir = dir;
      sendToNative({ action: 'setDirection', dir });
    });
  });

  sliderBrightness?.addEventListener('input', () => {
    const val = parseInt(sliderBrightness.value, 10);
    state.currentBrightness = val;
    if (valBrightness) valBrightness.textContent = `${val} / 4`;
  });
  sliderBrightness?.addEventListener('change', () => {
    sendToNative({ action: 'setBrightness', value: Number(sliderBrightness.value) });
  });

  sliderSpeed?.addEventListener('input', () => {
    const val = parseInt(sliderSpeed.value, 10);
    state.currentSpeed = val;
    if (valSpeed) valSpeed.textContent = `${val} / 4`;
  });
  sliderSpeed?.addEventListener('change', () => {
    sendToNative({ action: 'setSpeed', value: Number(sliderSpeed.value) });
  });

  document.getElementById('btn-led-off')?.addEventListener('click', () => {
    sendToNative({ action: 'turnOff' });
  });

  document.getElementById('btn-led-on')?.addEventListener('click', () => {
    sendToNative({ action: 'turnOn' });
  });

  // 6. Dual Color Palette (Foreground / Background)
  function rgbToHex(r, g, b) {
    return '#' + [r, g, b].map(x => {
      const hex = x.toString(16);
      return hex.length === 1 ? '0' + hex : hex;
    }).join('').toUpperCase();
  }

  function hexToRgb(hex) {
    const bigint = parseInt(hex.replace('#', ''), 16);
    return {
      r: (bigint >> 16) & 255,
      g: (bigint >> 8) & 255,
      b: bigint & 255
    };
  }

  function updatePaletteUI() {
    const col = state.activeLayer === 'fg' ? state.fgColor : state.bgColor;
    if (colorPreview) colorPreview.style.background = `rgb(${col.r}, ${col.g}, ${col.b})`;
    if (colorHex) colorHex.textContent = rgbToHex(col.r, col.g, col.b);
    if (sliderR) sliderR.value = col.r;
    if (sliderG) sliderG.value = col.g;
    if (sliderB) sliderB.value = col.b;
    if (valR) valR.textContent = col.r;
    if (valG) valG.textContent = col.g;
    if (valB) valB.textContent = col.b;
  }

  btnLayerFg?.addEventListener('click', () => {
    btnLayerFg.classList.add('active');
    btnLayerBg?.classList.remove('active');
    state.activeLayer = 'fg';
    updatePaletteUI();
  });

  btnLayerBg?.addEventListener('click', () => {
    btnLayerBg.classList.add('active');
    btnLayerFg?.classList.remove('active');
    state.activeLayer = 'bg';
    updatePaletteUI();
  });

  function onRgbSliderChange() {
    const r = parseInt(sliderR.value, 10);
    const g = parseInt(sliderG.value, 10);
    const b = parseInt(sliderB.value, 10);
    if (state.activeLayer === 'fg') {
      state.fgColor = { r, g, b };
    } else {
      state.bgColor = { r, g, b };
    }
    updatePaletteUI();
  }

  function applyCurrentColor(mode = state.currentMode) {
    if (![0, 3, 5, 9, 11, 12, 13, 16].includes(mode)) return;
    sendToNative({
      action: 'setColor',
      mode,
      r: state.fgColor.r,
      g: state.fgColor.g,
      b: state.fgColor.b,
      bg_r: state.bgColor.r,
      bg_g: state.bgColor.g,
      bg_b: state.bgColor.b
    });
  }

  sliderR?.addEventListener('input', onRgbSliderChange);
  sliderG?.addEventListener('input', onRgbSliderChange);
  sliderB?.addEventListener('input', onRgbSliderChange);

  [sliderR, sliderG, sliderB].forEach(slider => {
    slider?.addEventListener('change', () => applyCurrentColor());
  });

  document.querySelectorAll('#tab-panel-led .palette-swatches .swatch').forEach(sw => {
    sw.addEventListener('click', () => {
      const rgb = hexToRgb(sw.dataset.color);
      if (state.activeLayer === 'fg') {
        state.fgColor = rgb;
      } else {
        state.bgColor = rgb;
      }
      updatePaletteUI();
      applyCurrentColor();
    });
  });

  document.getElementById('btn-apply-all-color')?.addEventListener('click', () => {
    const color = state.activeLayer === 'fg' ? state.fgColor : state.bgColor;
    sendToNative({ action: 'setColor', ...color });
  });

  document.getElementById('btn-apply-selected-color')?.addEventListener('click', () => {
    if (state.selectedKeys.size === 0) {
      alert('Пожалуйста, выделите хотя бы одну клавишу на клавиатуре.');
      return;
    }
    const color = state.activeLayer === 'fg' ? state.fgColor : state.bgColor;
    applyMatrixColors(state.selectedKeys, color);
  });

  document.getElementById('btn-save-flash')?.addEventListener('click', () => {
    saveCurrentProfile();
  });

  // 7. Key Remap Logic
  document.querySelectorAll('.remap-type-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.remap-type-btn').forEach(b => b.classList.remove('active'));
      document.querySelectorAll('.remap-subpanel').forEach(p => p.classList.remove('active'));

      btn.classList.add('active');
      state.activeRemapType = btn.dataset.type;
      const subpanel = document.getElementById(`subpanel-${btn.dataset.type}`);
      if (subpanel) subpanel.classList.add('active');
    });
  });

  document.getElementById('btn-apply-remap')?.addEventListener('click', () => {
    if (!state.activeRemapKey) return;
    const k = state.activeRemapKey;
    let targetCode = 0;
    let label = '';

    if (state.activeRemapType === 'single') {
      targetCode = parseInt(selectSingleKey.value, 10);
      const opt = selectSingleKey.options[selectSingleKey.selectedIndex];
      label = opt ? opt.textContent : `Key 0x${targetCode.toString(16)}`;
    } else if (state.activeRemapType === 'media') {
      targetCode = parseInt(selectMediaKey.value, 16);
      const opt = selectMediaKey.options[selectMediaKey.selectedIndex];
      label = opt ? opt.textContent : `Media 0x${targetCode.toString(16)}`;
    } else if (state.activeRemapType === 'shortcut') {
      label = selectShortcutKey.options[selectShortcutKey.selectedIndex].textContent;
      targetCode = 0x8000;
    } else if (state.activeRemapType === 'macro') {
      label = 'Custom Macro';
      targetCode = 0x9000;
    } else if (state.activeRemapType === 'disable') {
      targetCode = 0x0000;
      label = 'Отключена (Disabled)';
    }

    state.remaps.set(k.idx, { type: state.activeRemapType, label, code: targetCode });
    sendToNative({
      action: 'setKeyRemap',
      keyIndex: k.idx,
      targetCode: targetCode
    });

    updateRemapList();
    showToast(`Клавиша ${k.name} переназначена: ${label}`);
  });

  document.getElementById('btn-reset-key')?.addEventListener('click', () => {
    if (!state.activeRemapKey) return;
    const k = state.activeRemapKey;
    state.remaps.delete(k.idx);
    sendToNative({
      action: 'setKeyRemap',
      keyIndex: k.idx,
      targetCode: k.val
    });
    updateRemapList();
    showToast(`Клавиша ${k.name} сброшена по умолчанию`);
  });

  document.getElementById('btn-reset-all-remaps')?.addEventListener('click', () => {
    if (confirm('Сбросить все переназначения клавиш в текущем профиле?')) {
      state.remaps.clear();
      sendToNative({ action: 'resetRemap' });
      updateRemapList();
      showToast('Все переназначения сброшены');
    }
  });

  document.getElementById('btn-reset-macros')?.addEventListener('click', () => {
    if (confirm('Очистить все сохраненные макросы?')) {
      sendToNative({ action: 'resetMacro' });
      showToast('Макросы очищены');
    }
  });

  document.getElementById('btn-save-remap-flash')?.addEventListener('click', () => {
    saveCurrentProfile();
  });

  function updateRemapList() {
    if (!remapActiveList) return;
    if (state.remaps.size === 0) {
      remapActiveList.innerHTML = '<div class="remap-empty-state">Нет переназначенных клавиш в текущем профиле. Все клавиши работают по умолчанию.</div>';
      return;
    }

    remapActiveList.innerHTML = '';
    state.remaps.forEach((remap, keyIdx) => {
      const keyInfo = KEYROX_KEYS.find(k => k.idx === keyIdx);
      const row = document.createElement('div');
      row.className = 'remap-item-row';
      row.style.cssText = 'display:flex; justify-content:space-between; padding:3px 0; border-bottom:1px solid #23262f; font-size:11px;';
      row.innerHTML = `<span style="color:#e79b40; font-weight:600;">${keyInfo ? keyInfo.name : 'Key ' + keyIdx}</span> <span>→</span> <span style="color:#ffffff;">${remap.label}</span>`;
      remapActiveList.appendChild(row);
    });
  }

  // 8. Custom Matrix Palette & Painting
  function updateMatrixPaletteUI() {
    const col = state.matrixColor;
    if (matrixColorPreview) matrixColorPreview.style.background = `rgb(${col.r}, ${col.g}, ${col.b})`;
    if (matrixColorHex) matrixColorHex.textContent = rgbToHex(col.r, col.g, col.b);
    if (matrixSliderR) matrixSliderR.value = col.r;
    if (matrixSliderG) matrixSliderG.value = col.g;
    if (matrixSliderB) matrixSliderB.value = col.b;
    if (matrixValR) matrixValR.textContent = col.r;
    if (matrixValG) matrixValG.textContent = col.g;
    if (matrixValB) matrixValB.textContent = col.b;
  }

  function onMatrixRgbSliderChange() {
    const r = parseInt(matrixSliderR.value, 10);
    const g = parseInt(matrixSliderG.value, 10);
    const b = parseInt(matrixSliderB.value, 10);
    state.matrixColor = { r, g, b };
    updateMatrixPaletteUI();
  }

  matrixSliderR?.addEventListener('input', onMatrixRgbSliderChange);
  matrixSliderG?.addEventListener('input', onMatrixRgbSliderChange);
  matrixSliderB?.addEventListener('input', onMatrixRgbSliderChange);

  document.querySelectorAll('#tab-panel-custom .palette-swatches .swatch').forEach(sw => {
    sw.addEventListener('click', () => {
      state.matrixColor = hexToRgb(sw.dataset.color);
      updateMatrixPaletteUI();
    });
  });

  function applyMatrixColors(keys, color) {
    for (const idx of keys) {
      if (color) state.keyCustomColors.set(idx, { ...color });
      else state.keyCustomColors.delete(idx);
      const el = document.getElementById("key-" + idx);
      if (el) el.style.backgroundColor = color ? "rgb(" + [color.r, color.g, color.b].join(",") + ")" : "";
    }
    const colors = new Array(KEYROX_KEYS.length);
    KEYROX_KEYS.forEach(({ idx }) => {
      colors[idx] = state.keyCustomColors.get(idx) || { r: 0, g: 0, b: 0 };
    });
    sendToNative({ action: 'setMatrix', colors });
  }

  document.getElementById('btn-matrix-apply')?.addEventListener('click', () => {
    if (state.selectedKeys.size === 0) {
      alert('Пожалуйста, выделите хотя бы одну клавишу на клавиатуре.');
      return;
    }
    applyMatrixColors(state.selectedKeys, state.matrixColor);
  });

  document.getElementById('btn-matrix-all')?.addEventListener('click', () => {
    applyMatrixColors(KEYROX_KEYS.map(key => key.idx), state.matrixColor);
  });

  document.getElementById('btn-matrix-clear-sel')?.addEventListener('click', () => {
    if (state.selectedKeys.size > 0) applyMatrixColors(state.selectedKeys, null);
  });

  document.getElementById('btn-matrix-clear-all')?.addEventListener('click', () => {
    applyMatrixColors(KEYROX_KEYS.map(key => key.idx), null);
  });

  document.getElementById('btn-matrix-save')?.addEventListener('click', () => {
    saveCurrentProfile();
  });

  // 9. Settings Tab Controls
  document.getElementById('btn-restore-defaults')?.addEventListener('click', () => {
    if (confirm('Сбросить все настройки клавиатуры до заводских по умолчанию?')) {
      sendToNative({ action: 'restoreDefaults' });
      document.querySelectorAll('.keycap').forEach(el => el.style.backgroundColor = '');
      clearSelection();
      state.remaps.clear();
      updateRemapList();
      showToast('Заводские настройки восстановлены');
    }
  });

  document.getElementById('btn-reset-led')?.addEventListener('click', () => {
    sendToNative({ action: 'resetLed' });
    if (modeSelect) modeSelect.value = "1";
    if (sliderBrightness) sliderBrightness.value = 4;
    if (sliderSpeed) sliderSpeed.value = 2;
    if (valBrightness) valBrightness.textContent = '4 / 4';
    if (valSpeed) valSpeed.textContent = '2 / 4';
    showToast('Световые эффекты сброшены на Wave');
  });

  document.getElementById('btn-reset-led-custom')?.addEventListener('click', () => {
    state.keyCustomColors.clear();
    document.querySelectorAll('.keycap').forEach(el => el.style.backgroundColor = '');
    sendToNative({ action: 'resetLedCustom' });
  });

  document.getElementById('btn-reset-macro-settings')?.addEventListener('click', () => {
    sendToNative({ action: 'resetMacro' });
    showToast('Макросы очищены');
  });

  // Backup & File Export/Import
  document.getElementById('btn-export-profiles')?.addEventListener('click', () => {
    sendToNative({
      action: 'exportProfilesToFile',
      data: profiles
    });
  });

  document.getElementById('btn-import-profiles')?.addEventListener('click', () => {
    sendToNative({ action: 'importProfilesFromFile' });
  });

  document.getElementById('btn-reveal-finder')?.addEventListener('click', () => {
    sendToNative({ action: 'revealProfilesInFinder' });
  });

  // App Info & Updates
  document.getElementById('btn-check-updates-ui')?.addEventListener('click', () => {
    sendToNative({ action: 'checkForUpdates' });
  });

  document.getElementById('btn-open-github-ui')?.addEventListener('click', () => {
    sendToNative({ action: 'openUrl', url: 'https://github.com/sl1mus/keyrox-mac' });
  });

  document.getElementById('btn-show-about-ui')?.addEventListener('click', () => {
    sendToNative({ action: 'showAbout' });
  });

  // Watchdog Background Daemon Toggle
  let watchdogInstalled = false;
  let watchdogRunning = false;

  document.getElementById('btn-toggle-watchdog')?.addEventListener('click', () => {
    if (watchdogInstalled || watchdogRunning) {
      showToast('Остановка и удаление фоновой службы...');
      sendToNative({ action: 'uninstallWatchdog' });
    } else {
      showToast('Установка системного фонового Watchdog (24/7)...');
      sendToNative({ action: 'installWatchdog' });
    }
  });

  // 10. Window Minimize, Maximize & Close
  document.getElementById('btn-minimize')?.addEventListener('click', () => {
    sendToNative({ action: 'minimizeWindow' });
  });

  document.getElementById('btn-maximize')?.addEventListener('click', () => {
    sendToNative({ action: 'maximizeWindow' });
  });

  document.getElementById('btn-close')?.addEventListener('click', () => {
    sendToNative({ action: 'closeWindow' });
  });

  // 11. Native Callbacks & Hardware Sync
  let initialHardwareSynced = false;
  let userRequestedReload = false;

  function loadHardwareAndProfileSettings() {
    userRequestedReload = true;
    initialHardwareSynced = false;
    showToast('Считывание настроек с клавиатуры...');
    sendToNative({ action: 'loadProfilesFromFile' });
    sendToNative({ action: 'getStatus' });
  }

  window.onDeviceStatus = function(status) {
    if (!status || !status.connected) {
      state.connected = false;
      if (statusDot) statusDot.className = 'status-dot';
      if (statusText) statusText.textContent = 'Отключено — подключите Red Square Keyrox TKL';
      return;
    }

    state.connected = true;
    if (statusDot) statusDot.className = 'status-dot connected';
    if (statusText) {
      statusText.textContent = `Подключено — Red Square Keyrox TKL (FW: ${status.fw || 'GK8911M'})`;
    }
    if (infoFw && status.fw) {
      const cleanFw = status.fw.replace(/PID2511-104K_/, '');
      infoFw.textContent = cleanFw;
      infoFw.title = status.fw;
    }

    const prevProfile = state.currentProfile;
    const hasPreset = Number.isInteger(status.profile);
    if (!hasPreset) document.querySelectorAll('.profile-btn').forEach(btn => btn.classList.remove('active'));
    else if (status.profile === prevProfile) {
      document.querySelectorAll('.profile-btn').forEach(btn => btn.classList.toggle('active', Number(btn.dataset.profile) === status.profile));
    }

    document.querySelectorAll('.dir-btn').forEach(btn => {
      const verticalOnly = [7, 14].includes(status.mode);
      btn.disabled = status.mode !== 1 && (!verticalOnly || Number(btn.dataset.dir) < 2);
    });
    if (sliderSpeed) sliderSpeed.disabled = [0, 4].includes(status.mode);
    if (sliderBrightness) sliderBrightness.disabled = status.mode === 4;

    // 1. Initial full hardware sync or hardware profile switch or manual user reload
    if (!initialHardwareSynced || (hasPreset && status.profile !== prevProfile)) {
      initialHardwareSynced = true;
      if (hasPreset) {
        state.currentProfile = status.profile;
        document.querySelectorAll('.profile-btn').forEach(btn => {
          btn.classList.toggle('active', parseInt(btn.dataset.profile, 10) === status.profile);
        });
      }

      // Sync active hardware lighting settings
      if (status.mode !== undefined && modeSelect) {
        modeSelect.value = status.mode.toString();
        state.currentMode = status.mode;
      }
      if (status.brightness !== undefined && sliderBrightness) {
        state.currentBrightness = status.brightness;
        sliderBrightness.value = status.brightness;
        if (valBrightness) valBrightness.textContent = `${status.brightness} / 4`;
      }
      if (status.speed !== undefined && sliderSpeed) {
        state.currentSpeed = status.speed;
        sliderSpeed.value = status.speed;
        if (valSpeed) valSpeed.textContent = `${status.speed} / 4`;
      }

      // Restore profile custom colors/remaps without overriding live hardware mode/brightness/speed
      const prof = profiles[state.currentProfile] || defaultProfiles[state.currentProfile];
      if (prof) {
        if (prof.fgColor) state.fgColor = { ...prof.fgColor };
        if (prof.bgColor) state.bgColor = { ...prof.bgColor };
        if (prof.matrixColor) state.matrixColor = { ...prof.matrixColor };
        if (prof.dir !== undefined) {
          state.currentDir = prof.dir;
          document.querySelectorAll('.dir-btn').forEach(btn => {
            btn.classList.toggle('active', parseInt(btn.dataset.dir, 10) === state.currentDir);
          });
        }
        if (prof.remaps) {
          state.remaps.clear();
          Object.entries(prof.remaps).forEach(([k, v]) => state.remaps.set(parseInt(k, 10), v));
          updateRemapList();
        }
        if (prof.matrixColors) {
          state.keyCustomColors.clear();
          document.querySelectorAll('.keycap').forEach(el => el.style.backgroundColor = '');
          Object.entries(prof.matrixColors).forEach(([k, v]) => {
            const idx = parseInt(k, 10);
            state.keyCustomColors.set(idx, v);
            const el = document.getElementById(`key-${idx}`);
            if (el) el.style.backgroundColor = `rgb(${v.r}, ${v.g}, ${v.b})`;
          });
        }
        updatePaletteUI();
        updateMatrixPaletteUI();
      }

      if (userRequestedReload) {
        showToast(`Загружен профиль P${state.currentProfile + 1} и текущие настройки!`);
        userRequestedReload = false;
      }
      return;
    }

    // 2. Periodic poll: update hardware values only if not currently focused by user
    if (status.mode !== undefined && status.mode !== state.currentMode) {
      state.currentMode = status.mode;
      if (modeSelect) modeSelect.value = status.mode.toString();
    }
    if (status.brightness !== undefined && status.brightness !== state.currentBrightness && document.activeElement !== sliderBrightness) {
      state.currentBrightness = status.brightness;
      if (sliderBrightness) sliderBrightness.value = status.brightness;
      if (valBrightness) valBrightness.textContent = `${status.brightness} / 4`;
    }
    if (status.speed !== undefined && status.speed !== state.currentSpeed && document.activeElement !== sliderSpeed) {
      state.currentSpeed = status.speed;
      if (sliderSpeed) sliderSpeed.value = status.speed;
      if (valSpeed) valSpeed.textContent = `${status.speed} / 4`;
    }
  };

  window.onProfilesLoaded = function(loaded) {
    if (loaded && typeof loaded === 'object') {
      profiles = Object.assign({}, defaultProfiles, loaded);
      console.log('[Keyrox] Profiles restored from disk', profiles);
      if (initialHardwareSynced) {
        // Apply saved colors/remaps for the active hardware profile
        const prof = profiles[state.currentProfile];
        if (prof) {
          if (prof.remaps) {
            state.remaps.clear();
            Object.entries(prof.remaps).forEach(([k, v]) => state.remaps.set(parseInt(k, 10), v));
            updateRemapList();
          }
          if (prof.matrixColors) {
            state.keyCustomColors.clear();
            document.querySelectorAll('.keycap').forEach(el => el.style.backgroundColor = '');
            Object.entries(prof.matrixColors).forEach(([k, v]) => {
              const idx = parseInt(k, 10);
              state.keyCustomColors.set(idx, v);
              const el = document.getElementById(`key-${idx}`);
              if (el) el.style.backgroundColor = `rgb(${v.r}, ${v.g}, ${v.b})`;
            });
          }
          if (prof.fgColor) state.fgColor = { ...prof.fgColor };
          if (prof.bgColor) state.bgColor = { ...prof.bgColor };
          if (prof.matrixColor) state.matrixColor = { ...prof.matrixColor };
          updatePaletteUI();
          updateMatrixPaletteUI();
        }
      }
    }
  };

  window.onToastMessage = function(data) {
    if (data && data.message) {
      showToast(data.message);
    }
  };

  window.onWatchdogStatus = function(status) {
    if (!status) return;
    watchdogInstalled = !!status.installed;
    watchdogRunning = !!status.running;

    const badge = document.getElementById('watchdog-state-badge');
    const btnText = document.getElementById('btn-toggle-watchdog-text');
    const infoWatchdog = document.getElementById('info-watchdog');

    if (status.running || status.installed) {
      if (badge) {
        badge.textContent = status.pid ? `PID ${status.pid} (24/7)` : 'Служба активна (24/7)';
        badge.className = 'info-val code text-green';
      }
      if (btnText) btnText.textContent = '⏹️ Отключить фоновую автозащиту';
      if (infoWatchdog) {
        infoWatchdog.textContent = 'In-App + Daemon (24/7)';
        infoWatchdog.className = 'info-val status-active';
      }
    } else {
      if (badge) {
        badge.textContent = 'Только пока открыто окно';
        badge.className = 'info-val code text-orange';
      }
      if (btnText) btnText.textContent = '🛡️ Включить автозащиту в фоне (24/7)';
      if (infoWatchdog) {
        infoWatchdog.textContent = 'Активен (In-App)';
        infoWatchdog.className = 'info-val status-active';
      }
    }
  };

  // Initialize
  renderKeyboard();
  updatePaletteUI();
  updateMatrixPaletteUI();
  updateSelectedCount();

  // Try to load profiles from disk and hardware status
  sendToNative({ action: 'loadProfilesFromFile' });
  sendToNative({ action: 'getStatus' });
  sendToNative({ action: 'getWatchdogStatus' });

})();
