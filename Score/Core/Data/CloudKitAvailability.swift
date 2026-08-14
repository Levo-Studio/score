import Foundation
import MachO

/// Prüft, ob dieser Prozess CloudKit überhaupt benutzen darf.
///
/// ## Warum das nötig ist
///
/// Fehlt das Entitlement `com.apple.developer.icloud-services`, **stürzt
/// CloudKit ab** — nicht mit einem Fehler, den man fangen könnte, sondern mit
/// einem Trap auf `com.apple.coredata.cloudkit.queue`, tief in
/// `PFCloudKitContainerProvider`. Das passiert asynchron, lange nachdem
/// `ModelContainer(for:)` erfolgreich zurückgekehrt ist. Ein `do`/`catch` um die
/// Initialisierung fängt davon nichts; der Absturz muss vermieden werden.
///
/// Betroffen ist jeder Build ohne Signierung: der Test-Host und alles, was mit
/// `CODE_SIGNING_ALLOWED=NO` gebaut wird — also der übliche schnelle Baubefehl
/// und CI.
///
/// ## Wie geprüft wird
///
/// Das hängt davon ab, wo die App läuft, und der Unterschied ist wichtig:
///
/// - **Im Simulator** liegen die Entitlements als Klartext-Plist in einer
///   eigenen Mach-O-Sektion `__TEXT,__entitlements`. Genau die liest der
///   Simulator selbst aus, und genau die fehlt einem unsignierten Build.
/// - **Auf einem Gerät** stehen sie in der Code-Signatur, nicht in dieser
///   Sektion. Dort wäre die Prüfung also wertlos — und gefährlich: ein falsches
///   „nein" würde den Sync auf echten Geräten stillschweigend abschalten.
///   Deshalb gilt auf dem Gerät immer `true`. Das ist gefahrlos, weil iOS eine
///   App ohne gültige Entitlements gar nicht erst startet.
enum CloudKitAvailability {

    /// Ob der Sync eingeschaltet werden darf.
    static let isEntitled: Bool = {
        #if targetEnvironment(simulator)
        return embeddedEntitlementsAllowCloudKit()
        #else
        return true
        #endif
    }()

    #if targetEnvironment(simulator)
    /// Liest die eingebettete Entitlements-Plist des eigenen Binaries.
    private static func embeddedEntitlementsAllowCloudKit() -> Bool {
        guard let header = _dyld_get_image_header(0) else { return false }

        var size: UInt = 0
        let pointer = header.withMemoryRebound(to: mach_header_64.self, capacity: 1) {
            getsectiondata($0, "__TEXT", "__entitlements", &size)
        }
        guard let pointer, size > 0 else { return false }

        let data = Data(bytes: pointer, count: Int(size))
        guard let plist = try? PropertyListSerialization.propertyList(
            from: data,
            format: nil
        ) as? [String: Any] else {
            return false
        }

        guard let services = plist["com.apple.developer.icloud-services"] as? [String] else {
            return false
        }
        return services.contains("CloudKit") || services.contains("CloudKit-Anonymous")
    }
    #endif
}
