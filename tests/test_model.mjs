#!/usr/bin/env node
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";

const source = fs.readFileSync(new URL("../Model.js", import.meta.url), "utf8").replace(/^\.pragma library\s*/m, "");
const context = {};
vm.createContext(context);
vm.runInContext(source, context);

const plain = (value) => JSON.parse(JSON.stringify(value));

assert.deepEqual(plain(context.parseData('{"state":"ready"}')), { state: "ready" });
assert.deepEqual(plain(context.parseData("not-json")), {});
assert.equal(context.healthKind("active"), "ok");
assert.equal(context.healthKind("running"), "ok");
assert.equal(context.healthKind("warning"), "busy");
assert.equal(context.healthKind("failed"), "bad");
assert.equal(context.healthKind("unknown"), "idle");
assert.equal(context.isDisruptiveAction("shutdown"), true);
assert.equal(context.isDisruptiveAction("power-on"), false);
assert.equal(context.consoleUrl("droplet", "42"), "https://cloud.digitalocean.com/droplets/42");
assert.equal(context.consoleUrl("domain", "example.com"), "https://cloud.digitalocean.com/networking/domains/example.com");
assert.equal(context.formatCurrency(45.6), "$45.60");
assert.deepEqual(
  plain(context.filterRows([{ name: "Web API", region: "nyc3" }, { name: "Worker", region: "sfo3" }], "NYC")),
  [{ name: "Web API", region: "nyc3" }],
);
assert.deepEqual(
  plain(context.healthChanges(
    [{ id: "1", name: "db", status: "online" }],
    [{ id: "1", name: "db", status: "degraded" }, { id: "2", name: "new", status: "failed" }],
  )),
  [{ id: "1", name: "db", previous: "online", status: "degraded" }],
);

assert.deepEqual(
  plain(context.preserveFailed(
    { droplets: [{ id: "old" }], apps: [{ id: "old-app" }], billing: { accountBalance: 20 } },
    { droplets: [], apps: [{ id: "new-app" }], billing: {} },
    { droplets: "timeout", billing: "rate limited" },
    ["droplets", "apps", "billing"],
  )),
  { droplets: [{ id: "old" }], apps: [{ id: "new-app" }], billing: { accountBalance: 20 } },
);

assert.deepEqual(
  plain(context.preserveSummary(
    { totalDroplets: 3, runningDroplets: 2, totalApps: 1, activeApps: 1, errorCount: 0 },
    { totalDroplets: 0, runningDroplets: 0, totalApps: 2, activeApps: 2, errorCount: 1 },
    { droplets: "timeout" },
  )),
  { totalDroplets: 3, runningDroplets: 2, totalApps: 2, activeApps: 2, errorCount: 1 },
);

assert.equal(context.countLabel(1, "active Droplet"), "1 active Droplet");
assert.equal(context.countLabel(0, "active Droplet"), "0 active Droplets");
assert.equal(context.countLabel(3, "healthy cluster"), "3 healthy clusters");
assert.equal(context.countLabel(undefined, "active Droplet"), "0 active Droplets");

assert.deepEqual(
  plain(context.copyTarget({ kind: "droplet", id: "42", source: { publicIpv4: "203.0.113.10", privateIpv4: "10.0.0.4" } })),
  { value: "203.0.113.10", label: "Droplet address" },
);
assert.deepEqual(
  plain(context.copyTarget({ kind: "droplet", id: "42", source: { publicIpv4: "", privateIpv4: "10.0.0.4" } })),
  { value: "10.0.0.4", label: "Droplet address" },
);
assert.deepEqual(
  plain(context.copyTarget({ kind: "droplet", id: "42", source: {} })),
  { value: "42", label: "Droplet ID" },
);
assert.deepEqual(
  plain(context.copyTarget({ kind: "loadBalancer", id: "lb1", source: { ip: "198.51.100.7" } })),
  { value: "198.51.100.7", label: "Load balancer IP" },
);
assert.deepEqual(
  plain(context.copyTarget({ kind: "app", id: "a1", source: { ingress: "https://portal.example.com" } })),
  { value: "https://portal.example.com", label: "App URL" },
);
assert.deepEqual(
  plain(context.copyTarget({ kind: "domain", id: "example.com", source: { name: "example.com" } })),
  { value: "example.com", label: "Domain" },
);
assert.deepEqual(
  plain(context.copyTarget({ kind: "database", id: "db1", source: { engine: "pg" } })),
  { value: "db1", label: "Identifier" },
);
// A database row must never offer a connection string or credential.
assert.deepEqual(
  plain(context.copyTarget({ kind: "database", id: "db1", source: { connection: { password: "do-not-leak" } } })),
  { value: "db1", label: "Identifier" },
);

console.log("Model.js tests passed");
