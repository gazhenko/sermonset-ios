// Reads the offer token from the path and hands it to the app. The token never leaves this page.
const token = decodeURIComponent(location.pathname.replace(/^\/t\/?/, '').replace(/\/$/, ''));
const open = document.getElementById('offer-open');
const problem = document.getElementById('offer-problem');
const expiry = document.getElementById('offer-expiry');

const looksLikeJWS = /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(token);
if (!looksLikeJWS) {
  problem.hidden = false;
  open.hidden = true;
} else {
  open.href = `sower://offer/${token}`;
  try {
    const part = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
    const payload = JSON.parse(atob(part + '='.repeat((4 - (part.length % 4)) % 4)));
    if (typeof payload.exp === 'number') {
      const when = new Date(payload.exp * 1000);
      const expired = when.getTime() <= Date.now();
      expiry.textContent = expired
        ? 'This offer has expired. Ask the sender for a new one.'
        : `Open it before ${when.toLocaleString(undefined, { weekday: 'long', month: 'long', day: 'numeric', hour: 'numeric', minute: '2-digit' })}.`;
      expiry.hidden = false;
      if (expired) open.hidden = true;
    }
  } catch {
    // The app verifies the signature; an unreadable expiry just isn't shown here.
  }
}
