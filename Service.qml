import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property bool panelOpen: false
  property bool loading: false
  property string state: "loading"
  property string message: "Loading DigitalOcean…"
  property string currentContext: ""
  property var contexts: []
  property var account: ({})
  property var billing: ({})
  property var summary: ({})
  property var errors: ({})
  property var droplets: []
  property var kubernetes: []
  property var databases: []
  property var apps: []
  property var loadBalancers: []
  property var volumes: []
  property var snapshots: []
  property var domains: []
  property var projects: []
  property int revision: 0
  property bool refreshQueued: false
  property string fetchContext: ""
  property bool contextTransitioning: false
  property string actionStatus: ""
  property string actionInProgress: ""
  property string _stdout: ""
  property string _stderr: ""
  property string _actionStdout: ""
  property string _actionStderr: ""
  property var previousHealth: ({ "droplets": [], "kubernetes": [], "databases": [], "apps": [] })
  property bool initialLoad: true
  property bool bootstrapped: false

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 60, 30, 3600)
  readonly property int idleRefreshIntervalSec: Math.max(refreshIntervalSec, intSetting("idleRefreshIntervalSec", 600, 60, 7200))
  readonly property bool notificationsEnabled: boolSetting("notificationsEnabled", true)
  readonly property real lowBalanceThreshold: numberSetting("lowBalanceThreshold", 10, 0, 10000)
  readonly property bool unhealthy: Number(summary.errorCount || 0) > 0
    || Number(summary.failedApps || 0) > 0
    || droplets.some(function(item) { return Model.healthKind(item.status) === "bad" })
    || kubernetes.some(function(item) { return Model.healthKind(item.status) === "bad" })
    || databases.some(function(item) { return Model.healthKind(item.status) === "bad" })
    || loadBalancers.some(function(item) { return Model.healthKind(item.status) === "bad" })
    || (Number(billing.accountBalance || 0) > 0 && Number(billing.accountBalance) < lowBalanceThreshold)

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, minimum, maximum) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  function numberSetting(name, fallback, minimum, maximum) {
    var value = Number(setting(name, fallback))
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  function boolSetting(name, fallback) {
    var value = setting(name, fallback)
    if (value === true || value === false) return value
    var text = String(value).toLowerCase()
    return text === "true" || text === "yes" || text === "on" || text === "1"
  }

  function helperPath() {
    return Qt.resolvedUrl("omarchy-digitalocean-fetch").toString().replace(/^file:\/\//, "")
  }

  function dashboardCommand(context) {
    var command = [helperPath(), "dashboard"]
    if (context !== "") command.push("--context", context)
    return command
  }

  function refresh() {
    if (fetchProcess.running || actionProcess.running) {
      refreshQueued = true
      return
    }
    refreshQueued = false
    loading = true
    _stdout = ""
    _stderr = ""
    fetchContext = currentContext
    fetchProcess.command = dashboardCommand(fetchContext)
    fetchProcess.running = true
  }

  function refreshContexts() {
    if (contextProcess.running) return
    contextProcess.command = [helperPath(), "contexts"]
    contextProcess.running = true
  }

  function selectContext(name) {
    var value = String(name || "")
    if (value === currentContext) return
    currentContext = value
    contextTransitioning = true
    initialLoad = true
    previousHealth = ({ "droplets": [], "kubernetes": [], "databases": [], "apps": [] })
    refresh()
  }

  function runDropletAction(action, id) {
    if (contextTransitioning) {
      actionStatus = "Wait for the selected context to finish loading."
      actionStatusTimer.restart()
      return
    }
    if (actionProcess.running) {
      actionStatus = "Another Droplet action is still running."
      actionStatusTimer.restart()
      return
    }
    if (fetchProcess.running) {
      actionStatus = "Wait for the current refresh to finish."
      actionStatusTimer.restart()
      return
    }
    actionInProgress = String(action) + ":" + String(id)
    actionStatus = "Running " + String(action) + "…"
    _actionStdout = ""
    _actionStderr = ""
    var command = [helperPath(), "droplet-action"]
    if (currentContext !== "") command.push("--context", currentContext)
    command.push("--action", String(action), "--target", String(id))
    actionProcess.command = command
    actionProcess.running = true
  }

  function notify(title, body, urgency) {
    Quickshell.execDetached(["notify-send", "-a", "DigitalOcean", "-u", urgency || "normal", "-i", "network-server", title, body])
  }

  function healthNotifications(oldData, newData) {
    if (!notificationsEnabled || initialLoad) return
    var groups = [
      ["Droplet", oldData.droplets || [], newData.droplets || []],
      ["Kubernetes cluster", oldData.kubernetes || [], newData.kubernetes || []],
      ["Database", oldData.databases || [], newData.databases || []],
      ["App", oldData.apps || [], newData.apps || []]
    ]
    for (var i = 0; i < groups.length; i++) {
      var changes = Model.healthChanges(groups[i][1], groups[i][2])
      for (var j = 0; j < changes.length; j++) {
        notify(groups[i][0] + " needs attention", changes[j].name + ": " + changes[j].previous + " → " + changes[j].status, "critical")
      }
    }
    var oldBalance = Number((oldData.billing || {}).accountBalance || 0)
    var newBalance = Number((newData.billing || {}).accountBalance || 0)
    if (newBalance > 0 && newBalance < lowBalanceThreshold && (oldBalance === 0 || oldBalance >= lowBalanceThreshold))
      notify("DigitalOcean balance is low", Model.formatCurrency(newBalance) + " remaining", "critical")
  }

  function apply(raw) {
    var data = Model.parseData(raw)
    if (!data || Object.keys(data).length === 0) {
      state = "error"
      message = "DigitalOcean returned an unreadable response."
      return
    }

    var incoming = {
      "account": data.account || ({}),
      "billing": data.billing || ({}),
      "droplets": Array.isArray(data.droplets) ? data.droplets : [],
      "kubernetes": Array.isArray(data.kubernetes) ? data.kubernetes : [],
      "databases": Array.isArray(data.databases) ? data.databases : [],
      "apps": Array.isArray(data.apps) ? data.apps : [],
      "loadBalancers": Array.isArray(data.loadBalancers) ? data.loadBalancers : [],
      "volumes": Array.isArray(data.volumes) ? data.volumes : [],
      "snapshots": Array.isArray(data.snapshots) ? data.snapshots : [],
      "domains": Array.isArray(data.domains) ? data.domains : [],
      "projects": Array.isArray(data.projects) ? data.projects : []
    }
    var current = {
      "account": account, "billing": billing, "droplets": droplets,
      "kubernetes": kubernetes, "databases": databases, "apps": apps,
      "loadBalancers": loadBalancers, "volumes": volumes, "snapshots": snapshots,
      "domains": domains, "projects": projects
    }
    var resourceErrors = data.errors || ({})
    var retained = Model.preserveFailed(current, incoming, resourceErrors, Object.keys(incoming))
    var next = {
      "droplets": retained.droplets,
      "kubernetes": retained.kubernetes,
      "databases": retained.databases,
      "apps": retained.apps,
      "billing": retained.billing
    }
    healthNotifications(previousHealth, next)

    account = retained.account
    billing = retained.billing
    summary = Model.preserveSummary(summary, data.summary || ({}), resourceErrors)
    errors = resourceErrors
    droplets = retained.droplets
    kubernetes = retained.kubernetes
    databases = retained.databases
    apps = retained.apps
    loadBalancers = retained.loadBalancers
    volumes = retained.volumes
    snapshots = retained.snapshots
    domains = retained.domains
    projects = retained.projects
    previousHealth = next
    state = String(data.state || "error")
    message = String(data.message || data.error || "")
    revision++
    initialLoad = false
  }

  visible: false

  Timer {
    id: refreshTimer
    interval: (root.panelOpen ? root.refreshIntervalSec : root.idleRefreshIntervalSec) * 1000
    repeat: true
    running: true
    triggeredOnStart: false
    onTriggered: root.refresh()
  }

  Timer {
    id: actionStatusTimer
    interval: 3500
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Process {
    id: fetchProcess
    command: []
    onExited: function(exitCode) {
      var stdout = String(fetchOutput.text || root._stdout || "")
      var stderr = String(fetchErrors.text || root._stderr || "").trim()
      if (root.fetchContext !== root.currentContext) {
        root.refreshQueued = false
        root.loading = true
        Qt.callLater(root.refresh)
        return
      }

      root.loading = false
      if (stdout.trim() !== "") root.apply(stdout)
      else {
        root.state = "error"
        root.message = stderr !== "" ? stderr : "DigitalOcean refresh failed."
      }
      root.contextTransitioning = false
      if (root.refreshQueued) {
        root.refreshQueued = false
        Qt.callLater(root.refresh)
      }
    }
    stdout: StdioCollector {
      id: fetchOutput
      waitForEnd: true
      onStreamFinished: root._stdout = text
    }
    stderr: StdioCollector {
      id: fetchErrors
      waitForEnd: true
      onStreamFinished: root._stderr = text
    }
  }

  Process {
    id: contextProcess
    command: []
    onExited: function(exitCode) {
      var result = Model.parseData(String(contextOutput.text || ""))
      root.contexts = Array.isArray(result.contexts) ? result.contexts : []
      var current = ""
      for (var i = 0; i < root.contexts.length; i++) {
        if (root.contexts[i].current) {
          current = String(root.contexts[i].name || "")
          break
        }
      }
      if (root.currentContext === "" && current !== "") root.selectContext(current)
      // doctl may be missing or unauthenticated; the dashboard still runs so the
      // panel reports why instead of sitting on the loading placeholder.
      else if (!root.bootstrapped) root.refresh()
      root.bootstrapped = true
    }
    stdout: StdioCollector { id: contextOutput; waitForEnd: true }
  }

  Process {
    id: actionProcess
    command: []
    onExited: function(exitCode) {
      var response = Model.parseData(String(actionOutput.text || root._actionStdout || ""))
      if (exitCode === 0 && response.success === true)
        root.actionStatus = "Action completed. Refreshing…"
      else
        root.actionStatus = String(response.error || actionErrors.text || root._actionStderr || "DigitalOcean action failed.").trim()
      root.actionInProgress = ""
      actionStatusTimer.restart()
      Qt.callLater(root.refresh)
    }
    stdout: StdioCollector {
      id: actionOutput
      waitForEnd: true
      onStreamFinished: root._actionStdout = text
    }
    stderr: StdioCollector {
      id: actionErrors
      waitForEnd: true
      onStreamFinished: root._actionStderr = text
    }
  }

  Component.onCompleted: refreshContexts()
}
