import Foundation
import AppKit
import Speech
import AVFoundation

/// Speech 프레임워크(ko-KR) 기반 실시간 음성-텍스트(STT) 입력 관리자
/// - 원본 음성 파일은 일체 디스크에 저장하지 않고 실시간 오디오 버퍼 스트림으로만 인식
/// - 마이크 권한 및 음성 인식 권한을 동적으로 요청하고 처리
/// - 오디오 노드 tap의 안전한 설치/해제 라이프사이클 관리 (중복 호출 및 미설치 해제 예외 원천 차단)
/// - 복수 문장 발화 연속 지원 (중간 단락 종결 시 자동 세션 갱신으로 음성 끊김 방지)
/// - 일시적 네트워크/무음 신호(203, 1110, 209, 102 등)에 대한 방어적 복구
public final class SpeechInputManager: ObservableObject {
    public static let shared = SpeechInputManager()

    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var activeFieldKey: String? = nil
    @Published public var errorMessage: String? = nil

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var isTapInstalled: Bool = false
    private var currentTextUpdateHandler: ((String) -> Void)?
    private var baseTextBeforeSpeech: String = ""
    private var latestFullText: String = ""
    private var currentSessionUUID = UUID()

    // 무음 감지 자동 종료 타이머
    private var silenceTimer: Timer?
    private var hasSpokenAnyWord: Bool = false
    private let initialSilenceTimeout: TimeInterval = 7.0    // 시작 후 첫 발화까지 7초 대기 (생각할 여유 제공)
    private let speechEndSilenceTimeout: TimeInterval = 3.5  // 발화 후 말이 멈추면 3.5초 후 자동 완료
    private var audioConfigObserver: NSObjectProtocol?

    private init() {
        setupAudioEngineObserver()
    }

    deinit {
        if let observer = audioConfigObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// 오디오 하드웨어 설정 변경(AirPods 연결/해제, 기본 입력 장치 변경 등) 감지
    private func setupAudioEngineObserver() {
        audioConfigObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isRecording else { return }
            print("[SpeechInputManager] ⚠️ 오디오 입력 장치 변경 감지 -> 안전하게 녹음 정리")
            self.stopRecording()
            self.errorMessage = "오디오 장치가 변경되어 음성 입력이 완료되었습니다."
        }
    }

