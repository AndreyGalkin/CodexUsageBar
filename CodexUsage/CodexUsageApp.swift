import SwiftUI

@main
struct CodexUsageApp: App {
    @StateObject private var service: CodexUsageService

    init() {
        let service = CodexUsageService()
        _service = StateObject(wrappedValue: service)
        service.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(service: service)
        } label: {
            Text(service.statusTitle)
                .task { service.start() }
        }
        .menuBarExtraStyle(.window)
    }
}
