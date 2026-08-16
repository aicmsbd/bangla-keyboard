// বাঙলা কিবোর্ড — cloud voice typing (Google Cloud Speech-to-Text).
//
// Why not the Web Speech API: WKWebView's own SpeechRecognition never fires any event on
// macOS (verified against a live click — getUserMedia works, but .start() just hangs forever).
// Why not Apple's native Speech framework: SFSpeechRecognizer.supportedLocales() has no
// Bangla locale at all (63 locales, zero bn-*). So the native host captures the mic itself
// (AVAudioEngine) and calls Google's REST API with the user's own key — the only combination
// that actually produces Bangla text. The key is entered once and kept in the macOS Keychain;
// it never touches the WKWebView/JS layer.

import Foundation
import AVFoundation
import Security

// ---- Keychain (the API key never lives in a plist or UserDefaults) -----------------------
enum VoiceKeychain {
    private static let service = "com.bangla.keyboard.app"
    private static let account = "GoogleSpeechAPIKey"

    static func save(_ key: String) {
        let data = Data(key.utf8)
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        var attrs = base
        attrs[kSecValueData as String] = data
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrService as String: service,
                                     kSecAttrAccount as String: account,
                                     kSecReturnData as String: true,
                                     kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// ---- Mic capture: resample whatever the input device gives us down to 16kHz mono PCM16 ----
final class VoiceRecorder {
    static let shared = VoiceRecorder()
    static let sampleRate = 16000.0

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var samples: [Int16] = []
    private(set) var isRecording = false

    func start() {
        guard !isRecording else { return }
        samples.removeAll()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Self.sampleRate, channels: 1, interleaved: true) else { return }
        converter = AVAudioConverter(from: inputFormat, to: target)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.consume(buffer, target: target)
        }
        do {
            engine.prepare()
            try engine.start()
            isRecording = true
        } catch {
            bkLog("VoiceRecorder start failed: \(error)")
        }
    }

    private func consume(_ buffer: AVAudioPCMBuffer, target: AVAudioFormat) {
        guard let converter = converter else { return }
        let ratio = Self.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        do {
            try converter.convert(to: out, from: buffer)
        } catch {
            return
        }
        guard let ch = out.int16ChannelData else { return }
        samples.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
    }

    /// Stops capture and returns raw little-endian PCM16 mono samples at Self.sampleRate.
    func stop() -> Data {
        guard isRecording else { return Data() }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        var data = Data(capacity: samples.count * 2)
        for s in samples { withUnsafeBytes(of: s.littleEndian) { data.append(contentsOf: $0) } }
        return data
    }
}

extension String: Error {}   // lets plain error-message strings flow through Result<_, String>

// ---- Google Cloud Speech-to-Text (synchronous REST recognize call) ------------------------
enum GoogleSTT {
    static func recognize(pcm16: Data, languageCode: String, apiKey: String,
                           completion: @escaping (Result<String, String>) -> Void) {
        guard !pcm16.isEmpty else { completion(.failure("EMPTY")); return }
        var comps = URLComponents(string: "https://speech.googleapis.com/v1/speech:recognize")!
        comps.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let config: [String: Any] = [
            "encoding": "LINEAR16",
            "sampleRateHertz": Int(VoiceRecorder.sampleRate),
            "languageCode": languageCode,
            "model": "default",
        ]
        let body: [String: Any] = [
            "config": config,
            "audio": ["content": pcm16.base64EncodedString()],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, _, err in
            if let err = err { completion(.failure("network: \(err.localizedDescription)")); return }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure("bad response")); return
            }
            if let error = json["error"] as? [String: Any], let msg = error["message"] as? String {
                completion(.failure(msg)); return
            }
            guard let results = json["results"] as? [[String: Any]], !results.isEmpty else {
                completion(.failure("EMPTY")); return
            }
            var transcript = ""
            for r in results {
                if let alts = r["alternatives"] as? [[String: Any]], let t = alts.first?["transcript"] as? String {
                    transcript += (transcript.isEmpty ? "" : " ") + t
                }
            }
            completion(.success(transcript.trimmingCharacters(in: .whitespaces)))
        }.resume()
    }
}
