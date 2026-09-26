import { state } from './state.js';
import { apiFetch, API_BASE_URL } from './api.js';
import { showGlobalAlert, openModal, closeModal } from './ui.js';
import { loadAllData } from './views.js';

export function resetFuelEconomySelectors() {
  document.getElementById('fe-year').innerHTML = '<option value="">-- Year --</option>';
  document.getElementById('fe-make').innerHTML = '<option value="">-- Make --</option>';
  document.getElementById('fe-make').disabled = true;
  document.getElementById('fe-model').innerHTML = '<option value="">-- Model --</option>';
  document.getElementById('fe-model').disabled = true;
  document.getElementById('fe-option').innerHTML = '<option value="">-- Option --</option>';
  document.getElementById('fe-option').disabled = true;
  document.getElementById('fe-btn').disabled = true;
}

export async function loadFuelEconomyYears() {
  try {
    const years = await apiFetch('/fueleconomy/years');
    const select = document.getElementById('fe-year');
    if (select) {
      select.innerHTML = '<option value="">-- Year --</option>';
      years.forEach(y => {
        const opt = document.createElement('option');
        opt.value = y.value;
        opt.innerText = y.text;
        select.appendChild(opt);
      });
    }
  } catch (err) {
    console.error('Failed to load FuelEconomy.gov years', err);
  }
}

export function setupFuelEconomyIntegration() {
  const feYear = document.getElementById('fe-year');
  const feMake = document.getElementById('fe-make');
  const feModel = document.getElementById('fe-model');
  const feOption = document.getElementById('fe-option');
  const feBtn = document.getElementById('fe-btn');

  if (!feYear) return;

  feYear.addEventListener('change', async () => {
    const year = feYear.value;
    feMake.innerHTML = '<option value="">-- Make --</option>';
    feMake.disabled = true;
    feModel.innerHTML = '<option value="">-- Model --</option>';
    feModel.disabled = true;
    feOption.innerHTML = '<option value="">-- Option --</option>';
    feOption.disabled = true;
    feBtn.disabled = true;

    if (!year) return;

    try {
      const makes = await apiFetch(`/fueleconomy/makes?year=${year}`);
      feMake.innerHTML = '<option value="">-- Make --</option>';
      makes.forEach(m => {
        const opt = document.createElement('option');
        opt.value = m.value;
        opt.innerText = m.text;
        feMake.appendChild(opt);
      });
      feMake.disabled = false;
    } catch (err) {
      console.error(err);
    }
  });

  feMake.addEventListener('change', async () => {
    const year = feYear.value;
    const make = feMake.value;
    feModel.innerHTML = '<option value="">-- Model --</option>';
    feModel.disabled = true;
    feOption.innerHTML = '<option value="">-- Option --</option>';
    feOption.disabled = true;
    feBtn.disabled = true;

    if (!make) return;

    try {
      const models = await apiFetch(`/fueleconomy/models?year=${year}&make=${encodeURIComponent(make)}`);
      feModel.innerHTML = '<option value="">-- Model --</option>';
      models.forEach(m => {
        const opt = document.createElement('option');
        opt.value = m.value;
        opt.innerText = m.text;
        feModel.appendChild(opt);
      });
      feModel.disabled = false;
    } catch (err) {
      console.error(err);
    }
  });

  feModel.addEventListener('change', async () => {
    const year = feYear.value;
    const make = feMake.value;
    const model = feModel.value;
    feOption.innerHTML = '<option value="">-- Option --</option>';
    feOption.disabled = true;
    feBtn.disabled = true;

    if (!model) return;

    try {
      const options = await apiFetch(`/fueleconomy/options?year=${year}&make=${encodeURIComponent(make)}&model=${encodeURIComponent(model)}`);
      feOption.innerHTML = '<option value="">-- Option --</option>';
      options.forEach(o => {
        const opt = document.createElement('option');
        opt.value = o.value;
        opt.innerText = o.text;
        feOption.appendChild(opt);
      });
      feOption.disabled = false;
    } catch (err) {
      console.error(err);
    }
  });

  feOption.addEventListener('change', () => {
    feBtn.disabled = !feOption.value;
  });

  feBtn.addEventListener('click', async () => {
    const id = feOption.value;
    if (!id) return;

    feBtn.disabled = true;
    feBtn.innerHTML = '<span class="spinner"></span>Loading...';

    try {
      const specs = await apiFetch(`/fueleconomy/vehicle/${id}`);
      
      document.getElementById('catalog-make').value = specs.make;
      document.getElementById('catalog-model').value = specs.model;
      document.getElementById('catalog-year').value = specs.year;
      document.getElementById('catalog-displacement').value = specs.engine_displacement || '';
      document.getElementById('catalog-fuel').value = specs.fuel_type;
      document.getElementById('catalog-efficiency').value = specs.default_efficiency;
      document.getElementById('catalog-idling-rate').value = specs.default_idling_rate;

      showGlobalAlert('Vehicle specifications loaded successfully!');
    } catch (err) {
      showGlobalAlert(err.message, 'error');
    } finally {
      feBtn.disabled = false;
      feBtn.innerHTML = '<i class="fa-solid fa-arrows-rotate"></i> Load Vehicle Specifications';
    }
  });
}

