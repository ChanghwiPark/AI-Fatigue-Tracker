import Foundation
import AppKit
import Speech
import AVFoundation

/// Speech 프레임워크(ko-KR) 기반 실시간 음성-텍스트(STT) 입력 관리자
/// - 원본 음성 파일은 일체 디스크에 저장하지 않고 실시간 오디오 버퍼 스트림으로만 인식
/// - 마이크 권한 및 음성 인식 권한을 동적으로 요청하고 처리
public final class SpeechInputManager: ObservableObject {
    public static let shared = SpeechInputManager()

    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var activeFieldKey: String? = nil
    @Published public var errorMessage: String? = nil

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var currentTextUpdateHandler: ((String) -> Void)?
    private var baseTextBeforeSpeech: String = ""

    // 무음 감지 자동 종료 타이머
    private var silenceTimer: Timer?
    private var hasSpokenAnyWord: Bool = false
    private let initialSilenceTimeout: TimeInterval = 5.0    // 시작 후 아무 말이 없을 때 5초 후 자동 종료
    private let speechEndSilenceTimeout: TimeInterval = 2.2  // 발화 후 말이 멈추면 2.2초 후 자동 완료

    private init() {}

    /// 특정 입력 필드에 대해 녹음 토글
    public func toggleRecording(
        fieldKey: String,
        currentText: String,
        onUpdate: @escaping (String) -> Void
    ) {
        if isRecording {
            if activeFieldKey == fieldKey {
                stopRecording()
            } else {
                stopRecording()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.startRecording(fieldKey: fieldKey, currentText: currentText, onUpdate: onUpdate)
                }
            }
        } else {
            startRecording(fieldKey: fieldKey, currentText: currentText, onUpdate: onUpdate)
        }
    }

    /// 음성 인식 시작
    public func startRecording(
        fieldKey: String,
        currentText: String,
        onUpdate: @escaping (String) -> Void
    ) {
        stopRecording()

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("[SpeechInputManager] ko-KR 음성 인식기 사용 불가")
            self.errorMessage = "한국어(ko-KR) 음성 인식을 현재 사용할 수 없습니다."
            showPermissionAlert(message: "한국어(ko-KR) 음성 인식기를 사용할 수 없습니다. 시스템 설정에서 음성 인식을 확인해 주세요.", pane: "Privacy_SpeechRecognition")
            return
        }

        print("[SpeechInputManager] 🎙️ 음성 인식 권한 확인 (현재 authStatus: \(SFSpeechRecognizer.authorizationStatus().rawValue))")
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                guard let self = self else { return }
                print("[SpeechInputManager] SFSpeechRecognizer authStatus 결과: \(authStatus.rawValue)")
                switch authStatus {
                case .authorized:
                    self.requestMicrophoneAndRecord(fieldKey: fieldKey, currentText: currentText, onUpdate: onUpdate)
                case .denied, .restricted:
                    self.errorMessage = "설정 > 개인정보 보호에서 음성 인식 권한을 허용해 주세요."
                    self.showPermissionAlert(
                        message: "음성으로 피로 설문에 답변하려면 '음성 인식' 권한이 필요합니다.\n\n[설정 열기]를 눌러 'AI 피로 기록'의 음성 인식 권한을 켜주세요.",
                        pane: "Privacy_SpeechRecognition"
                    )
                case .notDetermined:
                    self.errorMessage = "음성 인식 권한이 필요합니다."
                    self.showPermissionAlert(
                        message: "음성으로 피로 설문에 답변하려면 '음성 인식' 권한 허용이 필요합니다.\n\n화면에 뜨는 시스템 확인 창에서 [허용]을 눌러주시거나 [설정 열기]에서 권한을 켜주세요.",
                        pane: "Privacy_SpeechRecognition"
                    )
                @unknown default:
                    self.errorMessage = "알 수 없는 음성 인식 권한 상태입니다."
                }
            }
        }
    }

    private func requestMicrophoneAndRecord(
        fieldKey: String,
        currentText: String,
        onUpdate: @escaping (String) -> Void
    ) {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        print("[SpeechInputManager] 🎤 마이크 권한 확인 (현재 micStatus: \(micStatus.rawValue))")

        if micStatus == .authorized {
            self.beginAudioEngineRecording(fieldKey: fieldKey, currentText: currentText, onUpdate: onUpdate)
            return
        }

        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                print("[SpeechInputManager] 마이크 접근 요청 결과: \(granted)")
                if granted {
                    self.beginAudioEngineRecording(fieldKey: fieldKey, currentText: currentText, onUpdate: onUpdate)
                } else {
                    self.errorMessage = "설정 > 개인정보 보호에서 마이크 권한을 허용해 주세요."
                    self.showPermissionAlert(
                        message: "음성으로 피로 설문에 답변하려면 '마이크' 접근 권한이 필요합니다.\n\n[설정 열기]를 눌러 'AI 피로 기록'의 마이크 권한을 켜주세요.",
                        pane: "Privacy_Microphone"
                    )
                }
            }
        }
    }

    private func showPermissionAlert(message: String, pane: String = "Privacy_Microphone") {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "음성 입력 권한 필요"
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "설정 열기")
            alert.addButton(withTitle: "취소")
            if alert.runModal() == .alertFirstButtonReturn {
                PermissionsManager.shared.openSystemSettings(pane: pane)
            }
        }
    }

    private func beginAudioEngineRecording(
        fieldKey: String,
        currentText: String,
        onUpdate: @escaping (String) -> Void
    ) {
        do {
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.recognitionRequest = request
            self.baseTextBeforeSpeech = currentText
            self.currentTextUpdateHandler = onUpdate
            self.activeFieldKey = fieldKey

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
                print("[SpeechInputManager] 유효하지 않은 오디오 포맷: sampleRate=\(recordingFormat.sampleRate), channels=\(recordingFormat.channelCount)")
                self.errorMessage = "마이크 오디오 장치를 시작할 수 없습니다. 오디오 설정을 확인해 주세요."
                stopRecording()
                return
            }

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            self.isRecording = true
            self.errorMessage = nil
            self.hasSpokenAnyWord = false
            print("[SpeechInputManager] 🔴 실시간 음성 녹음 시작 (field: \(fieldKey))")

            // 1) 시작 후 아무 말이 없으면 5초 후 자동 종료
            self.resetSilenceTimer(timeout: self.initialSilenceTimeout)

            self.recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }

                if let error = error {
                    print("[SpeechInputManager] 음성 인식 태스크 에러: \(error.localizedDescription)")
                }

                if let result = result {
                    let spokenText = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !spokenText.isEmpty {
                        self.hasSpokenAnyWord = true
                        print("[SpeechInputManager] 🗣️ 인식된 텍스트: \"\(spokenText)\" (isFinal: \(result.isFinal))")

                        let prefix = self.baseTextBeforeSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
                        let combined: String
                        if prefix.isEmpty {
                            combined = spokenText
                        } else if prefix.hasSuffix(",") || prefix.hasSuffix(".") {
                            combined = "\(prefix) \(spokenText)"
                        } else {
                            combined = "\(prefix), \(spokenText)"
                        }

                        DispatchQueue.main.async {
                            self.currentTextUpdateHandler?(combined)
                            // 2) 발화가 감지되면 무음 타이머를 2.2초로 리셋 (말이 끝나고 2.2초 침묵 시 자동 완료)
                            self.resetSilenceTimer(timeout: self.speechEndSilenceTimeout)
                        }
                    }
                }

                if error != nil || (result?.isFinal ?? false) {
                    DispatchQueue.main.async {
                        self.stopRecording()
                    }
                }
            }
        } catch {
            print("[SpeechInputManager] 마이크 엔진 시작 실패: \(error)")
            self.errorMessage = "마이크를 시작할 수 없습니다: \(error.localizedDescription)"
            self.stopRecording()
        }
    }

    /// 무음 감지 타이머 재설정
    private func resetSilenceTimer(timeout: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isRecording else { return }
            self.silenceTimer?.invalidate()
            self.silenceTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self = self, self.isRecording else { return }
                    print("[SpeechInputManager] 무음 감지로 인한 자동 녹음 종료")
                    self.stopRecording()
                }
            }
        }
    }

    /// 음성 인식 정지
    public func stopRecording() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        hasSpokenAnyWord = false

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        DispatchQueue.main.async {
            self.isRecording = false
            self.activeFieldKey = nil
            self.currentTextUpdateHandler = nil
        }
        print("[SpeechInputManager] ⏹️ 음성 인식 정지 완료")
    }
}
