import Testing
@testable import SnowdropCore

@Test
func coreVersionMatchesAlpha() {
    #expect(SnowdropCoreVersion.version == "1.0.0-alpha")
}
