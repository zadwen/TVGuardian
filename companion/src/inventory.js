(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.TVGuardianInventory = factory();
}(this, function () {
  'use strict';
  function apiError(prefix, error) { return prefix + ': ' + (error && typeof error.name === 'string' ? error.name.slice(0, 80) : 'UnknownError'); }
  function call(api, method, timeoutMS) {
    return new Promise(function (resolve, reject) {
      var done = false;
      var timer = setTimeout(function () { if (!done) { done = true; reject({ name: 'TimeoutError' }); } }, timeoutMS);
      function finish(error, result) { if (done) return; done = true; clearTimeout(timer); if (error) reject(error); else resolve(result); }
      try { api[method](function (result) { finish(null, result); }, function (error) { finish(error); }); }
      catch (error) { finish(error); }
    });
  }
  function optionalString(object, property, maximum) {
    try { var value = object[property]; return typeof value === 'string' && value.length && value.length <= maximum && !/[\u0000-\u001f\u007f]/.test(value) ? value : undefined; }
    catch (_) { return undefined; }
  }
  function collect(tizenAPI, timeoutMS) {
    var snapshot = { protocolVersion: 1, inventoryStatus: 'unverified', complete: false, apps: [], errors: [] };
    if (!tizenAPI || !tizenAPI.application || typeof tizenAPI.application.getAppsInfo !== 'function') {
      snapshot.inventoryStatus = 'unsupported'; snapshot.errors.push('Application API unavailable on this device.'); return Promise.resolve(snapshot);
    }
    return call(tizenAPI.application, 'getAppsInfo', timeoutMS || 8000).then(function (apps) {
      if (!Array.isArray(apps) || apps.length > 2000) throw { name: 'InvalidResponseError' };
      var seen = Object.create(null);
      apps.forEach(function (app) {
        var id = optionalString(app, 'id', 256);
        if (!id || !/^[A-Za-z0-9._-]+$/.test(id) || seen[id]) return;
        seen[id] = true;
        var item = { id: id, name: optionalString(app, 'name', 160) || id };
        var packageID = optionalString(app, 'packageId', 256), iconPath = optionalString(app, 'iconPath', 512);
        if (packageID) item.packageID = packageID;
        if (iconPath) item.iconPath = iconPath;
        snapshot.apps.push(item);
      });
      snapshot.inventoryStatus = 'supported';
      if (!tizenAPI.package || typeof tizenAPI.package.getPackagesInfo !== 'function') {
        snapshot.errors.push('Package API unavailable; application inventory may be incomplete.'); return snapshot;
      }
      return call(tizenAPI.package, 'getPackagesInfo', timeoutMS || 8000).then(function (packages) {
        if (!Array.isArray(packages)) snapshot.errors.push('Package API returned an unknown format.');
        // No preinstalled flag or removability inference: neither is an authorized
        // system-app classification supplied by these public TV Web interfaces.
        return snapshot;
      }, function (error) { snapshot.errors.push(apiError('Package information denied or unavailable', error)); return snapshot; });
    }).catch(function (error) {
      snapshot.apps = []; snapshot.inventoryStatus = error && error.name === 'NotSupportedError' ? 'unsupported' : 'unverified';
      snapshot.errors.push(apiError('Application inventory denied or unavailable', error)); return snapshot;
    });
  }
  return { collect: collect };
}));
