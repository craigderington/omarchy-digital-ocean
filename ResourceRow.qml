import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  property string title: ""
  property string meta: ""
  property string detail: ""
  property string status: ""
  property color foreground: Color.foreground
  property color dim: Qt.darker(foreground, 1.5)
  property color statusColor: dim
  property string fontFamily: Style.font.family
  property var actions: []
  property bool selected: false
  property bool busy: false
  signal activated()
  signal actionRequested(string action)

  color: selected ? Qt.rgba(foreground.r, foreground.g, foreground.b, 0.10) : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.045)
  borderSpec: Border.flat(selected ? Qt.rgba(foreground.r, foreground.g, foreground.b, 0.35) : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.08), 1)
  radius: Style.cornerRadius
  padding: Style.space(9)
  implicitHeight: body.implicitHeight + contentTopInset + contentBottomInset

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }

  ColumnLayout {
    id: body
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: parent.contentLeftInset
    spacing: Style.space(5)

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.space(7)

      Rectangle {
        Layout.preferredWidth: Style.space(7)
        Layout.preferredHeight: Style.space(7)
        Layout.alignment: Qt.AlignVCenter
        radius: width / 2
        color: root.statusColor
      }

      Text {
        text: root.title
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        textFormat: Text.PlainText
        elide: Text.ElideRight
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        text: root.status
        color: root.statusColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText
        Layout.alignment: Qt.AlignVCenter
      }
    }

    Text {
      visible: text !== ""
      text: root.meta
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      textFormat: Text.PlainText
      elide: Text.ElideRight
      Layout.fillWidth: true
    }

    Text {
      visible: text !== ""
      text: root.detail
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
      elide: Text.ElideRight
      Layout.fillWidth: true
    }

    RowLayout {
      visible: root.actions.length > 0
      Layout.fillWidth: true
      spacing: Style.space(5)

      Repeater {
        model: root.actions
        Button {
          required property var modelData
          text: String(modelData.label || modelData.id || "Action")
          enabled: !root.busy && modelData.enabled !== false
          selected: modelData.danger === true
          bordered: true
          foreground: modelData.danger === true ? Color.urgent : root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          onClicked: root.actionRequested(String(modelData.id || ""))
        }
      }

      Item { Layout.fillWidth: true }
    }
  }
}
