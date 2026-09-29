import Foundation

extension Bundle {
    /// SwiftPM's generated `Bundle.module` for executables only looks next to the binary and
    /// traps when the bundle is missing. `scripts/bundle.sh` puts the resource bundle in
    /// `Contents/Resources` (the only place codesign accepts), so look there first.
    static let app: Bundle = {
        let name = "Feather_Feather.bundle"
        for base in [Bundle.main.resourceURL, Bundle.main.bundleURL] {
            if let url = base?.appendingPathComponent(name), let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return Bundle.module
    }()
}
