// RoutePump Admin Dashboard JS logic
import './style.css';
import { state } from './state.js';
import { initMap } from './map.js';
import { setupAuth, showDashboardApp, showAuthScreen, handleLogout } from './auth.js';
import { setupForms } from './forms.js';

// Initialize Application
document.addEventListener('DOMContentLoaded', () => {
  setupNavigation();
  setupAuth();
  setupForms();

  if (state.token) {
    showDashboardApp();
  } else {
    showAuthScreen();
  }
});

// Set up Navigation
function setupNavigation() {
  const menuItems = document.querySelectorAll('.sidebar-menu-item');
  menuItems.forEach(item => {
    item.addEventListener('click', (e) => {
      e.preventDefault();
      const targetPage = item.getAttribute('data-page');
      switchPage(targetPage);
      
      // Update sidebar styling
      menuItems.forEach(mi => mi.classList.remove('active'));
      item.classList.add('active');
    });
  });

  // Logout Button
  const logoutBtn = document.getElementById('logout-btn');
  if (logoutBtn) {
    logoutBtn.addEventListener('click', handleLogout);
  }
}

function switchPage(pageId) {
  state.activePage = pageId;
  const pages = document.querySelectorAll('.page-view');
  pages.forEach(p => p.style.display = 'none');
  
  const targetPageElement = document.getElementById(`${pageId}-page`);
  if (targetPageElement) {
    targetPageElement.style.display = 'block';
  }

  if (pageId === 'stations') {
    // Lazy initialize map
    setTimeout(initMap, 100);
  }
}
