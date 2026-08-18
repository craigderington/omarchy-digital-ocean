.pragma library

function parseData(raw) {
  try {
    var parsed = JSON.parse(String(raw || ""))
    return parsed && typeof parsed === "object" ? parsed : {}
  } catch (error) {
    return {}
  }
}

function healthKind(status) {
  var value = String(status || "").toLowerCase()
  if (["active", "online", "running", "provisioned", "deployed", "completed"].indexOf(value) !== -1) return "ok"
  if (["pending", "new", "creating", "provisioning", "deploying", "warning"].indexOf(value) !== -1) return "busy"
  if (["off", "offline", "failed", "error", "degraded", "canceled", "cancelled", "errored"].indexOf(value) !== -1) return "bad"
  return "idle"
}

function isDisruptiveAction(action) {
  return ["shutdown", "power-off", "reboot"].indexOf(String(action || "")) !== -1
}

function encodePath(value) {
  return encodeURIComponent(String(value || ""))
}

function consoleUrl(kind, id) {
  var routes = {
    "droplet": "droplets/",
    "kubernetes": "kubernetes/clusters/",
    "database": "databases/",
    "app": "apps/",
    "loadBalancer": "networking/load-balancers/",
    "volume": "volumes/",
    "snapshot": "images/snapshots/",
    "domain": "networking/domains/",
    "project": "projects/"
  }
  var route = routes[String(kind || "")]
  return route ? "https://cloud.digitalocean.com/" + route + encodePath(id) : "https://cloud.digitalocean.com/"
}

function formatCurrency(value) {
  var number = Number(value)
  return "$" + (isFinite(number) ? number : 0).toFixed(2)
}

function searchableText(row) {
  var parts = []
  for (var key in row) {
    if (!Object.prototype.hasOwnProperty.call(row, key)) continue
    var value = row[key]
    if (typeof value === "string" || typeof value === "number") parts.push(String(value))
    else if (Array.isArray(value)) parts.push(value.join(" "))
  }
  return parts.join(" ").toLowerCase()
}

function filterRows(rows, query) {
  var needle = String(query || "").trim().toLowerCase()
  if (!needle) return rows || []
  return (rows || []).filter(function(row) { return searchableText(row).indexOf(needle) !== -1 })
}

function countLabel(count, singular, plural) {
  var number = Number(count) || 0
  return number + " " + (number === 1 ? String(singular) : String(plural || singular + "s"))
}

// Non-secret value a row's Copy action puts on the clipboard. Falls back to
// the resource identifier when the richer address is absent, so Copy always
// yields something the DigitalOcean console can be searched with.
function copyTarget(row) {
  var source = (row && row.source) || {}
  var kind = String((row && row.kind) || "")
  var id = String((row && row.id) || "")
  if (kind === "droplet") {
    var address = String(source.publicIpv4 || source.privateIpv4 || "")
    return address ? { value: address, label: "Droplet address" } : { value: id, label: "Droplet ID" }
  }
  if (kind === "loadBalancer")
    return source.ip ? { value: String(source.ip), label: "Load balancer IP" } : { value: id, label: "Load balancer ID" }
  if (kind === "kubernetes")
    return source.endpoint ? { value: String(source.endpoint), label: "Cluster endpoint" } : { value: id, label: "Cluster ID" }
  if (kind === "app")
    return source.ingress ? { value: String(source.ingress), label: "App URL" } : { value: id, label: "App ID" }
  if (kind === "domain") return { value: id, label: "Domain" }
  return { value: id, label: "Identifier" }
}

function preserveFailed(current, incoming, errors, keys) {
  var result = {}
  ;(keys || []).forEach(function(key) {
    result[key] = errors && errors[key] !== undefined ? current[key] : incoming[key]
  })
  return result
}

function preserveSummary(current, incoming, errors) {
  var result = {}
  for (var key in incoming) {
    if (Object.prototype.hasOwnProperty.call(incoming, key)) result[key] = incoming[key]
  }
  var fields = {
    "droplets": ["totalDroplets", "runningDroplets"],
    "kubernetes": ["healthyKubernetes", "totalKubernetes"],
    "databases": ["healthyDatabases", "totalDatabases"],
    "apps": ["activeApps", "failedApps", "totalApps"],
    "loadBalancers": ["healthyLoadBalancers", "totalLoadBalancers"]
  }
  for (var category in fields) {
    if (!errors || errors[category] === undefined) continue
    fields[category].forEach(function(field) {
      if (current[field] !== undefined) result[field] = current[field]
    })
  }
  return result
}

function healthChanges(previous, current) {
  var oldById = {}
  var changes = []
  ;(previous || []).forEach(function(item) { oldById[String(item.id || "")] = item })
  ;(current || []).forEach(function(item) {
    var old = oldById[String(item.id || "")]
    if (!old) return
    var before = healthKind(old.status)
    var after = healthKind(item.status)
    if (before !== "bad" && after === "bad") {
      changes.push({ id: String(item.id || ""), name: String(item.name || "resource"), previous: String(old.status || ""), status: String(item.status || "") })
    }
  })
  return changes
}
