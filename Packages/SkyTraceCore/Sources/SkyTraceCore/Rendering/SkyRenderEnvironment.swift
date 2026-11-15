import Foundation
import Observation

#if canImport(Darwin)
import Darwin
#endif

public enum SkyMemoryPressure: Equatable, Sendable {
    case normal
    case warning
    case critical
}

public struct SkyRenderEnvironment: Equatable, Sendable {
    public let thermalState: ProcessInfo.ThermalState
    public let isLowPowerModeEnabled: Bool
    public let memoryPressure: SkyMemoryPressure
    public let revision: Int

    public init(
        thermalState: ProcessInfo.ThermalState = .nominal,
        isLowPowerModeEnabled: Bool = false,
        memoryPressure: SkyMemoryPressure = .normal,
        revision: Int = 0
    ) {
        self.thermalState = thermalState
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.memoryPressure = memoryPressure
        self.revision = revision
    }
}

/// Observes the system signals that can materially change renderer quality.
/// Notifications are debounced so SceneKit settings never oscillate on a
/// transient transition.
@MainActor
@Observable
public final class SkyRenderEnvironmentMonitor {
    public private(set) var environment: SkyRenderEnvironment

    @ObservationIgnored nonisolated(unsafe) private var notificationTokens: [any NSObjectProtocol] = []
    @ObservationIgnored private var memoryPressureSource: (any DispatchSourceMemoryPressure)?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var lastObservedState: SkyRenderEnvironment

    public init() {
        let initial = SkyRenderEnvironment(
            thermalState: ProcessInfo.processInfo.thermalState,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        environment = initial
        lastObservedState = initial
        installObservers()
    }

    deinit {
        refreshTask?.cancel()
        memoryPressureSource?.cancel()
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }

    private func installObservers() {
        let center = NotificationCenter.default
        notificationTokens = [
            center.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.scheduleRefresh() }
            },
            center.addObserver(
                forName: .NSProcessInfoPowerStateDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.scheduleRefresh() }
            }
        ]

#if canImport(Darwin)
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: .all,
            queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            let pressure: SkyMemoryPressure
            if source.data.contains(.critical) {
                pressure = .critical
            } else if source.data.contains(.warning) {
                pressure = .warning
            } else {
                pressure = .normal
            }
            Task { @MainActor [weak self] in
                self?.apply(environment: self?.currentSystemEnvironment(memoryPressure: pressure) ?? SkyRenderEnvironment())
            }
        }
        memoryPressureSource = source
        source.resume()
#endif
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            self.apply(environment: self.currentSystemEnvironment())
            self.refreshTask = nil
        }
    }

    private func currentSystemEnvironment(
        memoryPressure: SkyMemoryPressure? = nil
    ) -> SkyRenderEnvironment {
        SkyRenderEnvironment(
            thermalState: ProcessInfo.processInfo.thermalState,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            memoryPressure: memoryPressure ?? environment.memoryPressure,
            revision: environment.revision
        )
    }

    private func apply(environment next: SkyRenderEnvironment) {
        guard
            next.thermalState != lastObservedState.thermalState ||
            next.isLowPowerModeEnabled != lastObservedState.isLowPowerModeEnabled ||
            next.memoryPressure != lastObservedState.memoryPressure
        else { return }

        environment = SkyRenderEnvironment(
            thermalState: next.thermalState,
            isLowPowerModeEnabled: next.isLowPowerModeEnabled,
            memoryPressure: next.memoryPressure,
            revision: environment.revision &+ 1
        )
        lastObservedState = environment
    }
}
