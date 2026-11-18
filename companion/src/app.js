(function () {
  'use strict';
  var session = null, reporting = false, timer = null;
  var byID = function (id) { return document.getElementById(id); };
  function status(message) { byID('status').textContent = message; }
  function origin(value) {
    var url = new URL(value);
    if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || (url.pathname !== '/' && url.pathname !== '')) throw new Error('Use an HTTPS origin without a path, query or credentials.');
    return url.origin;
  }
  function randomInstance() {
    if (!window.crypto || !window.crypto.getRandomValues) throw new Error('Secure random generation is unavailable. Pairing is disabled.');
    var bytes = new Uint8Array(16); window.crypto.getRandomValues(bytes);
    return Array.prototype.map.call(bytes, function (byte) { return ('0' + byte.toString(16)).slice(-2); }).join('');
  }
  function request(base, path, method, body, token) {
    return new Promise(function (resolve, reject) {
      var xhr = new XMLHttpRequest(); xhr.open(method, base + path, true); xhr.timeout = 10000;
      xhr.setRequestHeader('Content-Type', 'application/json');
      if (token) xhr.setRequestHeader('Authorization', 'Bearer ' + token);
      xhr.onload = function () {
        if (xhr.status < 200 || xhr.status >= 300) { reject(new Error('Bridge request failed (HTTP ' + xhr.status + '). Check pairing, permissions and session expiry.')); return; }
        try {
          var result = xhr.responseText ? JSON.parse(xhr.responseText) : {};
          if (result.error) throw new Error('The bridge rejected the operation.');
          resolve(result);
        } catch (_) { reject(new Error('Unexpected bridge response. No success is assumed.')); }
      };
      xhr.onerror = function () { reject(new Error('HTTPS connection failed. Check the bridge origin, trusted TLS certificate, TV access policy and CSP.')); };
      xhr.ontimeout = function () { reject(new Error('Bridge timed out. Reporting is unverified.')); };
      xhr.send(JSON.stringify(body || {}));
    });
  }
  function render(snapshot) {
    byID('inventory').textContent = 'Public inventory: ' + snapshot.inventoryStatus + ' • ' + snapshot.apps.length + ' app entries • completeness not guaranteed.';
    var list = byID('errors'); while (list.firstChild) list.removeChild(list.firstChild);
    snapshot.errors.forEach(function (error) { var item = document.createElement('li'); item.textContent = error; list.appendChild(item); });
  }
  function report() {
    if (!session || reporting || document.hidden) return Promise.resolve();
    reporting = true; var active = session;
    return window.TVGuardianInventory.collect(window.tizen).then(function (snapshot) {
      render(snapshot);
      if (session !== active || document.hidden) return;
      return request(active.base, '/v1/companion/report', 'POST', snapshot, active.token).then(function (result) {
        if (session === active && result.received === true) status('Inventory delivered at ' + new Date().toLocaleTimeString() + '. Enforcement: none.');
      });
    }).catch(function (error) { status(error.message); }).then(function () { reporting = false; });
  }
  byID('pair').addEventListener('click', function () {
    if (session) { status('Stop the current session before pairing again.'); return; }
    try {
      var base = origin(byID('bridge').value.trim()), code = byID('code').value.trim(), instance = randomInstance();
      if (!/^\d{12}$/.test(code)) throw new Error('Enter the 12-digit one-time code from the iPhone.');
      if (!window.tizen) throw new Error('This is not a Tizen TV. No simulated inventory or pairing is available in this browser.');
      byID('pair').disabled = true; status('Pairing over HTTPS…');
      request(base, '/v1/pairing/redeem', 'POST', { code: code, name: byID('name').value.trim(), instanceID: instance }).then(function (result) {
        if (typeof result.token !== 'string' || result.token.length < 40) throw new Error('The bridge did not issue a valid session.');
        session = { base: base, token: result.token }; byID('code').value = '';
        byID('refresh').disabled = false; byID('stop').disabled = false;
        status('Paired. Credentials are held in memory only.'); report(); timer = setInterval(report, 30000);
      }).catch(function (error) { status(error.message); byID('pair').disabled = false; });
    } catch (error) { status(error.message); byID('pair').disabled = false; }
  });
  byID('refresh').addEventListener('click', report);
  byID('stop').addEventListener('click', function () {
    var previous = session; session = null; clearInterval(timer); timer = null; byID('code').value = '';
    byID('pair').disabled = false; byID('refresh').disabled = true; byID('stop').disabled = true;
    if (previous) request(previous.base, '/v1/companion/session', 'DELETE', {}, previous.token).then(function () { status('Session revoked. No further reports will be sent.'); }, function () { status('Local session erased. Bridge revocation was not confirmed; revoke it from the iPhone.'); });
  });
  document.addEventListener('visibilitychange', function () { if (document.hidden) status('App hidden; reporting paused. No system enforcement exists.'); else report(); });
  window.addEventListener('pagehide', function () { session = null; clearInterval(timer); });
  document.addEventListener('keydown', function (event) {
    if ([37, 38, 39, 40].indexOf(event.keyCode) < 0) return;
    if (document.activeElement && document.activeElement.tagName === 'INPUT' && (event.keyCode === 37 || event.keyCode === 39)) return;
    var fields = Array.prototype.filter.call(document.querySelectorAll('input,button'), function (element) { return !element.disabled; });
    var index = fields.indexOf(document.activeElement), direction = event.keyCode === 37 || event.keyCode === 38 ? -1 : 1;
    fields[(index + direction + fields.length) % fields.length].focus(); event.preventDefault();
  });
  byID('bridge').focus();
}());
