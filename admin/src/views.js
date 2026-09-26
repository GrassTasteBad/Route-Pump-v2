import { state } from './state.js';
import { apiFetch } from './api.js';
import { showGlobalAlert } from './ui.js';
import { renderMapObjects } from './map.js';

export async function loadAllData() {
  if (!state.token) return;
  try {
    const stations = await apiFetch('/gas-stations');
    const catalog = await apiFetch('/vehicle-catalog');
    const anomalies = await apiFetch('/anomalies');
    const submissions = await apiFetch('/price-submissions');
    const users = await apiFetch('/users');
    const analytics = await apiFetch('/analytics/dashboard');

    state.stations = stations;
    state.catalog = catalog;
    state.anomalies = anomalies;
    state.submissions = submissions;
    state.users = users;
    state.analytics = analytics;

    updateDashboardUI();
    updateStationsTable();
    updateCatalogTable();
    updateAnomaliesTable();
    updateSubmissionsTable();
    updateUsersTable();
    updateUserStationDropdown();
    updateAnalyticsUI();
  } catch (err) {
    showGlobalAlert(err.message, 'error');
  }
}

export function updateDashboardUI() {
  const stationsEl = document.getElementById('stat-stations');
  const vehiclesEl = document.getElementById('stat-vehicles');
  const anomaliesEl = document.getElementById('stat-anomalies');
  const queuedVehiclesEl = document.getElementById('stat-queued-vehicles');
  
  if (stationsEl) stationsEl.innerText = state.stations.length;
  if (vehiclesEl) vehiclesEl.innerText = state.catalog.length;
  if (queuedVehiclesEl) {
    const totalQueued = state.stations.reduce((sum, s) => sum + (s.queue_count || 0), 0);
    queuedVehiclesEl.innerText = `${totalQueued} Vehicles`;
  }

  const pendingAnomalies = state.anomalies.filter(a => a.status === 'pending');
  if (anomaliesEl) anomaliesEl.innerText = pendingAnomalies.length;
  
  const badgeCount = document.getElementById('anomaly-badge-count');
  if (badgeCount) {
    if (pendingAnomalies.length > 0) {
      badgeCount.innerText = pendingAnomalies.length;
      badgeCount.style.display = 'inline-block';
    } else {
      badgeCount.style.display = 'none';
    }
  }

  // Calculate averages
  let unl91Sum = 0, unl91Count = 0;
  let unl95Sum = 0, unl95Count = 0;
  let dslRegSum = 0, dslRegCount = 0;
  let dslPremSum = 0, dslPremCount = 0;

  state.stations.forEach(s => {
    if (s.prices['regular unleaded (91)']) { unl91Sum += s.prices['regular unleaded (91)']; unl91Count++; }
    if (s.prices['premium unleaded(95)']) { unl95Sum += s.prices['premium unleaded(95)']; unl95Count++; }
    if (s.prices['regular diesel']) { dslRegSum += s.prices['regular diesel']; dslRegCount++; }
    if (s.prices['premium diesel']) { dslPremSum += s.prices['premium diesel']; dslPremCount++; }
  });

  const avgUnl91 = unl91Count > 0 ? unl91Sum / unl91Count : 0;
  const avgUnl95 = unl95Count > 0 ? unl95Sum / unl95Count : 0;
  const avgDslReg = dslRegCount > 0 ? dslRegSum / dslRegCount : 0;
  const avgDslPrem = dslPremCount > 0 ? dslPremSum / dslPremCount : 0;

  const unlAvgEl = document.getElementById('stat-unl-avg');
  const regUnl91El = document.getElementById('avg-regular-unleaded-91');
  const premUnl95El = document.getElementById('avg-premium-unleaded-95');
  const regDslEl = document.getElementById('avg-regular-diesel');
  const premDslEl = document.getElementById('avg-premium-diesel');

  if (unlAvgEl) unlAvgEl.innerText = `₱${avgUnl91.toFixed(2)}`;
  if (regUnl91El) regUnl91El.innerText = `₱${avgUnl91.toFixed(2)}`;
  if (premUnl95El) premUnl95El.innerText = `₱${avgUnl95.toFixed(2)}`;
  if (regDslEl) regDslEl.innerText = `₱${avgDslReg.toFixed(2)}`;
  if (premDslEl) premDslEl.innerText = `₱${avgDslPrem.toFixed(2)}`;

  // Update live queues table
  const queuesTable = document.getElementById('dashboard-queues-table');
  if (queuesTable) {
    queuesTable.innerHTML = '';
    
    state.stations.forEach(station => {
      let badgeClass = 'badge-success';
      let statusText = 'Empty';
      if (station.queue_count >= 1 && station.queue_count <= 3) {
        badgeClass = 'badge-warning';
        statusText = 'Moderate';
      } else if (station.queue_count > 3) {
        badgeClass = 'badge-danger';
        statusText = 'Congested';
      }

      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><strong>${station.name}</strong></td>
        <td>${station.branch}</td>
        <td style="text-align: center;">${station.queue_count} vehicles</td>
        <td>${station.wait_time_minutes} mins</td>
        <td><span class="badge ${badgeClass}">${statusText}</span></td>
      `;
      queuesTable.appendChild(tr);
    });
  }
}

export function updateStationsTable() {
  const tableBody = document.getElementById('stations-table-body');
  if (!tableBody) return;
  tableBody.innerHTML = '';

  state.stations.forEach(station => {
    let statusBadge = `<span class="badge badge-success">Active</span>`;
    if (station.status === 'maintenance') {
      statusBadge = `<span class="badge badge-warning">Maintenance</span>`;
    } else if (station.status === 'out_of_stock') {
      statusBadge = `<span class="badge badge-danger">Out of Fuel</span>`;
    } else if (station.status === 'inactive' || station.status === 'deactivated') {
      statusBadge = `<span class="badge" style="background: rgba(148, 163, 184, 0.15); color: #94a3b8; border: 1px solid rgba(148, 163, 184, 0.3);">Inactive</span>`;
    }

    const isActive = station.status === 'active';
    const actionBtn = isActive
      ? `<button class="btn-secondary btn-sm-toggle-station" data-id="${station.id}" data-action="deactivate" style="padding: 4px 10px; font-size: 11.5px; color: var(--accent-rose); border-color: rgba(244, 63, 94, 0.35);"><i class="fa-solid fa-power-off"></i> Deactivate</button>`
      : `<button class="btn-primary btn-sm-toggle-station" data-id="${station.id}" data-action="activate" style="padding: 4px 10px; font-size: 11.5px; background: var(--accent-emerald); border-color: var(--accent-emerald);"><i class="fa-solid fa-circle-check"></i> Activate</button>`;

    const tr = document.createElement('tr');
    tr.style.cursor = 'pointer';
    tr.innerHTML = `
      <td><strong>${station.name}</strong></td>
      <td>${station.branch}</td>
      <td>${Number(station.latitude).toFixed(6)}, ${Number(station.longitude).toFixed(6)}</td>
      <td>${statusBadge}</td>
      <td>₱${station.prices['regular unleaded (91)'] ? Number(station.prices['regular unleaded (91)']).toFixed(2) : '-'}</td>
      <td>₱${station.prices['premium unleaded(95)'] ? Number(station.prices['premium unleaded(95)']).toFixed(2) : '-'}</td>
      <td>₱${station.prices['regular diesel'] ? Number(station.prices['regular diesel']).toFixed(2) : '-'}</td>
      <td>₱${station.prices['premium diesel'] ? Number(station.prices['premium diesel']).toFixed(2) : '-'}</td>
      <td>
        ${actionBtn}
      </td>
    `;

    // Row clicks zoom map to station
    tr.addEventListener('click', (e) => {
      if (e.target.closest('.btn-sm-toggle-station')) return;
      if (state.map) {
        state.map.setCenter({ lat: station.latitude, lng: station.longitude });
        state.map.setZoom(16);
      }
    });

    tableBody.appendChild(tr);
  });

  // Activate / Deactivate Action bindings
  document.querySelectorAll('.btn-sm-toggle-station').forEach(btn => {
    btn.addEventListener('click', async (e) => {
      e.stopPropagation();
      const id = btn.getAttribute('data-id');
      const action = btn.getAttribute('data-action');
      const newStatus = action === 'activate' ? 'active' : 'inactive';
      const actionWord = action === 'activate' ? 'activate' : 'deactivate';

      if (confirm(`Are you sure you want to ${actionWord} this gas station?`)) {
        try {
          await apiFetch(`/gas-stations/${id}/status`, {
            method: 'POST',
            body: JSON.stringify({ status: newStatus }),
          });
          showGlobalAlert(`Gas station ${action === 'activate' ? 'activated' : 'deactivated'} successfully!`);
          loadAllData();
        } catch (err) {
          showGlobalAlert(err.message, 'error');
        }
      }
    });
  });

  // Update Map Markers & Polygons if map is active
  if (state.map) {
    renderMapObjects();
  }
}

let catalogPage = 1;
const catalogPageSize = 10;
let catalogSearchQuery = '';
let catalogFilterMake = '';
let catalogControlsInitialized = false;

function setupCatalogControls() {
  const searchInput = document.getElementById('catalog-search');
  if (searchInput) {
    searchInput.addEventListener('input', (e) => {
      catalogSearchQuery = e.target.value;
      catalogPage = 1;
      updateCatalogTable();
    });
  }

  const makeSelect = document.getElementById('catalog-filter-make');
  if (makeSelect) {
    makeSelect.addEventListener('change', (e) => {
      catalogFilterMake = e.target.value;
      catalogPage = 1;
      updateCatalogTable();
    });
  }

  const prevBtn = document.getElementById('catalog-prev-btn');
  if (prevBtn) {
    prevBtn.addEventListener('click', () => {
      if (catalogPage > 1) {
        catalogPage--;
        updateCatalogTable();
      }
    });
  }

  const nextBtn = document.getElementById('catalog-next-btn');
  if (nextBtn) {
    nextBtn.addEventListener('click', () => {
      const filteredCount = state.catalog.filter(item => {
        const matchesSearch = catalogSearchQuery === '' || 
          item.make.toLowerCase().includes(catalogSearchQuery.toLowerCase()) ||
          item.model.toLowerCase().includes(catalogSearchQuery.toLowerCase()) ||
          item.year.toString().includes(catalogSearchQuery);
        const matchesMake = catalogFilterMake === '' || item.make === catalogFilterMake;
        return matchesSearch && matchesMake;
      }).length;
      
      const totalPages = Math.ceil(filteredCount / catalogPageSize);
      if (catalogPage < totalPages) {
        catalogPage++;
        updateCatalogTable();
      }
    });
  }

  catalogControlsInitialized = true;
}

function populateCatalogMakesDropdown() {
  const makeSelect = document.getElementById('catalog-filter-make');
  if (!makeSelect) return;
  
  const currentSelection = catalogFilterMake;
  const makes = [...new Set(state.catalog.map(item => item.make))].sort();
  
  makeSelect.innerHTML = '<option value="">All Makes</option>';
  makes.forEach(make => {
    const opt = document.createElement('option');
    opt.value = make;
    opt.innerText = make;
    if (make === currentSelection) {
      opt.selected = true;
    }
    makeSelect.appendChild(opt);
  });
}

export function updateCatalogTable() {
  const tableBody = document.getElementById('catalog-table-body');
  if (!tableBody) return;
  tableBody.innerHTML = '';

  if (!catalogControlsInitialized) {
    setupCatalogControls();
  }

  populateCatalogMakesDropdown();

  const filtered = state.catalog.filter(item => {
    const matchesSearch = catalogSearchQuery === '' || 
      item.make.toLowerCase().includes(catalogSearchQuery.toLowerCase()) ||
      item.model.toLowerCase().includes(catalogSearchQuery.toLowerCase()) ||
      item.year.toString().includes(catalogSearchQuery);
      
    const matchesMake = catalogFilterMake === '' || item.make === catalogFilterMake;
    
    return matchesSearch && matchesMake;
  });

  const totalItems = filtered.length;
  const totalPages = Math.ceil(totalItems / catalogPageSize);
  
  if (catalogPage > totalPages && totalPages > 0) {
    catalogPage = totalPages;
  }
  if (catalogPage < 1) {
    catalogPage = 1;
  }

  const startIdx = (catalogPage - 1) * catalogPageSize;
  const endIdx = Math.min(startIdx + catalogPageSize, totalItems);
  const pagedItems = filtered.slice(startIdx, endIdx);

  pagedItems.forEach(item => {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td><strong>${item.make}</strong></td>
      <td>${item.model}</td>
      <td>${item.year}</td>
      <td>${item.engine_displacement || '-'}</td>
      <td><span class="badge badge-cyan">${item.fuel_type}</span></td>
      <td><strong>${Number(item.default_efficiency).toFixed(2)} km/L</strong></td>
      <td>${item.default_idling_rate ? Number(item.default_idling_rate).toFixed(2) + ' L/h' : '1.20 L/h'}</td>
    `;
    tableBody.appendChild(tr);
  });

  const infoEl = document.getElementById('catalog-pagination-info');
  if (infoEl) {
    if (totalItems > 0) {
      infoEl.innerText = `Showing ${startIdx + 1} to ${endIdx} of ${totalItems} entries`;
    } else {
      infoEl.innerText = 'Showing 0 to 0 of 0 entries';
    }
  }

  const prevBtn = document.getElementById('catalog-prev-btn');
  if (prevBtn) {
    prevBtn.disabled = (catalogPage <= 1);
  }
  const nextBtn = document.getElementById('catalog-next-btn');
  if (nextBtn) {
    nextBtn.disabled = (catalogPage >= totalPages || totalPages === 0);
  }
}

let anomaliesPage = 1;
const anomaliesPageSize = 10;
let anomaliesSearchQuery = '';
let anomaliesFilterFuel = '';
let anomaliesFilterStatus = 'pending';
let anomaliesControlsInitialized = false;

function setupAnomaliesControls() {
  const searchInput = document.getElementById('anomalies-search');
  if (searchInput) {
    searchInput.addEventListener('input', (e) => {
      anomaliesSearchQuery = e.target.value;
      anomaliesPage = 1;
      updateAnomaliesTable();
    });
  }

  const fuelSelect = document.getElementById('anomalies-filter-fuel');
  if (fuelSelect) {
    fuelSelect.addEventListener('change', (e) => {
      anomaliesFilterFuel = e.target.value;
      anomaliesPage = 1;
      updateAnomaliesTable();
    });
  }

  const refreshBtn = document.getElementById('refresh-anomalies-btn');
  if (refreshBtn) {
    refreshBtn.addEventListener('click', () => {
      loadAllData();
      showGlobalAlert('Report queue refreshed!', 'success');
    });
  }

  const tabButtons = document.querySelectorAll('.report-tab');
  tabButtons.forEach(tab => {
    tab.addEventListener('click', () => {
      tabButtons.forEach(t => t.classList.remove('active'));
      tab.classList.add('active');
      anomaliesFilterStatus = tab.getAttribute('data-filter') || 'pending';
      anomaliesPage = 1;
      updateAnomaliesTable();
    });
  });

  const prevBtn = document.getElementById('anomalies-prev-btn');
  if (prevBtn) {
    prevBtn.addEventListener('click', () => {
      if (anomaliesPage > 1) {
        anomaliesPage--;
        updateAnomaliesTable();
      }
    });
  }

  const nextBtn = document.getElementById('anomalies-next-btn');
  if (nextBtn) {
    nextBtn.addEventListener('click', () => {
      const filteredCount = getFilteredAnomaliesCount();
      const totalPages = Math.ceil(filteredCount / anomaliesPageSize);
      if (anomaliesPage < totalPages) {
        anomaliesPage++;
        updateAnomaliesTable();
      }
    });
  }

  anomaliesControlsInitialized = true;
}

function getFilteredAnomaliesCount() {
  return state.anomalies.filter(log => {
    const matchesStatus = anomaliesFilterStatus === 'all' || log.status === anomaliesFilterStatus;
    const matchesFuel = !anomaliesFilterFuel || (log.price && log.price.fuel_type === anomaliesFilterFuel);
    const q = anomaliesSearchQuery.toLowerCase();
    const matchesSearch = !q ||
      (log.station && log.station.name && log.station.name.toLowerCase().includes(q)) ||
      (log.station && log.station.branch && log.station.branch.toLowerCase().includes(q)) ||
      (log.price && log.price.reporter && log.price.reporter.name && log.price.reporter.name.toLowerCase().includes(q)) ||
      (log.description && log.description.toLowerCase().includes(q));
    return matchesStatus && matchesFuel && matchesSearch;
  }).length;
}

export function updateAnomaliesTable() {
  const tableBody = document.getElementById('anomalies-table-body');
  if (!tableBody) return;
  tableBody.innerHTML = '';

  if (!anomaliesControlsInitialized) {
    setupAnomaliesControls();
  }

  // 1. Calculate KPI Metrics
  const totalCount = state.anomalies.length;
  const pendingCount = state.anomalies.filter(a => a.status === 'pending').length;
  const approvedCount = state.anomalies.filter(a => a.status === 'resolved').length;
  const rejectedCount = state.anomalies.filter(a => a.status === 'dismissed').length;

  let trustSum = 0;
  let trustReportersCount = 0;
  state.anomalies.forEach(a => {
    if (a.price && a.price.reporter && typeof a.price.reporter.trust_score === 'number') {
      trustSum += a.price.reporter.trust_score;
      trustReportersCount++;
    }
  });
  const avgTrust = trustReportersCount > 0 ? (trustSum / trustReportersCount).toFixed(1) : '85.0';

  const statTotalEl = document.getElementById('queue-stat-total');
  const statPendingEl = document.getElementById('queue-stat-pending');
  const statApprovedEl = document.getElementById('queue-stat-approved');
  const statTrustEl = document.getElementById('queue-stat-trust');

  if (statTotalEl) statTotalEl.innerText = totalCount;
  if (statPendingEl) statPendingEl.innerText = pendingCount;
  if (statApprovedEl) statApprovedEl.innerText = approvedCount;
  if (statTrustEl) statTrustEl.innerText = avgTrust;

  // Update tab counts
  const tabPending = document.getElementById('tab-count-pending');
  const tabAll = document.getElementById('tab-count-all');
  const tabApproved = document.getElementById('tab-count-approved');
  const tabRejected = document.getElementById('tab-count-rejected');

  if (tabPending) tabPending.innerText = pendingCount;
  if (tabAll) tabAll.innerText = totalCount;
  if (tabApproved) tabApproved.innerText = approvedCount;
  if (tabRejected) tabRejected.innerText = rejectedCount;

  // 2. Filter data
  const filtered = state.anomalies.filter(log => {
    const matchesStatus = anomaliesFilterStatus === 'all' || log.status === anomaliesFilterStatus;
    const matchesFuel = !anomaliesFilterFuel ||
      (log.price && log.price.fuel_type === anomaliesFilterFuel) ||
      (log.variants && log.variants.some(v => v.fuel_type === anomaliesFilterFuel));
    const q = anomaliesSearchQuery.toLowerCase();
    const hasVariantMatch = log.variants && log.variants.some(v => v.fuel_type.toLowerCase().includes(q));
    const matchesSearch = !q ||
      (log.station && log.station.name && log.station.name.toLowerCase().includes(q)) ||
      (log.station && log.station.branch && log.station.branch.toLowerCase().includes(q)) ||
      (log.price && log.price.reporter && log.price.reporter.name && log.price.reporter.name.toLowerCase().includes(q)) ||
      (log.description && log.description.toLowerCase().includes(q)) ||
      hasVariantMatch;
    return matchesStatus && matchesFuel && matchesSearch;
  });

  const totalItems = filtered.length;
  const emptyStateEl = document.getElementById('anomalies-empty-state');
  const paginationRow = document.getElementById('anomalies-pagination-row');

  if (totalItems === 0) {
    if (emptyStateEl) emptyStateEl.style.display = 'block';
    if (paginationRow) paginationRow.style.display = 'none';
  } else {
    if (emptyStateEl) emptyStateEl.style.display = 'none';
    if (paginationRow) paginationRow.style.display = 'flex';
  }

  const totalPages = Math.ceil(totalItems / anomaliesPageSize);
  if (anomaliesPage > totalPages && totalPages > 0) anomaliesPage = totalPages;
  if (anomaliesPage < 1) anomaliesPage = 1;

  const startIdx = (anomaliesPage - 1) * anomaliesPageSize;
  const endIdx = Math.min(startIdx + anomaliesPageSize, totalItems);
  const pagedItems = filtered.slice(startIdx, endIdx);

  pagedItems.forEach(log => {
    const hasMultipleVariants = log.variants && log.variants.length > 1;

    // Fuel Variant HTML
    let fuelVariantsHtml;
    let reportedPricesHtml;

    if (hasMultipleVariants) {
      fuelVariantsHtml = `
        <div style="display:flex; flex-direction:column; gap:6px;">
          ${log.variants.map(v => `
            <div style="height:22px; display:flex; align-items:center;">
              <span class="badge badge-cyan" style="text-transform:capitalize; font-size:11px; padding:2px 8px; font-weight:600;">
                ${v.fuel_type}
              </span>
            </div>
          `).join('')}
        </div>`;

      reportedPricesHtml = `
        <div style="display:flex; flex-direction:column; gap:6px;">
          ${log.variants.map(v => {
            const rPrice = v.price ? Number(v.price) : 0;
            const currentBase = log.station?.prices?.[v.fuel_type] ? Number(log.station.prices[v.fuel_type]) : 0;
            let vBadge = '';
            if (currentBase > 0 && rPrice > 0) {
              const pct = (((rPrice - currentBase) / currentBase) * 100).toFixed(1);
              const isPositive = pct >= 0;
              if (Math.abs(pct) >= 10) {
                vBadge = ` <span class="badge-variance-high" style="font-size:10px; padding:1px 5px;"><i class="fa-solid fa-triangle-exclamation"></i> ${isPositive ? '+' : ''}${pct}%</span>`;
              } else {
                vBadge = ` <span class="badge-variance-normal" style="font-size:10px; padding:1px 5px;">${isPositive ? '+' : ''}${pct}%</span>`;
              }
            }
            return `
              <div style="height:22px; display:flex; align-items:center; font-size:14px; font-weight:700; color:var(--text-primary);">
                ₱${rPrice.toFixed(2)}${vBadge}
              </div>
            `;
          }).join('')}
        </div>`;
    } else {
      const v = (log.variants && log.variants[0]) || log.price || {};
      const reportedPrice = v.price ? Number(v.price) : (log.price?.price ? Number(log.price.price) : 0);
      const fuelType = v.fuel_type || log.price?.fuel_type || 'Fuel';
      const stationCurrentPrice = log.station?.prices?.[fuelType] ? Number(log.station.prices[fuelType]) : 0;

      let varianceBadge = '<span class="badge-variance-normal"><i class="fa-solid fa-check"></i> Standard</span>';
      if (stationCurrentPrice > 0 && reportedPrice > 0) {
        const pct = (((reportedPrice - stationCurrentPrice) / stationCurrentPrice) * 100).toFixed(1);
        const isPositive = pct >= 0;
        if (Math.abs(pct) >= 10) {
          varianceBadge = `<span class="badge-variance-high"><i class="fa-solid fa-triangle-exclamation"></i> ${isPositive ? '+' : ''}${pct}% Variance</span>`;
        } else {
          varianceBadge = `<span class="badge-variance-normal"><i class="fa-solid fa-shield-halved"></i> ${isPositive ? '+' : ''}${pct}% Variance</span>`;
        }
      }

      fuelVariantsHtml = `<span class="badge badge-cyan" style="text-transform: capitalize;">${fuelType}</span>`;
      reportedPricesHtml = `
        <div style="font-size: 15px; font-weight: 700; color: var(--text-primary);">₱${reportedPrice.toFixed(2)}</div>
        <div>${varianceBadge}</div>
      `;
    }

    // Reporter & Trust Score
    const reporter = log.price?.reporter;
    const reporterName = reporter?.name || (log.status === 'dismissed' ? '—' : 'Motorist');
    const trustScore = reporter?.trust_score ?? 80;
    
    let trustPill = '<span class="trust-pill-high"><i class="fa-solid fa-star"></i> ' + trustScore + ' Trust</span>';
    if (trustScore < 50) {
      trustPill = `<span class="trust-pill-low"><i class="fa-solid fa-circle-exclamation"></i> ${trustScore} Low Risk</span>`;
    } else if (trustScore < 80) {
      trustPill = `<span class="trust-pill-med"><i class="fa-solid fa-shield-halved"></i> ${trustScore} Med Trust</span>`;
    }

    // Photo Proof Thumbnail
    const imagePath = log.image_path || log.price?.image_path;
    let photoCellHtml;
    if (imagePath) {
      const safePath = (imagePath || '').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
      const thumbSrc = `${PROOF_STORAGE_BASE}/${imagePath}`;
      photoCellHtml = `
        <div class="proof-thumb-wrap" onclick="window.__rpViewProof('${safePath}')" title="Click to view full proof photo">
          <img src="${thumbSrc}" class="proof-thumb" alt="Price proof photo" loading="lazy"
               onerror="this.style.display='none';this.nextElementSibling.style.display='flex';">
          <div class="proof-thumb-err" style="display:none;width:56px;height:56px;border-radius:8px;background:#1e293b;align-items:center;justify-content:center;">
            <i class="fa-solid fa-image-slash" style="color:#64748b;font-size:18px;"></i>
          </div>
          <div class="proof-thumb-overlay"><i class="fa-solid fa-magnifying-glass-plus"></i></div>
        </div>`;
    } else {
      photoCellHtml = `<span style="font-size:11px;color:var(--text-secondary);display:flex;align-items:center;gap:4px;">
        <i class="fa-solid fa-ban" style="color:#475569;"></i> No Photo
      </span>`;
    }

    // Method & Time
    const isOcr = log.description?.toLowerCase().includes('ocr') || !!imagePath || log.price?.ocr_verified || (log.variants && log.variants.some(v => v.ocr_verified));
    const methodBadge = isOcr
      ? '<span class="method-badge-ocr"><i class="fa-solid fa-camera"></i> OCR Upload</span>'
      : '<span class="method-badge-manual"><i class="fa-solid fa-keyboard"></i> Manual Input</span>';
    
    const formattedDate = new Date(log.created_at || Date.now()).toLocaleTimeString('en-PH', {
      hour: '2-digit', minute: '2-digit', month: 'short', day: 'numeric'
    });

    // Status Badge
    const isPhotoReview = (log.price?.status === 'pending_photo_review') || (log.variants && log.variants.some(v => v.price_status === 'pending_photo_review')) || (!!imagePath && log.status === 'pending');
    let statusBadge = '<span class="badge badge-warning"><i class="fa-solid fa-clock"></i> Pending Review</span>';
    if (log.status === 'resolved') {
      statusBadge = '<span class="badge badge-success"><i class="fa-solid fa-check"></i> Approved</span>';
    } else if (log.status === 'dismissed') {
      statusBadge = '<span class="badge badge-danger"><i class="fa-solid fa-xmark"></i> Rejected</span>';
    } else if (isPhotoReview) {
      statusBadge = `<span class="badge" style="background:rgba(245,158,11,0.18);color:#f59e0b;border:1px solid rgba(245,158,11,0.4);">
        <i class="fa-solid fa-camera-rotate"></i> Pending Photo Review
      </span>`;
    }

    // Actions — Audit button opens detailed modal inspection
    const actionButtons = `
      <div style="display: flex; gap: 6px; align-items: center;">
        <button class="btn-inspect btn-anomaly-inspect" data-id="${log.id}"><i class="fa-solid fa-eye"></i> Audit</button>
      </div>
    `;

    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>
        <div><strong>${log.station?.name || 'Unknown Station'}</strong></div>
        <div style="color: var(--text-secondary); font-size: 12.5px;"><i class="fa-solid fa-location-dot" style="color: var(--accent-cyan);"></i> ${log.station?.branch || 'Main'}</div>
      </td>
      <td>${fuelVariantsHtml}</td>
      <td>${reportedPricesHtml}</td>
      <td>
        <div><strong>${reporterName}</strong></div>
        <div style="margin-top: 2px;">${trustPill}</div>
      </td>
      <td style="padding:8px 12px;">${photoCellHtml}</td>
      <td>
        <div>${methodBadge}</div>
        <div style="color: var(--text-secondary); font-size: 11.5px; margin-top: 3px;">${formattedDate}</div>
      </td>
      <td>${statusBadge}</td>
      <td>${actionButtons}</td>
    `;
    tableBody.appendChild(tr);
  });

  // Inspection Bindings (Audit Modal)
  document.querySelectorAll('.btn-anomaly-inspect').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const id = btn.getAttribute('data-id');
      const log = state.anomalies.find(a => a.id.toString() === id.toString());
      if (log) openReportDetailModal(log);
    });
  });

  // Pagination Info & Buttons
  const infoEl = document.getElementById('anomalies-pagination-info');
  if (infoEl) {
    if (totalItems > 0) {
      infoEl.innerText = `Showing ${startIdx + 1} to ${endIdx} of ${totalItems} reports`;
    } else {
      infoEl.innerText = 'Showing 0 to 0 of 0 reports';
    }
  }

  const prevBtn = document.getElementById('anomalies-prev-btn');
  if (prevBtn) prevBtn.disabled = (anomaliesPage <= 1);
  const nextBtn = document.getElementById('anomalies-next-btn');
  if (nextBtn) nextBtn.disabled = (anomaliesPage >= totalPages || totalPages === 0);
}

function openReportDetailModal(log) {
  const modalBody = document.getElementById('report-modal-body');
  const modalActions = document.getElementById('report-modal-actions');
  if (!modalBody) return;

  const reporter = log.price?.reporter;
  const trustScore = reporter?.trust_score ?? 80;
  const imagePath = log.image_path || log.price?.image_path;
  const variants = log.variants || (log.price ? [log.price] : []);

  let variantsComparisonHtml = '';
  if (variants.length > 0) {
    variantsComparisonHtml = `
      <div style="margin-bottom: 18px; border: 1px solid var(--border-glass); border-radius: 10px; overflow: hidden; background: rgba(255,255,255,0.02);">
        <div style="padding: 10px 14px; background: rgba(255,255,255,0.04); font-size: 12px; font-weight: 700; color: var(--text-secondary); text-transform: uppercase; letter-spacing: 0.5px;">
          Submitted Fuel Prices vs Current Baseline
        </div>
        <table style="width: 100%; border-collapse: collapse; font-size: 13px;">
          <thead>
            <tr style="border-bottom: 1px solid var(--border-glass); color: var(--text-secondary); text-align: left;">
              <th style="padding: 8px 14px;">Fuel Variant</th>
              <th style="padding: 8px 14px;">Submitted Price</th>
              <th style="padding: 8px 14px;">Current Baseline</th>
              <th style="padding: 8px 14px;">Variance</th>
            </tr>
          </thead>
          <tbody>
            ${variants.map(v => {
              const repPrice = v.price ? Number(v.price) : 0;
              const basePrice = log.station?.prices?.[v.fuel_type] ? Number(log.station.prices[v.fuel_type]) : 0;
              let varHtml = '<span style="color:var(--text-secondary);">No baseline</span>';
              if (basePrice > 0 && repPrice > 0) {
                const diff = repPrice - basePrice;
                const pct = (((repPrice - basePrice) / basePrice) * 100).toFixed(1);
                const isPos = pct >= 0;
                const color = Math.abs(pct) >= 10 ? 'var(--accent-rose)' : 'var(--accent-emerald)';
                varHtml = `<span style="color:${color};font-weight:600;">${isPos ? '+' : ''}₱${diff.toFixed(2)} (${isPos ? '+' : ''}${pct}%)</span>`;
              }
              return `
                <tr style="border-bottom: 1px solid rgba(255,255,255,0.04);">
                  <td style="padding: 9px 14px;"><span class="badge badge-cyan" style="text-transform:capitalize; font-size:11px;">${v.fuel_type}</span></td>
                  <td style="padding: 9px 14px; font-weight: 700; color: var(--text-primary); font-size: 14px;">₱${repPrice.toFixed(2)}</td>
                  <td style="padding: 9px 14px; color: var(--text-secondary);">${basePrice > 0 ? `₱${basePrice.toFixed(2)}` : '—'}</td>
                  <td style="padding: 9px 14px;">${varHtml}</td>
                </tr>
              `;
            }).join('')}
          </tbody>
        </table>
      </div>
    `;
  }

  modalBody.innerHTML = `
    <div class="audit-details-grid" style="margin-bottom: 16px;">
      <div class="audit-stat-box">
        <div class="audit-stat-label">Gas Station</div>
        <div class="audit-stat-value" style="font-size: 15px;">${log.station?.name || 'Unknown'} (${log.station?.branch || 'Main'})</div>
      </div>
      <div class="audit-stat-box">
        <div class="audit-stat-label">Reporter Rating</div>
        <div class="audit-stat-value" style="font-size: 15px;">${reporter?.name || 'Motorist'} <span style="font-size: 12px; color: var(--accent-emerald);">(⭐ ${trustScore}/100)</span></div>
      </div>
    </div>

    ${imagePath ? `
      <div style="margin-bottom: 16px; padding: 14px; background: rgba(255,255,255,0.03); border: 1px solid var(--border-glass); border-radius: 10px;">
        <div class="audit-stat-label" style="margin-bottom: 8px;"><i class="fa-solid fa-camera" style="color: var(--accent-cyan);"></i> Motorist Verification Photo Proof</div>
        <div style="display: flex; align-items: center; gap: 14px;">
          <div class="proof-thumb-wrap" onclick="window.__rpViewProof('${(imagePath || '').replace(/"/g, '&quot;').replace(/'/g, '&#39;')}')" title="Click to view full photo" style="width: 76px; height: 76px; flex-shrink: 0;">
            <img src="${PROOF_STORAGE_BASE}/${imagePath}" class="proof-thumb" alt="Price proof photo">
            <div class="proof-thumb-overlay"><i class="fa-solid fa-magnifying-glass-plus"></i></div>
          </div>
          <div>
            <div style="font-size: 13.5px; font-weight: 600; color: var(--text-primary);">OCR Board Photo Submitted</div>
            <div style="font-size: 12px; color: var(--text-secondary); margin-top: 3px;">Audit the photographed fuel price board against the entered prices below. Click the thumbnail to view high-resolution image.</div>
          </div>
        </div>
      </div>
    ` : ''}

    ${variantsComparisonHtml}

    <div class="audit-comparison-box" style="margin-bottom: 16px;">
      <div class="audit-stat-label" style="margin-bottom: 6px;">Audit Notes & System Flag</div>
      <div style="font-size: 12.5px; color: var(--text-secondary); line-height: 1.5;">${log.description || 'Reported price submission flagged for moderation threshold audit.'}</div>
    </div>

    ${log.status === 'pending' ? `
      <div class="audit-impact-callout approve">
        <i class="fa-solid fa-circle-info" style="font-size: 18px;"></i>
        <div>
          <strong>Approval Impact:</strong> Approving will publish all submitted fuel prices to active motorists and award <strong>+10 Trust Score</strong> to ${reporter?.name || 'reporter'}.
        </div>
      </div>
    ` : ''}
  `;

  if (log.status === 'pending') {
    modalActions.innerHTML = `
      <button type="button" class="btn-secondary" onclick="closeModal('report-detail-modal')">Cancel</button>
      <button type="button" class="btn-danger" id="modal-reject-btn"><i class="fa-solid fa-xmark"></i> Reject Report</button>
      <button type="button" class="btn-success" id="modal-approve-btn"><i class="fa-solid fa-check"></i> Approve & Publish</button>
    `;

    document.getElementById('modal-approve-btn')?.addEventListener('click', async () => {
      try {
        await apiFetch(`/anomalies/${log.id}/resolve`, { method: 'POST' });
        window.closeModal('report-detail-modal');
        showGlobalAlert('Report approved! Submitted prices are now live for motorists.');
        loadAllData();
      } catch (err) {
        showGlobalAlert(err.message, 'error');
      }
    });

    document.getElementById('modal-reject-btn')?.addEventListener('click', async () => {
      if (!confirm('Are you sure you want to reject this price report?')) return;
      try {
        await apiFetch(`/anomalies/${log.id}/dismiss`, { method: 'POST' });
        window.closeModal('report-detail-modal');
        showGlobalAlert('Report rejected and dismissed.');
        loadAllData();
      } catch (err) {
        showGlobalAlert(err.message, 'error');
      }
    });
  } else {
    modalActions.innerHTML = `
      <button type="button" class="btn-secondary" onclick="closeModal('report-detail-modal')">Close</button>
    `;
  }

  window.openModal('report-detail-modal');
}


export function updateUsersTable() {
  const tableBody = document.getElementById('users-table-body');
  if (!tableBody) return;
  tableBody.innerHTML = '';

  state.users.forEach(user => {
    const roleBadgeClass = user.role === 'admin'
      ? 'badge-danger'
      : user.role === 'partner'
        ? 'badge-cyan'
        : 'badge-success';

    const roleLabel = user.role.charAt(0).toUpperCase() + user.role.slice(1);
    const stationCell = user.station
      ? `<strong>${user.station.name}</strong> <span style="color:var(--text-secondary);font-size:12px;">(${user.station.branch})</span>`
      : '<span style="color:var(--text-secondary);">—</span>';

    const statusBadge = user.status === 'deactivated'
      ? '<span class="badge badge-danger">Deactivated</span>'
      : '<span class="badge badge-success">Active</span>';

    const joinedDate = new Date(user.created_at).toLocaleDateString('en-PH', {
      year: 'numeric', month: 'short', day: 'numeric'
    });

    const isSelf = state.user && state.user.id === user.id;
    let actionBtn = '';
    if (isSelf) {
      actionBtn = `<span style="color:var(--text-secondary);font-size:12px;">Current Session</span>`;
    } else if (user.status === 'deactivated') {
      actionBtn = `<button class="btn-success btn-user-activate" data-id="${user.id}" style="padding:4px 8px;font-size:11px;"><i class="fa-solid fa-user-check"></i> Activate</button>`;
    } else {
      actionBtn = `<button class="btn-danger btn-user-deactivate" data-id="${user.id}" style="padding:4px 8px;font-size:11px;"><i class="fa-solid fa-ban"></i> Deactivate</button>`;
    }

    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td><strong>${user.name}</strong></td>
      <td style="color:var(--text-secondary);font-size:13px;">${user.email}</td>
      <td><span class="badge ${roleBadgeClass}">${roleLabel}</span></td>
      <td>${stationCell}</td>
      <td>${statusBadge}</td>
      <td style="color:var(--text-secondary);font-size:13px;">${joinedDate}</td>
      <td>${actionBtn}</td>
    `;
    tableBody.appendChild(tr);
  });

  // Deactivate action bindings
  document.querySelectorAll('.btn-user-deactivate').forEach(btn => {
    btn.addEventListener('click', async () => {
      const id = btn.getAttribute('data-id');
      if (confirm('Deactivate this user account? The user will no longer be able to log in.')) {
        try {
          await apiFetch(`/users/${id}`, { method: 'DELETE' });
          showGlobalAlert('User account deactivated successfully!');
          loadAllData();
        } catch (err) {
          showGlobalAlert(err.message, 'error');
        }
      }
    });
  });

  // Activate action bindings
  document.querySelectorAll('.btn-user-activate').forEach(btn => {
    btn.addEventListener('click', async () => {
      const id = btn.getAttribute('data-id');
      if (confirm('Reactivate this user account? The user will be able to log in again.')) {
        try {
          await apiFetch(`/users/${id}/activate`, { method: 'POST' });
          showGlobalAlert('User account activated successfully!');
          loadAllData();
        } catch (err) {
          showGlobalAlert(err.message, 'error');
        }
      }
    });
  });
}

export function updateUserStationDropdown() {
  const select = document.getElementById('user-station');
  if (!select) return;
  const currentVal = select.value;
  select.innerHTML = '<option value="">-- Select a gas station --</option>';

  state.stations.forEach(station => {
    const opt = document.createElement('option');
    opt.value = station.id;
    opt.innerText = `${station.name} - ${station.branch}`;
    select.appendChild(opt);
  });

  if (currentVal && state.stations.some(s => s.id === currentVal)) {
    select.value = currentVal;
  }
}

export function updateAnalyticsUI() {
  if (!state.analytics) return;

  // 1. Fuel Type Distribution Chart
  const distributionContainer = document.getElementById('fuel-type-distribution-container');
  if (distributionContainer) {
    distributionContainer.innerHTML = '';
    const distData = state.analytics.fuel_type_distribution || {};
    
    let maxCount = 1;
    Object.values(distData).forEach(val => {
      if (val > maxCount) maxCount = val;
    });

    Object.entries(distData).forEach(([fuelType, count]) => {
      const percentage = (count / maxCount) * 100;
      
      const row = document.createElement('div');
      row.style.display = 'flex';
      row.style.flexDirection = 'column';
      row.style.gap = '6px';
      
      row.innerHTML = `
        <div style="display: flex; justify-content: space-between; font-size: 13.5px; font-weight: 500;">
          <span style="text-transform: capitalize;">${fuelType}</span>
          <span style="color: var(--accent-cyan); font-weight: bold;">${count} reports</span>
        </div>
        <div style="width: 100%; height: 10px; background: var(--bg-secondary); border-radius: 5px; overflow: hidden; border: 1px solid var(--border-muted);">
          <div style="width: ${percentage}%; height: 100%; background: linear-gradient(90deg, var(--accent-cyan), var(--accent-emerald)); border-radius: 5px;"></div>
        </div>
      `;
      distributionContainer.appendChild(row);
    });

    if (Object.keys(distData).length === 0) {
      distributionContainer.innerHTML = '<div style="color: var(--text-secondary); text-align: center; padding: 20px;">No fuel price logs available.</div>';
    }
  }

  // 2. Vehicle Efficiency Categorization Table
  const efficiencyTableBody = document.getElementById('vehicle-efficiency-table-body');
  if (efficiencyTableBody) {
    efficiencyTableBody.innerHTML = '';
    const efficiencyData = state.analytics.vehicle_efficiency_categorization || [];

    efficiencyData.forEach(row => {
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><strong style="text-transform: capitalize;">${row.vehicle_type}</strong></td>
        <td><strong style="color: var(--accent-emerald);">${Number(row.avg_fuel_efficiency).toFixed(2)} km/L</strong></td>
        <td>${Number(row.avg_idling_rate).toFixed(2)} L/h</td>
        <td><span class="badge badge-cyan">${row.total_vehicles} logged</span></td>
      `;
      efficiencyTableBody.appendChild(tr);
    });

    if (efficiencyData.length === 0) {
      efficiencyTableBody.innerHTML = '<tr><td colspan="4" style="text-align: center; color: var(--text-secondary);">No vehicle profile data available.</td></tr>';
    }
  }

  // 3. Fuel Price Monthly Trend Table
  const trendsTableBody = document.getElementById('monthly-trends-table-body');
  if (trendsTableBody) {
    trendsTableBody.innerHTML = '';
    const trendsData = state.analytics.monthly_price_trends || [];

    trendsData.forEach(row => {
      const tr = document.createElement('tr');
      tr.innerHTML = `
        <td><strong>${row.month}</strong></td>
        <td><strong style="color: var(--accent-cyan);">₱${Number(row.avg_unleaded_price).toFixed(2)}</strong></td>
        <td><strong style="color: var(--accent-amber);">₱${Number(row.avg_diesel_price).toFixed(2)}</strong></td>
      `;
      trendsTableBody.appendChild(tr);
    });

    if (trendsData.length === 0) {
      trendsTableBody.innerHTML = '<tr><td colspan="3" style="text-align: center; color: var(--text-secondary);">No historical monthly price trends available.</td></tr>';
    }
  }
}

let submissionsSearchQuery = '';
let submissionsStatusFilter = '';
let submissionsFuelFilter = '';

// ── Photo Proof Lightbox ─────────────────────────────────────────────────────
const _storageHost = window.location.hostname || '127.0.0.1';
const PROOF_STORAGE_BASE = `http://${_storageHost}:8000/storage`;

window.__rpViewProof = function (imagePath) {
  const modal  = document.getElementById('proof-photo-modal');
  const img    = document.getElementById('proof-photo-img');
  const loader = document.getElementById('proof-photo-loader');
  if (!modal || !img) return;
  img.style.display = 'none';
  if (loader) loader.style.display = 'flex';
  modal.style.display = 'flex';
  img.onload  = () => { if (loader) loader.style.display = 'none'; img.style.display = 'block'; };
  img.onerror = () => { if (loader) loader.style.display = 'none'; img.alt = 'Failed to load'; img.style.display = 'block'; };
  img.src = `${PROOF_STORAGE_BASE}/${imagePath}`;
};

window.__rpCloseProof = function () {
  const modal = document.getElementById('proof-photo-modal');
  const img   = document.getElementById('proof-photo-img');
  if (modal) modal.style.display = 'none';
  if (img)   img.src = '';
};

window.__rpApproveSubmission = async function (id) {
  try {
    await apiFetch(`/price-submissions/${id}/approve`, { method: 'POST' });
    showGlobalAlert('All fuel variants in this submission approved & verified!');
    loadAllData();
  } catch (err) {
    showGlobalAlert(err.message, 'error');
  }
};

window.__rpRejectSubmission = async function (id) {
  if (!confirm('Are you sure you want to reject this price submission?')) return;
  try {
    await apiFetch(`/price-submissions/${id}/reject`, { method: 'POST' });
    showGlobalAlert('Price submission rejected.');
    loadAllData();
  } catch (err) {
    showGlobalAlert(err.message, 'error');
  }
};

export function updateSubmissionsTable() {
  const tableBody = document.getElementById('submissions-table-body');
  if (!tableBody) return;

  // Bind Search & Filter Input Listeners once
  const subSearchInput = document.getElementById('submissions-search');
  if (subSearchInput && !subSearchInput.dataset.bound) {
    subSearchInput.dataset.bound = 'true';
    subSearchInput.addEventListener('input', (e) => {
      submissionsSearchQuery = e.target.value;
      updateSubmissionsTable();
    });
  }

  const subStatusFilter = document.getElementById('submissions-filter-status');
  if (subStatusFilter && !subStatusFilter.dataset.bound) {
    subStatusFilter.dataset.bound = 'true';
    subStatusFilter.addEventListener('change', (e) => {
      submissionsStatusFilter = e.target.value;
      updateSubmissionsTable();
    });
  }

  const subFuelFilter = document.getElementById('submissions-filter-fuel');
  if (subFuelFilter && !subFuelFilter.dataset.bound) {
    subFuelFilter.dataset.bound = 'true';
    subFuelFilter.addEventListener('change', (e) => {
      submissionsFuelFilter = e.target.value;
      updateSubmissionsTable();
    });
  }

  const refreshSubBtn = document.getElementById('refresh-submissions-btn');
  if (refreshSubBtn && !refreshSubBtn.dataset.bound) {
    refreshSubBtn.dataset.bound = 'true';
    refreshSubBtn.addEventListener('click', () => {
      loadAllData();
    });
  }

  const submissions = state.submissions || [];

  // Metrics
  const totalCount     = submissions.length;
  const verifiedCount  = submissions.filter(s => s.calculated_status === 'verified').length;
  const pendingCount   = submissions.filter(s => s.calculated_status === 'pending' || s.calculated_status === 'pending_photo_review').length;
  const rejectedCount  = submissions.filter(s => s.calculated_status === 'rejected').length;
  const withPhotoCount = submissions.filter(s => s.image_path).length;

  const statTotal    = document.getElementById('sub-stat-total');
  const statVerified = document.getElementById('sub-stat-verified');
  const statPending  = document.getElementById('sub-stat-pending');
  const statRejected = document.getElementById('sub-stat-rejected');
  const statPhotos   = document.getElementById('sub-stat-photos');

  if (statTotal)    statTotal.innerText    = totalCount;
  if (statVerified) statVerified.innerText = verifiedCount;
  if (statPending)  statPending.innerText  = pendingCount;
  if (statPhotos)   statPhotos.innerText   = withPhotoCount;
  if (statRejected) statRejected.innerText = rejectedCount;

  // Filter Submissions
  const filtered = submissions.filter(sub => {
    const q = submissionsSearchQuery.toLowerCase();
    const hasVariantMatch = sub.variants && sub.variants.some(v => v.fuel_type.toLowerCase().includes(q));
    const matchesSearch = !q ||
      (sub.station_name && sub.station_name.toLowerCase().includes(q)) ||
      (sub.station_branch && sub.station_branch.toLowerCase().includes(q)) ||
      (sub.reporter_name && sub.reporter_name.toLowerCase().includes(q)) ||
      (sub.fuel_type && sub.fuel_type.toLowerCase().includes(q)) ||
      hasVariantMatch;

    const matchesStatus = !submissionsStatusFilter || sub.calculated_status === submissionsStatusFilter;
    const matchesFuel = !submissionsFuelFilter || 
      sub.fuel_type === submissionsFuelFilter ||
      (sub.variants && sub.variants.some(v => v.fuel_type === submissionsFuelFilter));

    return matchesSearch && matchesStatus && matchesFuel;
  });

  const emptyStateEl = document.getElementById('submissions-empty-state');
  if (filtered.length === 0) {
    tableBody.innerHTML = '';
    if (emptyStateEl) emptyStateEl.style.display = 'block';
    return;
  } else {
    if (emptyStateEl) emptyStateEl.style.display = 'none';
  }

  tableBody.innerHTML = '';

  filtered.forEach(sub => {
    const trustScore = sub.trust_score ?? 50;
    let trustPill = '<span class="trust-pill-high"><i class="fa-solid fa-star"></i> ' + trustScore + ' Trust</span>';
    if (trustScore < 50) {
      trustPill = `<span class="trust-pill-low"><i class="fa-solid fa-circle-exclamation"></i> ${trustScore} Low Risk</span>`;
    } else if (trustScore < 80) {
      trustPill = `<span class="trust-pill-med"><i class="fa-solid fa-shield-halved"></i> ${trustScore} Med Trust</span>`;
    }

    let locationBadge = '<span class="badge badge-warning"><i class="fa-solid fa-tower-cell"></i> Remote Submission</span>';
    if (sub.is_inside_geofence) {
      locationBadge = '<span class="badge badge-success"><i class="fa-solid fa-location-dot"></i> Geofence (150m)</span>';
    }
    if (sub.ocr_verified) {
      locationBadge += ' <span class="method-badge-ocr"><i class="fa-solid fa-camera"></i> OCR Verified</span>';
    }

    let statusBadge = '<span class="badge badge-warning"><i class="fa-solid fa-clock"></i> Pending (Remote)</span>';
    if (sub.calculated_status === 'pending_photo_review') {
      const ocrTag = sub.ocr_verified
        ? ' <span style="font-size:10px; opacity:.8;"><i class="fa-solid fa-wand-magic-sparkles"></i> OCR ✓</span>'
        : '';
      statusBadge = `<span class="badge" style="background:rgba(245,158,11,0.18);color:#f59e0b;border:1px solid rgba(245,158,11,0.4);">
        <i class="fa-solid fa-camera-rotate"></i> Pending Photo Review${ocrTag}
      </span>`;
    } else if (sub.calculated_status === 'approved') {
      statusBadge = '<span class="badge badge-success"><i class="fa-solid fa-circle-check"></i> Approved (Admin Decision)</span>';
    } else if (sub.calculated_status === 'rejected') {
      statusBadge = '<span class="badge badge-danger"><i class="fa-solid fa-circle-xmark"></i> Rejected (Admin Decision)</span>';
    } else if (sub.calculated_status === 'verified') {
      statusBadge = '<span class="badge badge-success"><i class="fa-solid fa-shield-check"></i> Verified (Geofence / OCR)</span>';
    }

    // Audits are made strictly in the Reports tab — Submitted Prices is purely the record
    const formattedDate = new Date(sub.created_at || Date.now()).toLocaleTimeString('en-PH', {
      hour: '2-digit', minute: '2-digit', month: 'short', day: 'numeric'
    });

    // Photo proof thumbnail (1 photo for all variants)
    let photoCellHtml;
    if (sub.image_path) {
      const safePath = (sub.image_path || '').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
      const thumbSrc = `${PROOF_STORAGE_BASE}/${sub.image_path}`;
      photoCellHtml = `
        <div class="proof-thumb-wrap" onclick="window.__rpViewProof('${safePath}')" title="View full proof photo (1 photo for all fuel variants)">
          <img src="${thumbSrc}" class="proof-thumb" alt="Price proof" loading="lazy"
               onerror="this.style.display='none';this.nextElementSibling.style.display='flex';">
          <div class="proof-thumb-err" style="display:none;width:56px;height:56px;border-radius:8px;background:#1e293b;align-items:center;justify-content:center;">
            <i class="fa-solid fa-image-slash" style="color:#64748b;font-size:18px;"></i>
          </div>
          <div class="proof-thumb-overlay"><i class="fa-solid fa-magnifying-glass-plus"></i></div>
        </div>`;
    } else {
      photoCellHtml = `<span style="font-size:11px;color:var(--text-secondary);display:flex;align-items:center;gap:4px;">
        <i class="fa-solid fa-ban" style="color:#475569;"></i> No Photo
      </span>`;
    }

    // Single submission: display every fuel variant available on the image together
    let fuelVariantsHtml;
    let submittedPricesHtml;

    if (sub.variants && sub.variants.length > 1) {
      fuelVariantsHtml = `
        <div style="display:flex; flex-direction:column; gap:6px;">
          ${sub.variants.map(v => `
            <div style="height:22px; display:flex; align-items:center;">
              <span class="badge badge-cyan" style="text-transform:capitalize; font-size:11px; padding:2px 8px; font-weight:600;">
                ${v.fuel_type}
              </span>
            </div>
          `).join('')}
        </div>`;

      submittedPricesHtml = `
        <div style="display:flex; flex-direction:column; gap:6px;">
          ${sub.variants.map(v => `
            <div style="height:22px; display:flex; align-items:center; font-size:14px; font-weight:700; color:var(--text-primary);">
              &#8369;${Number(v.price).toFixed(2)}
            </div>
          `).join('')}
        </div>`;
    } else {
      const v = (sub.variants && sub.variants[0]) || sub;
      fuelVariantsHtml = `<span class="badge badge-cyan" style="text-transform:capitalize;">${v.fuel_type}</span>`;
      submittedPricesHtml = `<div style="font-size:15px; font-weight:700; color:var(--text-primary);">&#8369;${Number(v.price).toFixed(2)}</div>`;
    }

    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>
        <div><strong>${sub.station_name}</strong></div>
        <div style="color:var(--text-secondary);font-size:12.5px;"><i class="fa-solid fa-location-dot" style="color:var(--accent-cyan);"></i> ${sub.station_branch}</div>
      </td>
      <td>${fuelVariantsHtml}</td>
      <td>${submittedPricesHtml}</td>
      <td>
        <div><strong>${sub.reporter_name}</strong></div>
        <div style="margin-top:2px;">${trustPill}</div>
      </td>
      <td style="padding:8px 12px;">${photoCellHtml}</td>
      <td><div>${locationBadge}</div></td>
      <td><div style="font-size:12.5px;color:var(--text-secondary);">${formattedDate}</div></td>
      <td>
        ${statusBadge}
      </td>
    `;
    tableBody.appendChild(tr);
  });
}
