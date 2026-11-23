import AppKit
import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if model.needsAccessOnboarding {
                FullDiskAccessView(model: model)
            } else {
                NavigationSplitView {
                    SidebarView(model: model)
                } detail: {
                    switch model.sidebarSelection ?? .carte {
                    case .carte: CarteView(model: model)
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .task { await model.start() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.recheckAccess()
            model.refreshVolume()
        }
    }
}