export function setupForms() {
  setupFuelEconomyIntegration();
  
  // Add Station Dialog
  const addStationBtn = document.getElementById('add-station-btn');
  if (addStationBtn) {
    addStationBtn.addEventListener('click', () => {
      document.getElementById('station-form').reset();
      document.getElementById('station-modal-title').innerText = 'Add Gas Station';
      openModal('station-modal');
    });
  }

  const stationForm = document.getElementById('station-form');
  if (stationForm) {
    stationForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const name = document.getElementById('station-name').value;
      const branch = document.getElementById('station-branch').value;
      const latitude = parseFloat(document.getElementById('station-lat').value);
      const longitude = parseFloat(document.getElementById('station-lng').value);

      try {
        await apiFetch('/gas-stations', {
          method: 'POST',
          body: JSON.stringify({ name, branch, latitude, longitude }),
        });
        
        closeModal('station-modal');
        showGlobalAlert('Gas station added successfully!');
        loadAllData();
      } catch (err) {
        alert(err.message);
      }
    });
  }

  // Add Vehicle Catalog Dialog
  const addCatalogBtn = document.getElementById('add-catalog-btn');
  if (addCatalogBtn) {
    addCatalogBtn.addEventListener('click', () => {
      document.getElementById('catalog-form').reset();
      resetFuelEconomySelectors();
      loadFuelEconomyYears();
      openModal('catalog-modal');
    });
  }

  const catalogForm = document.getElementById('catalog-form');
  if (catalogForm) {
    catalogForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const make = document.getElementById('catalog-make').value;
      const model = document.getElementById('catalog-model').value;
      const year = parseInt(document.getElementById('catalog-year').value);
      const engine_displacement = document.getElementById('catalog-displacement').value;
      const fuel_type = document.getElementById('catalog-fuel').value;
      const default_efficiency = parseFloat(document.getElementById('catalog-efficiency').value);
      const default_idling_rate = parseFloat(document.getElementById('catalog-idling-rate').value);

      try {
        await apiFetch('/vehicle-catalog', {
          method: 'POST',
          body: JSON.stringify({ make, model, year, engine_displacement, fuel_type, default_efficiency, default_idling_rate }),
        });

        closeModal('catalog-modal');
        showGlobalAlert('Vehicle catalog type added!');
        loadAllData();
      } catch (err) {
        alert(err.message);
      }
    });
  }

  // Sync / Update Vehicle Catalog list
  const syncCatalogBtn = document.getElementById('sync-catalog-btn');
  if (syncCatalogBtn) {
    syncCatalogBtn.addEventListener('click', async () => {
      syncCatalogBtn.disabled = true;
      const originalText = syncCatalogBtn.innerHTML;
      syncCatalogBtn.innerHTML = '<span class="spinner"></span>Syncing...';
      
      try {
        const result = await apiFetch('/vehicle-catalog/sync', {
          method: 'POST'
        });
        showGlobalAlert(result.message || 'Catalog synced successfully!');
        loadAllData();
      } catch (err) {
        showGlobalAlert(err.message || 'Sync failed', 'error');
      } finally {
        syncCatalogBtn.disabled = false;
        syncCatalogBtn.innerHTML = originalText;
      }
    });
  }

  // Add User
  const addUserBtn = document.getElementById('add-user-btn');
  if (addUserBtn) {
    addUserBtn.addEventListener('click', () => {
      document.getElementById('user-form').reset();
      const stationGroup = document.getElementById('user-station-group');
      if (stationGroup) stationGroup.style.display = 'block';
      openModal('user-modal');
    });
  }

  // Role selector — toggle station dropdown visibility
  const userRoleSelect = document.getElementById('user-role');
  if (userRoleSelect) {
    userRoleSelect.addEventListener('change', (e) => {
      const stationGroup = document.getElementById('user-station-group');
      if (stationGroup) {
        stationGroup.style.display = e.target.value === 'partner' ? 'block' : 'none';
      }
    });
  }

  // User form submit
  const userForm = document.getElementById('user-form');
  if (userForm) {
    userForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const name = document.getElementById('user-name').value.trim();
      const email = document.getElementById('user-email').value.trim();
      const password = document.getElementById('user-password').value;
      const role = document.getElementById('user-role').value;
      const station_id = role === 'partner' ? document.getElementById('user-station').value : null;

      if (role === 'partner' && !station_id) {
        alert('Please select a linked gas station for the partner account.');
        return;
      }

      try {
        await apiFetch('/users', {
          method: 'POST',
          body: JSON.stringify({ name, email, password, role, station_id }),
        });
        closeModal('user-modal');
        showGlobalAlert(`User account for ${name} created successfully!`);
        loadAllData();
      } catch (err) {
        alert(err.message);
      }
    });
  }

  // ── Submit Prices via Image (Single Submission for All Fuel Variants) ──
  const openPriceModalBtn = document.getElementById('open-price-modal-btn');
  if (openPriceModalBtn) {
    openPriceModalBtn.addEventListener('click', () => {
      const select = document.getElementById('price-sub-station');
      if (select) {
        select.innerHTML = '<option value="">-- Select Station --</option>';
        (state.stations || []).forEach(s => {
          const opt = document.createElement('option');
          opt.value = s.id;
          opt.innerText = `${s.name} - ${s.branch}`;
          select.appendChild(opt);
        });
      }
      document.getElementById('price-submission-form').reset();
      const previewWrap = document.getElementById('price-sub-preview-wrap');
      if (previewWrap) previewWrap.style.display = 'none';
      openModal('price-submission-modal');
    });
  }

  // Station select change: prefill current prices if available
  const priceSubStation = document.getElementById('price-sub-station');
  if (priceSubStation) {
    priceSubStation.addEventListener('change', (e) => {
      const stationId = e.target.value;
      const station = (state.stations || []).find(s => s.id === stationId);
      if (station && station.prices) {
        document.getElementById('price-sub-unl91').value = station.prices['regular unleaded (91)'] || '';
        document.getElementById('price-sub-unl95').value = station.prices['premium unleaded(95)'] || '';
        document.getElementById('price-sub-dslreg').value = station.prices['regular diesel'] || '';
        document.getElementById('price-sub-dslprem').value = station.prices['premium diesel'] || '';
      }
    });
  }

  // Photo preview
  const photoInput = document.getElementById('price-sub-photo');
  if (photoInput) {
    photoInput.addEventListener('change', (e) => {
      const file = e.target.files[0];
      const previewWrap = document.getElementById('price-sub-preview-wrap');
      const previewImg = document.getElementById('price-sub-preview');
      if (file && previewImg && previewWrap) {
        previewImg.src = URL.createObjectURL(file);
        previewWrap.style.display = 'block';
      }
    });
  }

  // ── Image Audit Modal logic ──────────────────────────────────────────────────
  //
  // Instead of posting immediately on form submit, we show the admin an audit
  // modal where they inspect the image and tick 3 checklist boxes.  Only after
  // all boxes are checked can they click "Confirm & Publish Prices".
  //

  // Capture pending submission state
  let _pendingStationId = null;
  let _pendingPrices    = null;
  let _pendingPhotoFile = null;

  // Helper – enable/disable confirm button based on checklist
  function _updateAuditConfirmBtn() {
    const allChecked =
      document.getElementById('audit-check-match')?.checked &&
      document.getElementById('audit-check-legit')?.checked &&
      document.getElementById('audit-check-station')?.checked;
    const btn = document.getElementById('audit-confirm-btn');
    if (btn) btn.disabled = !allChecked;
  }

  // Wire checklist boxes
  ['audit-check-match', 'audit-check-legit', 'audit-check-station'].forEach(id => {
    document.getElementById(id)?.addEventListener('change', _updateAuditConfirmBtn);
  });

  // "Go Back" button — close audit modal and reopen the submission form
  document.getElementById('audit-goback-btn')?.addEventListener('click', () => {
    closeModal('price-audit-modal');
    openModal('price-submission-modal');
  });

  // "Cancel Submission" button — discard everything
  document.getElementById('audit-reject-btn')?.addEventListener('click', () => {
    closeModal('price-audit-modal');
    _pendingStationId = null;
    _pendingPrices    = null;
    _pendingPhotoFile = null;
    showGlobalAlert('Submission cancelled — no prices were published.', 'error');
  });

  // "X" close button on audit modal — same as Go Back
  document.getElementById('audit-modal-close-btn')?.addEventListener('click', () => {
    closeModal('price-audit-modal');
    openModal('price-submission-modal');
  });

  // "Confirm & Publish Prices" button — actually POST to API
  document.getElementById('audit-confirm-btn')?.addEventListener('click', async () => {
    if (!_pendingStationId || !_pendingPrices) return;

    const confirmBtn        = document.getElementById('audit-confirm-btn');
    const originalBtnText   = confirmBtn.innerHTML;
    confirmBtn.disabled     = true;
    confirmBtn.innerHTML    = '<span class="spinner"></span> Publishing…';

    try {
      const formData = new FormData();
      formData.append('prices', JSON.stringify(_pendingPrices));
      if (_pendingPhotoFile) {
        // Exactly 1 photo for all fuel variants
        formData.append('photo', _pendingPhotoFile);
      }

      const token = state.token || localStorage.getItem('rp_token');
      const res   = await fetch(`${API_BASE_URL}/gas-stations/${_pendingStationId}/prices`, {
        method:  'POST',
        headers: {
          'Authorization': token ? `Bearer ${token}` : '',
          'Accept':        'application/json',
        },
        body: formData,
      });

      const data = await res.json();
      if (!res.ok) throw new Error(data.message || 'Failed to submit fuel prices.');

      closeModal('price-audit-modal');
      showGlobalAlert('✅ All fuel variants published — 1 photo for all variants submitted successfully!');
      loadAllData();
    } catch (err) {
      showGlobalAlert(err.message, 'error');
    } finally {
      _pendingStationId = null;
      _pendingPrices    = null;
      _pendingPhotoFile = null;
      confirmBtn.disabled  = false;
      confirmBtn.innerHTML = originalBtnText;
    }
  });

  // Price submission form submit → intercept and open Audit Modal instead of posting
  const priceSubmissionForm = document.getElementById('price-submission-form');
  if (priceSubmissionForm) {
    priceSubmissionForm.addEventListener('submit', async (e) => {
      e.preventDefault();

      const stationId = document.getElementById('price-sub-station').value;
      if (!stationId) {
        alert('Please select a gas station.');
        return;
      }

      const p91     = parseFloat(document.getElementById('price-sub-unl91').value);
      const p95     = parseFloat(document.getElementById('price-sub-unl95').value);
      const dslReg  = parseFloat(document.getElementById('price-sub-dslreg').value);
      const dslPrem = parseFloat(document.getElementById('price-sub-dslprem').value);

      const prices = {};
      if (!isNaN(p91)     && p91     > 0) prices['regular unleaded (91)']  = p91;
      if (!isNaN(p95)     && p95     > 0) prices['premium unleaded(95)']   = p95;
      if (!isNaN(dslReg)  && dslReg  > 0) prices['regular diesel']         = dslReg;
      if (!isNaN(dslPrem) && dslPrem > 0) prices['premium diesel']         = dslPrem;

      if (Object.keys(prices).length === 0) {
        alert('Please enter at least one fuel variant price.');
        return;
      }

      const photoFile = photoInput && photoInput.files ? photoInput.files[0] : null;

      // ── Populate Audit Modal ──────────────────────────────────────────────
      // Station name
      const stationSelect   = document.getElementById('price-sub-station');
      const selectedOption  = stationSelect.options[stationSelect.selectedIndex];
      const auditStationLbl = document.getElementById('audit-station-label');
      if (auditStationLbl) {
        auditStationLbl.innerHTML =
          `<i class="fa-solid fa-gas-pump" style="color:var(--accent-cyan);"></i> ${selectedOption.text}`;
      }

      // Prices list
      const fuelLabels = {
        'regular unleaded (91)': 'Regular Unleaded (91)',
        'premium unleaded(95)':  'Premium Unleaded (95)',
        'regular diesel':        'Regular Diesel',
        'premium diesel':        'Premium Diesel',
      };
      const auditPricesList = document.getElementById('audit-prices-list');
      if (auditPricesList) {
        auditPricesList.innerHTML = Object.entries(prices).map(([type, price]) => `
          <div style="display:flex; justify-content:space-between; align-items:center;
                      background:rgba(255,255,255,0.04); border:1px solid var(--border-muted);
                      border-radius:8px; padding:8px 12px;">
            <span style="font-size:12.5px; color:var(--text-secondary); text-transform:capitalize;">${fuelLabels[type] || type}</span>
            <span style="font-size:15px; font-weight:700; color:var(--text-primary);">&#8369;${Number(price).toFixed(2)}</span>
          </div>`).join('');
      }

      // Image preview
      const auditImg     = document.getElementById('audit-preview-img');
      const auditNoPhoto = document.getElementById('audit-no-photo');
      const auditOcrHint = document.getElementById('audit-ocr-hint');
      if (photoFile && auditImg && auditNoPhoto) {
        auditImg.src            = URL.createObjectURL(photoFile);
        auditImg.style.display  = 'block';
        auditNoPhoto.style.display = 'none';
        if (auditOcrHint) auditOcrHint.style.display = 'block';
      } else if (auditImg && auditNoPhoto) {
        auditImg.src            = '';
        auditImg.style.display  = 'none';
        auditNoPhoto.style.display = 'flex';
        if (auditOcrHint) auditOcrHint.style.display = 'none';
      }

      // Reset checkboxes and confirm button
      ['audit-check-match', 'audit-check-legit', 'audit-check-station'].forEach(id => {
        const el = document.getElementById(id);
        if (el) el.checked = false;
      });
      const confirmBtn = document.getElementById('audit-confirm-btn');
      if (confirmBtn) confirmBtn.disabled = true;

      // Store pending data for the confirm handler
      _pendingStationId = stationId;
      _pendingPrices    = prices;
      _pendingPhotoFile = photoFile;

      // Close submission form and open audit modal
      closeModal('price-submission-modal');
      openModal('price-audit-modal');
    });
  }
}
