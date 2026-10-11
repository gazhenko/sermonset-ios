import Testing
@testable import SermonSetSpeech

@Suite struct SpeechMemoryTests {
    @Test(arguments: [UInt64(0), UInt64(64 * 1024 * 1024), UInt64(4 * 1024 * 1024 * 1024)])
    func memorySourceFollowsEnvironment(processBytes: UInt64) {
        let hostBytes: UInt64 = 4 * 1024 * 1024 * 1024
        var processQueries = 0, hostQueries = 0
        let available = SpeechMemory.available(processMemory: {
            processQueries += 1
            return processBytes
        }, hostMemory: {
            hostQueries += 1
            return hostBytes
        })
        #if os(iOS) && !targetEnvironment(simulator)
        #expect(available == processBytes)
        #expect(processQueries == 1 && hostQueries == 0)
        #else
        #expect(available == hostBytes)
        #expect(processQueries == 0 && hostQueries == 1)
        #endif
    }

    @Test(arguments: [UInt64(0), UInt64(64 * 1024 * 1024)])
    func lowMemoryIsNotTreatedAsUnlimited(bytes: UInt64) {
        #expect(SpeechMemory.available(processMemory: { bytes }, hostMemory: { bytes }) == bytes)
    }
}
