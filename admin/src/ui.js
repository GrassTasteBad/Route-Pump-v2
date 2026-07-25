// Modal and Alert utilities

window.openModal = function(modalId) {
  const modal = document.getElementById(modalId);
  if (modal) modal.classList.add('active');
};

window.closeModal = function(modalId) {
  const modal = document.getElementById(modalId);
  if (modal) modal.classList.remove('active');
};

export function openModal(modalId) {
  window.openModal(modalId);
}

export function closeModal(modalId) {
  window.closeModal(modalId);
}

export function showGlobalAlert(message, type = 'success') {
  const alert = document.getElementById('global-alert');
  if (alert) {
    alert.innerText = message;
    alert.className = `alert-message ${type}`;
    alert.style.display = 'block';
    setTimeout(() => {
      alert.style.display = 'none';
    }, 5000);
  }
}
