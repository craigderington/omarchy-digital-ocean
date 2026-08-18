import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root

  moduleName: "cd.digitalocean"
  ipcTarget: "cd.digitalocean"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var tabs: [
    { id: "droplets", label: "Droplets" },
    { id: "kubernetes", label: "K8s" },
    { id: "databases", label: "Databases" },
    { id: "apps", label: "Apps" },
    { id: "network", label: "Network" },
    { id: "storage", label: "Storage" },
    { id: "domains", label: "Domains" },
    { id: "projects", label: "Projects" }
  ]

  property string selectedTab: "droplets"
  property string query: ""
  property int cursorIndex: 0
  property bool cursorActive: false
  property var pendingAction: null
  readonly property bool confirmOpen: pendingAction !== null
  readonly property var visibleRows: {
    cloud.revision
    return Model.filterRows(rowsForTab(selectedTab), query)
  }

  function stateColor(status) {
    var kind = Model.healthKind(status)
    if (kind === "ok") return "#57d38c"
    if (kind === "busy") return "#e7b955"
    if (kind === "bad") return urgent
    return dim
  }

  function dropletActions(item) {
    var actions = []
    if (item.publicIpv4) actions.push({ id: "ssh", label: "SSH" })
    actions.push({ id: "copy", label: "Copy IP", enabled: item.publicIpv4 !== "" || item.privateIpv4 !== "" })
    if (item.status === "active") {
      actions.push({ id: "reboot", label: "Reboot", danger: true })
      actions.push({ id: "shutdown", label: "Shutdown", danger: true })
      actions.push({ id: "power-off", label: "Power off", danger: true })
    } else if (item.status === "off") {
      actions.push({ id: "power-on", label: "Start" })
    }
    actions.push({ id: "console", label: "Console" })
    return actions
  }

  function rowsForTab(tab) {
    var rows = []
    var i
    var item
    if (tab === "droplets") {
      for (i = 0; i < cloud.droplets.length; i++) {
        item = cloud.droplets[i]
        rows.push({ kind: "droplet", id: item.id, title: item.name, status: item.status,
          meta: [item.region, item.size, item.image].filter(Boolean).join(" · "),
          detail: [item.publicIpv4, item.vcpus ? item.vcpus + " vCPU" : "", item.memoryMb ? Math.round(item.memoryMb / 1024) + " GB RAM" : ""].filter(Boolean).join(" · "),
          source: item, actions: dropletActions(item) })
      }
    } else if (tab === "kubernetes") {
      for (i = 0; i < cloud.kubernetes.length; i++) {
        item = cloud.kubernetes[i]
        rows.push({ kind: "kubernetes", id: item.id, title: item.name, status: item.status,
          meta: [item.region, item.version, item.nodePools + " node pools"].filter(Boolean).join(" · "),
          detail: item.endpoint || item.ipv4 || "", source: item,
          actions: [{ id: "kubeconfig", label: "Kubeconfig" }, { id: "copy", label: "Copy" }, { id: "console", label: "Console" }] })
      }
    } else if (tab === "databases") {
      for (i = 0; i < cloud.databases.length; i++) {
        item = cloud.databases[i]
        rows.push({ kind: "database", id: item.id, title: item.name, status: item.status,
          meta: [item.engine, item.version, item.region].filter(Boolean).join(" · "),
          detail: [item.size, item.nodes ? item.nodes + " nodes" : ""].filter(Boolean).join(" · "), source: item,
          actions: [{ id: "copy", label: "Copy" }, { id: "console", label: "Console" }] })
      }
    } else if (tab === "apps") {
      for (i = 0; i < cloud.apps.length; i++) {
        item = cloud.apps[i]
        var appActions = []
        if (item.ingress) appActions.push({ id: "open-app", label: "Open app" })
        appActions.push({ id: "copy", label: "Copy" })
        appActions.push({ id: "console", label: "Console" })
        rows.push({ kind: "app", id: item.id, title: item.name, status: item.status,
          meta: [item.region, item.tier].filter(Boolean).join(" · "), detail: item.ingress || "", source: item, actions: appActions })
      }
    } else if (tab === "network") {
      for (i = 0; i < cloud.loadBalancers.length; i++) {
        item = cloud.loadBalancers[i]
        rows.push({ kind: "loadBalancer", id: item.id, title: item.name, status: item.status,
          meta: [item.region, item.size, item.algorithm].filter(Boolean).join(" · "), detail: item.ip || "", source: item,
          actions: [{ id: "copy", label: "Copy IP", enabled: item.ip !== "" }, { id: "console", label: "Console" }] })
      }
    } else if (tab === "storage") {
      for (i = 0; i < cloud.volumes.length; i++) {
        item = cloud.volumes[i]
        rows.push({ kind: "volume", id: item.id, title: item.name, status: item.dropletIds.length ? "attached" : "unattached",
          meta: [item.region, item.sizeGb + " GB"].filter(Boolean).join(" · "), detail: item.description || "", source: item,
          actions: [{ id: "copy", label: "Copy" }, { id: "console", label: "Console" }] })
      }
      for (i = 0; i < cloud.snapshots.length; i++) {
        item = cloud.snapshots[i]
        rows.push({ kind: "snapshot", id: item.id, title: item.name, status: "snapshot",
          meta: [item.resourceType, item.sizeGb + " GB"].filter(Boolean).join(" · "), detail: (item.regions || []).join(", "), source: item,
          actions: [{ id: "copy", label: "Copy" }, { id: "console", label: "Console" }] })
      }
    } else if (tab === "domains") {
      for (i = 0; i < cloud.domains.length; i++) {
        item = cloud.domains[i]
        rows.push({ kind: "domain", id: item.name, title: item.name, status: "active", meta: "TTL " + item.ttl, detail: "", source: item,
          actions: [{ id: "copy", label: "Copy" }, { id: "console", label: "DNS" }] })
      }
    } else if (tab === "projects") {
      for (i = 0; i < cloud.projects.length; i++) {
        item = cloud.projects[i]
        rows.push({ kind: "project", id: item.id, title: item.name, status: item.isDefault ? "default" : item.environment,
          meta: [item.purpose, item.environment].filter(Boolean).join(" · "), detail: item.description || "", source: item,
          actions: [{ id: "copy", label: "Copy" }, { id: "console", label: "Console" }] })
      }
    }
    return rows
  }

  function contextNames() {
    return cloud.contexts.map(function(item) { return String(item.name || "") })
  }

  function openUrl(url) {
    if (!url) return
    Quickshell.execDetached(["omarchy-launch-browser", String(url)])
    close()
  }

  function copyText(value, label) {
    if (!value) return
    Quickshell.execDetached(["wl-copy", "-n", "--", String(value)])
    cloud.actionStatus = "Copied " + String(label || value)
  }

  function executeRowAction(row, action) {
    if (!row) return
    if (action === "console") {
      openUrl(Model.consoleUrl(row.kind, row.id))
    } else if (action === "open-app") {
      openUrl(row.source.ingress)
    } else if (action === "copy") {
      var target = Model.copyTarget(row)
      copyText(target.value, target.label)
    } else if (action === "ssh") {
      if (!row.source.publicIpv4) return
      Quickshell.execDetached(["omarchy-launch-terminal", "--", "ssh", String(row.source.publicIpv4)])
      close()
    } else if (action === "kubeconfig") {
      var command = ["omarchy-launch-terminal", "--", "doctl"]
      if (cloud.currentContext !== "") command.push("--context", cloud.currentContext)
      command.push("kubernetes", "cluster", "kubeconfig", "save", String(row.id))
      Quickshell.execDetached(command)
      close()
    } else if (["power-on", "shutdown", "power-off", "reboot"].indexOf(action) !== -1) {
      var request = { action: action, id: String(row.id), name: String(row.title), context: cloud.currentContext }
      if (Model.isDisruptiveAction(action)) pendingAction = request
      else cloud.runDropletAction(action, String(row.id))
    }
  }

  function confirmPendingAction() {
    var request = pendingAction
    pendingAction = null
    if (!request) return
    if (request.context !== cloud.currentContext) {
      cloud.actionStatus = "Context changed. Confirm the action again."
      return
    }
    cloud.runDropletAction(request.action, request.id)
  }

  function activateCursor() {
    if (visibleRows.length === 0) return
    executeRowAction(visibleRows[Math.max(0, Math.min(cursorIndex, visibleRows.length - 1))], "console")
  }

  function selectTabByOffset(delta) {
    var index = 0
    for (var i = 0; i < tabs.length; i++) {
      if (tabs[i].id === selectedTab) { index = i; break }
    }
    selectedTab = tabs[Math.max(0, Math.min(tabs.length - 1, index + delta))].id
  }

  function moveCursor(delta) {
    cursorActive = true
    if (visibleRows.length === 0) return
    cursorIndex = Math.max(0, Math.min(visibleRows.length - 1, cursorIndex + delta))
    Qt.callLater(scrollCursorIntoView)
  }

  function scrollCursorIntoView() {
    var item = resourceRepeater.itemAt(cursorIndex)
    if (!item) return
    var point = item.mapToItem(resourceFlick.contentItem, 0, 0)
    var margin = Style.space(8)
    if (point.y < resourceFlick.contentY + margin) resourceFlick.contentY = Math.max(0, point.y - margin)
    else if (point.y + item.height > resourceFlick.contentY + resourceFlick.height - margin)
      resourceFlick.contentY = Math.min(Math.max(0, resourceFlick.contentHeight - resourceFlick.height), point.y + item.height + margin - resourceFlick.height)
  }

  function tabCount(id) {
    if (id === "network") return cloud.loadBalancers.length
    if (id === "storage") return cloud.volumes.length + cloud.snapshots.length
    return (cloud[id] || []).length
  }

  onVisibleRowsChanged: cursorIndex = Math.max(0, Math.min(cursorIndex, visibleRows.length - 1))
  onSelectedTabChanged: { cursorIndex = 0; cursorActive = false; resourceFlick.contentY = 0 }
  onPendingActionChanged: {
    if (pendingAction) Qt.callLater(function() { confirmButton.forceActiveFocus() })
    else if (opened && !search.activeFocus) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onOpenedChanged: {
    if (opened) {
      pendingAction = null
      cursorIndex = 0
      cursorActive = false
      cloud.refresh()
      cloud.refreshContexts()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      query = ""
      pendingAction = null
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Service { id: cloud; settings: root.settings; panelOpen: root.opened }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { cloud.refresh(); return "ok" }
    function status(): string { return cloud.state }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    active: cloud.unhealthy || cloud.state === "error"
    activeColor: root.urgent
    tooltipText: {
      if (cloud.state !== "ready") return "DigitalOcean · " + cloud.message
      var lines = ["DigitalOcean" + (cloud.currentContext ? " · " + cloud.currentContext : "")]
      lines.push(Number(cloud.summary.runningDroplets || 0) + "/" + Number(cloud.summary.totalDroplets || 0) + " Droplets active")
      if (Number(cloud.summary.totalKubernetes || 0) > 0) lines.push(Number(cloud.summary.healthyKubernetes || 0) + "/" + Number(cloud.summary.totalKubernetes || 0) + " Kubernetes healthy")
      if (Number(cloud.summary.totalApps || 0) > 0) lines.push(Number(cloud.summary.activeApps || 0) + "/" + Number(cloud.summary.totalApps || 0) + " Apps active")
      lines.push("Balance: " + Model.formatCurrency(cloud.billing.accountBalance || 0))
      if (Number(cloud.summary.errorCount || 0) > 0) lines.push(Number(cloud.summary.errorCount) + " API errors")
      return lines.join("\n")
    }
    onPressed: function(code) {
      if (code === Qt.MiddleButton || code === Qt.RightButton) cloud.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(panelContent.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: search.activeFocus || contextPicker.popupOpen || root.confirmOpen
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.selectTabByOffset(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: {
        if (root.confirmOpen) root.pendingAction = null
        else if (root.query !== "") root.query = ""
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r" || text === "R") cloud.refresh()
        else if (text === "/") Qt.callLater(function() { search.forceActiveFocus() })
        else if ((text === "c" || text === "C") && contextPicker.visible && contextPicker.enabled) contextPicker.toggle()
        else if (text >= "1" && text <= "8") root.selectedTab = root.tabs[Number(text) - 1].id
      }

      ColumnLayout {
        id: panelContent
        anchors.fill: parent
        spacing: Style.space(10)

        PanelHero {
          Layout.fillWidth: true
          title: cloud.account.email ? "DigitalOcean · " + cloud.account.email : "DigitalOcean"
          meta: cloud.loading ? "Refreshing infrastructure…" :
            Model.countLabel(cloud.summary.runningDroplets, "active Droplet") + " · " +
            Model.countLabel(cloud.summary.healthyKubernetes, "healthy cluster") + " · " +
            Model.formatCurrency(cloud.billing.accountBalance || 0) + " balance"
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          TextField {
            id: search
            Layout.fillWidth: true
            foreground: root.foreground
            font.family: root.fontFamily
            placeholderText: "Filter resources  /"
            text: root.query
            onTextChanged: root.query = text
            Keys.onEscapePressed: function(event) {
              root.query = ""
              keyCatcher.forceActiveFocus()
              event.accepted = true
            }
          }

          Dropdown {
            id: contextPicker
            visible: cloud.contexts.length > 1
            enabled: !cloud.contextTransitioning && cloud.actionInProgress === ""
            opacity: enabled ? 1 : 0.5
            showLabel: false
            Layout.preferredWidth: Style.space(150)
            Layout.alignment: Qt.AlignVCenter
            foreground: root.foreground
            fontFamily: root.fontFamily
            options: root.contextNames()
            value: cloud.currentContext
            onChanged: function(name) { cloud.selectContext(String(name)) }
          }
        }

        Flow {
          Layout.fillWidth: true
          spacing: Style.space(5)

          Repeater {
            model: root.tabs
            Button {
              required property var modelData
              text: modelData.label + "  " + root.tabCount(modelData.id)
              selected: root.selectedTab === modelData.id
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onClicked: root.selectedTab = modelData.id
            }
          }
        }

        BorderSurface {
          visible: cloud.state !== "ready" || Object.keys(cloud.errors).length > 0
          Layout.fillWidth: true
          implicitHeight: errorText.implicitHeight + Style.space(18)
          color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.10)
          borderSpec: Border.flat(Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.35), 1)
          radius: Style.cornerRadius

          Text {
            id: errorText
            anchors.fill: parent
            anchors.margins: Style.space(9)
            text: {
              if (cloud.state !== "ready") return cloud.message
              var names = Object.keys(cloud.errors)
              return "Partial results · " + names.map(function(name) { return name + ": " + cloud.errors[name] }).join(" · ")
            }
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
          }
        }

        BorderSurface {
          visible: root.confirmOpen
          Layout.fillWidth: true
          implicitHeight: confirmBody.implicitHeight + Style.space(18)
          color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.10)
          borderSpec: Border.flat(Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.45), 1)
          radius: Style.cornerRadius

          RowLayout {
            id: confirmBody
            anchors.fill: parent
            anchors.margins: Style.space(9)
            spacing: Style.space(8)
            Text {
              Layout.fillWidth: true
              text: root.pendingAction ? "Confirm " + root.pendingAction.action + " on " + root.pendingAction.name
                + " (ID " + root.pendingAction.id + ") in context " + (root.pendingAction.context || "default") + "?" : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
            }
            Button {
              id: cancelConfirmButton
              text: "Cancel"
              foreground: root.foreground
              focusable: true
              onClicked: root.pendingAction = null
              Keys.onEscapePressed: function(event) { root.pendingAction = null; event.accepted = true }
            }
            Button {
              id: confirmButton
              text: "Confirm"
              foreground: root.urgent
              selected: true
              focusable: true
              onClicked: root.confirmPendingAction()
              Keys.onEscapePressed: function(event) { root.pendingAction = null; event.accepted = true }
            }
          }
        }

        Text {
          visible: cloud.actionStatus !== ""
          Layout.fillWidth: true
          text: cloud.actionStatus
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }

        Text {
          visible: root.visibleRows.length === 0 && !cloud.loading
          Layout.fillWidth: true
          text: root.query ? "No resources match this filter." : "No resources in this category."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
        }

        Flickable {
          id: resourceFlick
          visible: root.visibleRows.length > 0
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.minimumHeight: Style.space(90)
          Layout.preferredHeight: Math.min(resourceColumn.implicitHeight, Style.space(470))
          contentWidth: width
          contentHeight: resourceColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: resourceColumn
            width: resourceFlick.width
            spacing: Style.space(6)

            Repeater {
              id: resourceRepeater
              model: root.visibleRows
              ResourceRow {
                required property var modelData
                required property int index
                width: resourceColumn.width
                title: modelData.title
                meta: modelData.meta
                detail: modelData.detail
                status: modelData.status
                statusColor: root.stateColor(modelData.status)
                foreground: root.foreground
                dim: root.dim
                fontFamily: root.fontFamily
                actions: modelData.actions || []
                selected: root.cursorActive && root.cursorIndex === index
                busy: cloud.loading || cloud.contextTransitioning || cloud.actionInProgress !== ""
                onActivated: {
                  root.cursorActive = true
                  root.cursorIndex = index
                  root.executeRowAction(modelData, "console")
                }
                onActionRequested: function(action) {
                  root.cursorActive = true
                  root.cursorIndex = index
                  root.executeRowAction(modelData, action)
                }
              }
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)
          Text {
            text: "R refresh · / search · 1–8 or H/L category · J/K navigate · Enter open" + (contextPicker.visible ? " · C context" : "")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            Layout.fillWidth: true
          }
          Text {
            text: "MTD " + Model.formatCurrency(cloud.billing.monthToDateUsage || 0)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
