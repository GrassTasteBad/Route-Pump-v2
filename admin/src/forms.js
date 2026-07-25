import { state } from './state.js';
import { apiFetch } from './api.js';
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
}
