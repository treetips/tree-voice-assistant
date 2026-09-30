import Foundation
import Testing

@testable import TreeVoiceAssistant

@Suite("IrodoriTTSService")
struct IrodoriTTSServiceTests {
    @Test("infer.pyの引数を組み立てる")
    func arguments() throws {
        let ref = URL(fileURLWithPath: "/tmp/ref.wav", isDirectory: false)
        let out = URL(fileURLWithPath: "/tmp/out", isDirectory: true)
        let proj = URL(fileURLWithPath: "/tmp/tts-irodori", isDirectory: true)
        let src = URL(fileURLWithPath: "/tmp/tts-irodori/src", isDirectory: true)
        let request = TTSRequest(
            model: "Aratako/Irodori-TTS-v4.1-Small",
            refAudioURL: ref,
            refText: "無視される",
            text: "よむ",
            outputDirectory: out,
            caption: "落ち着いた声"
        )
        let args = IrodoriTTSService.generateArguments(
            request: request, projectDirectory: proj, sourceDirectory: src, outputDirectory: out)
        #expect(args.contains("/tmp/tts-irodori/src/infer.py"))
        #expect(args.contains("Aratako/Irodori-TTS-v4.1-Small"))
        #expect(args.contains("/tmp/ref.wav"))
        #expect(args.contains("落ち着いた声"))
        #expect(!args.contains("--ref_text"))
    }

    @Test("captionが空なら--captionを付けない")
    func noCaptionFlag() throws {
        let ref = URL(fileURLWithPath: "/tmp/ref.wav", isDirectory: false)
        let out = URL(fileURLWithPath: "/tmp/out", isDirectory: true)
        let proj = URL(fileURLWithPath: "/tmp/tts-irodori", isDirectory: true)
        let src = URL(fileURLWithPath: "/tmp/tts-irodori/src", isDirectory: true)
        let request = TTSRequest(
            model: "Aratako/Irodori-TTS-v4.1-Small",
            refAudioURL: ref,
            refText: "",
            text: "よむ",
            outputDirectory: out,
            caption: nil
        )
        let args = IrodoriTTSService.generateArguments(
            request: request, projectDirectory: proj, sourceDirectory: src, outputDirectory: out)
        #expect(!args.contains("--caption"))
    }
}