    /// 특정 입력 필드에 대해 녹음 토글
    public func toggleRecording(
        fieldKey: String,
        currentText: String,
        onUpdate: @escaping (String) -> Void
    ) {
        if isRecording {
            let wasSameField = (activeFieldKey == fieldKey)
            stopRecording()
            if !wasSameField {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.startRecording(fieldKey: fieldKey, currentText: currentText, onUpdate: onUpdate)
                }
            }
        } else {
            startRecording(fieldKey: fieldKey, currentText: currentText, onUpdate: onUpdate)
        }
    }

    /// 음성 인식 시작 (마이크 아이콘을 직접 눌렀을 때만 권한 확인 및 요청)
    public func startRecording(
        fieldKey: String,
        currentText: String,
        onUpdate: @escaping (String) -> Void
    ) {
        stopRecording()
        self.errorMessage = nil

        // 1. 마이크 권한 확인 (사용자가 마이크 버튼을 직접 눌렀을 때만 요청)
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        print("[SpeechInputManager] 🎤 마이크 권한 확인 (micStatus: \(micStatus.rawValue))")

        switch micStatus {
        case .denied, .restricted:
            self.errorMessage = "설정 > 개인정보 보호에서 마이크 권한을 허용해 주세요."
            self.showPermissionAlert(
                message: "피로 설문의 주관식 응답을 음성으로 입력하려면 '마이크' 접근 권한이 필요합니다.\n\n[설정 열기]를 눌러 시스템 설정에서 'AI 피로 기록'의 마이크 권한을 켜주세요.",
                pane: "Privacy_Microphone"
            )
            return

        case .notDetermined:
            // 아직 결정되지 않은 상태에서 마이크 버튼을 눌렀을 때만 시스템 권한 팝업 호출
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    PermissionsManager.shared.checkMicrophone()
                    if granted {
                        self.checkSpeechRecognitionAndStart(fieldKey: fieldKey, currentText: currentText, onUpdate: onUpdate)
                    } else {
                        self.errorMessage = "마이크 접근이 거부되었습니다."
                        self.showPermissionAlert(
                            message: "피로 설문의 주관식 응답을 음성으로 입력하려면 '마이크' 접근 권한이 필요합니다.\n\n[설정 열기]를 눌러 시스템 설정에서 마이크 권한을 허용해 주세요.",
                            pane: "Privacy_Microphone"
                        )
                    }
                }
            }
            return

        case .authorized:
            checkSpeechRecognitionAndStart(fieldKey: fieldKey, currentText: currentText, onUpdate: onUpdate)

        @unknown default:
            break
        }
    }

    /// 2. 음성 인식 권한 확인 및 실제 오디오 엔진 녹음 연계
    private func checkSpeechRecognitionAndStart(
        fieldKey: String,
        currentText: String,
        onUpdate: @escaping (String) -> Void
    ) {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("[SpeechInputManager] ko-KR 음성 인식기 사용 불가")
            self.errorMessage = "한국어(ko-KR) 음성 인식을 현재 사용할 수 없습니다."
            showPermissionAlert(message: "한국어(ko-KR) 음성 인식기를 사용할 수 없습니다. 시스템 설정에서 음성 인식을 확인해 주세요.", pane: "Privacy_SpeechRecognition")
            return
        }

        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        print("[SpeechInputManager] 🎙️ 음성 인식 권한 확인 (speechStatus: \(speechStatus.rawValue))")

        switch speechStatus {
        case .authorized:
            self.beginAudioEngineRecording(fieldKey: fieldKey, currentText: currentText, onUpdate: onUpdate)

        case .denied, .restricted:
            self.errorMessage = "설정 > 개인정보 보호에서 음성 인식 권한을 허용해 주세요."
            self.showPermissionAlert(
                message: "음성을 텍스트로 자동 변환하려면 '음성 인식' 권한이 필요합니다.\n\n[설정 열기]를 눌러 시스템 설정에서 'AI 피로 기록'의 음성 인식 권한을 켜주세요.",
                pane: "Privacy_SpeechRecognition"
            )

        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    PermissionsManager.shared.checkSpeechRecognition()
                    if authStatus == .authorized {
                        self.beginAudioEngineRecording(fieldKey: fieldKey, currentText: currentText, onUpdate: onUpdate)
                    } else {
                        self.errorMessage = "음성 인식 권한이 거부되었습니다."
                        self.showPermissionAlert(
                            message: "음성을 텍스트로 자동 변환하려면 '음성 인식' 권한이 필요합니다.\n\n[설정 열기]를 눌러 시스템 설정에서 음성 인식 권한을 켜주세요.",
                            pane: "Privacy_SpeechRecognition"
                        )
                    }
                }
            }

        @unknown default:
            self.errorMessage = "알 수 없는 음성 인식 권한 상태입니다."
        }
    }

    private func showPermissionAlert(message: String, pane: String = "Privacy_Microphone") {
        DispatchQueue.main.async {
            // CLI/테스트 환경이거나 headless인 경우 alert.runModal()로 인한 비정상 종료 방지
            guard NSApp != nil, !CommandLine.arguments.contains("--test-speech-engine") else {
                print("[SpeechInputManager] 비대화형/테스트 환경: 권한 알림 로그만 기록 -> \(pane)")
                return
            }

            let alert = NSAlert()
            alert.messageText = "음성 입력 권한 필요"
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "설정 열기")
            alert.addButton(withTitle: "취소")

            if let targetWindow = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && !$0.className.contains("StatusBar") }) {
                alert.beginSheetModal(for: targetWindow) { response in
                    if response == .alertFirstButtonReturn {
                        PermissionsManager.shared.openSystemSettings(pane: pane)
                    }
                }
            } else {
                NSApp.activate(ignoringOtherApps: true)
                if alert.runModal() == .alertFirstButtonReturn {
                    PermissionsManager.shared.openSystemSettings(pane: pane)
                }
            }
        }
    }

    private func removeTapSafely() {
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
    }

    private func setRecordingState(_ recording: Bool, fieldKey: String? = nil, handler: ((String) -> Void)? = nil) {
        let update = {
            self.isRecording = recording
            if recording {
                self.activeFieldKey = fieldKey
                self.currentTextUpdateHandler = handler
            } else {
                self.activeFieldKey = nil
                self.currentTextUpdateHandler = nil
            }
        }

        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    private func beginAudioEngineRecording(
        fieldKey: String,
        currentText: String,
        onUpdate: @escaping (String) -> Void
    ) {
        do {
            let sessionID = UUID()
            self.currentSessionUUID = sessionID

            // 1. 기존 잔여 탭 및 엔진 정리
            removeTapSafely()
            if audioEngine.isRunning {
                audioEngine.stop()
                audioEngine.reset()
            }

            self.baseTextBeforeSpeech = currentText
            self.latestFullText = currentText
            self.hasSpokenAnyWord = false
            self.errorMessage = nil

            let inputNode = audioEngine.inputNode
            audioEngine.prepare()

            var recordingFormat = inputNode.outputFormat(forBus: 0)
            if recordingFormat.sampleRate <= 0 || recordingFormat.channelCount <= 0 {
                recordingFormat = inputNode.inputFormat(forBus: 0)
            }

            guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
                print("[SpeechInputManager] 유효하지 않은 오디오 포맷: sampleRate=\(recordingFormat.sampleRate), channels=\(recordingFormat.channelCount)")
                self.errorMessage = "마이크 오디오 장치를 시작할 수 없습니다. 오디오 설정을 확인해 주세요."
                stopRecording()
                return
            }

            // 2. 오디오 노드 버퍼 Tap 설치
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                guard let self = self, self.currentSessionUUID == sessionID else { return }
                self.recognitionRequest?.append(buffer)
            }
            self.isTapInstalled = true

            // 3. 오디오 엔진 구동
            try audioEngine.start()

            // 4. 음성 인식 태스크 시작
            self.startRecognitionTask(sessionID: sessionID)

            self.setRecordingState(true, fieldKey: fieldKey, handler: onUpdate)
            print("[SpeechInputManager] 🔴 실시간 음성 녹음 시작 (session: \(sessionID.uuidString.prefix(6)), field: \(fieldKey))")

            // 5. 시작 후 첫 발화까지 7초 대기
            self.resetSilenceTimer(timeout: self.initialSilenceTimeout)

        } catch {
            print("[SpeechInputManager] 마이크 엔진 시작 실패: \(error)")
            self.errorMessage = "마이크를 시작할 수 없습니다: \(error.localizedDescription)"
            self.stopRecording()
        }
    }

    /// 연속 음성 인식을 지원하기 위한 RecognitionTask 시작/재시작
    private func startRecognitionTask(sessionID: UUID) {
        guard self.currentSessionUUID == sessionID else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13.0, *), speechRecognizer?.supportsOnDeviceRecognition == true {
            request.addsPunctuation = true
        }
        self.recognitionRequest = request

        self.recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            self?.handleRecognitionResult(result: result, error: error, sessionID: sessionID)
        }
    }

    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?, sessionID: UUID) {
        guard self.currentSessionUUID == sessionID else { return }

        if let nsError = error as NSError? {
            // 사용자에 의한 정상 취소(Code=216, 1, 301)는 에러가 아님
            if (nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 216 || nsError.code == 301)) ||
               (nsError.domain == "siriSpeechErrorDomain" && nsError.code == 1) {
                return
            }

            // 일시적 무발화(Code=203, 1110) 및 대기/세션 변경 신호(Code=209, 102)는 무음 타이머에 위임하여 녹음 유지
            if nsError.code == 203 || nsError.code == 1110 || nsError.code == 209 || nsError.code == 102 {
                print("[SpeechInputManager] 일시적 무발화/대기 신호 (녹음 계속 유지): \(nsError.code)")
                return
            }

            print("[SpeechInputManager] 음성 인식 에러: \(nsError.localizedDescription) (\(nsError.domain) code:\(nsError.code))")
            DispatchQueue.main.async {
                guard self.currentSessionUUID == sessionID else { return }
                // 발화된 내용이 있었으면 지금까지의 결과를 보존하며 완료
                if self.hasSpokenAnyWord {
                    self.stopRecording()
                } else {
                    self.errorMessage = "음성 인식이 원활하지 않습니다. 다시 마이크를 눌러 말씀해 주세요."
                    self.stopRecording()
                }
            }
            return
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

                self.latestFullText = combined

                DispatchQueue.main.async {
                    guard self.currentSessionUUID == sessionID else { return }
                    self.currentTextUpdateHandler?(combined)
                    // 발화 감지 시 무음 타이머를 3.5초로 갱신 (말이 끝나고 3.5초 침묵 시 자동 완료)
                    self.resetSilenceTimer(timeout: self.speechEndSilenceTimeout)
                }
            }

            if result.isFinal {
                // 한 단락 음성 인식이 종결된 경우, 지금까지의 결과를 baseText로 승격하고
                // 사용자가 마이크를 끄지 않았다면 다음 발화를 연속 인식할 수 있도록 recognitionTask 재연결
                DispatchQueue.main.async {
                    guard self.currentSessionUUID == sessionID, self.isRecording else { return }
                    self.baseTextBeforeSpeech = self.latestFullText
                    print("[SpeechInputManager] 🏁 중간 단락 종결 -> 연속 발화를 위해 recognitionTask 갱신 (누적: \"\(self.baseTextBeforeSpeech)\")")
                    self.startRecognitionTask(sessionID: sessionID)
                }
            }
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
        currentSessionUUID = UUID() // 이전 세션 콜백 즉시 무효화
        silenceTimer?.invalidate()
        silenceTimer = nil
        hasSpokenAnyWord = false

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        removeTapSafely()
        audioEngine.reset()

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        setRecordingState(false)
        print("[SpeechInputManager] ⏹️ 음성 인식 정지 완료")
    }
}
