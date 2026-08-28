import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "ericvrp.one-app-per-workspace"

  // Bar widgets are created once per monitor. Read the service map owned by
  // shell.qml so every icon instance controls the same service object.
  readonly property var services: root.bar && root.bar.shell ? root.bar.shell._services : ({})
  readonly property var service: root.services[root.moduleName] || null
  readonly property bool featureEnabled: root.service ? root.service.enabled : true
  readonly property bool serviceReady: root.service ? root.service.stateReady : false
  readonly property color iconColor: button.active && button.useActiveColor
    ? button.activeColor : button.foreground

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button

    anchors.fill: parent
    bar: root.bar
    text: ""
    active: root.featureEnabled
    activeColor: root.bar ? root.bar.urgent : Color.urgent
    useActiveColor: true
    interactive: root.service !== null && root.serviceReady
    pressable: root.service !== null && root.serviceReady
    tooltipText: root.serviceReady
      ? (root.featureEnabled
        ? "One app per workspace (enabled)"
        : "Tiling mode (disabled)")
      : "One app per workspace (loading)"

    iconComponent: Component {
      Item {
        Rectangle {
          visible: root.featureEnabled
          anchors.centerIn: parent
          width: Math.round(parent.width * 0.68)
          height: width
          color: "transparent"
          border.width: 1
          border.color: root.iconColor
          radius: Style.spaceReal(0.5)
        }

        Row {
          visible: !root.featureEnabled
          anchors.centerIn: parent
          width: parent.width * 0.76
          height: parent.height * 0.68
          spacing: Style.spaceReal(1)

          Repeater {
            model: 2

            Rectangle {
              required property int index

              width: (parent.width - parent.spacing) / 2
              height: parent.height
              color: "transparent"
              border.width: 1
              border.color: root.iconColor
              radius: Style.spaceReal(0.5)
            }
          }
        }
      }
    }

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton && root.service) root.service.toggle()
    }
  }
}
