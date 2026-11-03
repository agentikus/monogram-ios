import Foundation
import SwiftSignalKit
import Speech

private var sharedRecognizers: [String: NSObject] = [:]

private struct TranscriptionResult {
    var text: String
    var confidence: Float
    var isFinal: Bool
}

private final class TranscriptionAccumulator {
    private static let restartThreshold: TimeInterval = 0.75

    private var committed: String = ""
    private var lastText: String = ""
    private var lastFirstTimestamp: TimeInterval?

    func update(text: String, firstSegmentTimestamp: TimeInterval?) -> String {
        if let previous = self.lastFirstTimestamp, let current = firstSegmentTimestamp, current > previous + TranscriptionAccumulator.restartThreshold, !self.lastText.isEmpty {
            self.committed = TranscriptionAccumulator.join(self.committed, self.lastText)
        }
        if !text.isEmpty {
            self.lastText = text
            if let firstSegmentTimestamp = firstSegmentTimestamp {
                self.lastFirstTimestamp = firstSegmentTimestamp
            }
        }
        return self.combinedText()
    }

    func combinedText() -> String {
        return TranscriptionAccumulator.join(self.committed, self.lastText)
    }

    private static func join(_ lhs: String, _ rhs: String) -> String {
        if lhs.isEmpty {
            return rhs
        } else if rhs.isEmpty {
            return lhs
        } else {
            return lhs + " " + rhs
        }
    }
}

private func transcribeAudio(path: String, locale: String) -> Signal<TranscriptionResult?, NoError> {
    return Signal { subscriber in
        let disposable = MetaDisposable()
        
        if #available(iOS 13.0, *) {
            SFSpeechRecognizer.requestAuthorization { status in
                Queue.mainQueue().async {
                    switch status {
                    case .notDetermined:
                        subscriber.putNext(nil)
                        subscriber.putCompletion()
                    case .restricted:
                        subscriber.putNext(nil)
                        subscriber.putCompletion()
                    case .denied:
                        subscriber.putNext(nil)
                        subscriber.putCompletion()
                    case .authorized:
                        let speechRecognizer: SFSpeechRecognizer
                        if let sharedRecognizer = sharedRecognizers[locale] as? SFSpeechRecognizer {
                            speechRecognizer = sharedRecognizer
                        } else {
                            guard let speechRecognizerValue = SFSpeechRecognizer(locale: Locale(identifier: locale)), speechRecognizerValue.isAvailable else {
                                subscriber.putNext(nil)
                                subscriber.putCompletion()
                                
                                return
                            }
                            speechRecognizerValue.defaultTaskHint = .dictation
                            sharedRecognizers[locale] = speechRecognizerValue
                            speechRecognizer = speechRecognizerValue
                            
                        }
                        
                        let tempFilePath = NSTemporaryDirectory() + "/\(UInt64.random(in: 0 ... UInt64.max)).m4a"
                        let _ = try? FileManager.default.copyItem(atPath: path, toPath: tempFilePath)
                        
                        let request = SFSpeechURLRecognitionRequest(url: URL(fileURLWithPath: tempFilePath))
                        if #available(iOS 16.0, *) {
                            request.addsPunctuation = true
                        }
                        request.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition
                        request.shouldReportPartialResults = true
                        
                        let accumulator = TranscriptionAccumulator()
                        let task = speechRecognizer.recognitionTask(with: request, resultHandler: { result, error in
                            if let result = result {
                                let transcription = result.bestTranscription
                                let combined = accumulator.update(text: transcription.formattedString, firstSegmentTimestamp: transcription.segments.first?.timestamp)

                                if result.isFinal {
                                    var confidence: Float = 0.0
                                    if !transcription.segments.isEmpty {
                                        for segment in transcription.segments {
                                            confidence += segment.confidence
                                        }
                                        confidence /= Float(transcription.segments.count)
                                    }
                                    subscriber.putNext(TranscriptionResult(text: combined, confidence: confidence, isFinal: true))
                                    subscriber.putCompletion()
                                }
                            } else {
                                print("transcribeAudio: locale: \(locale), error: \(String(describing: error))")

                                let combined = accumulator.combinedText()
                                if combined.isEmpty {
                                    subscriber.putNext(nil)
                                } else {
                                    subscriber.putNext(TranscriptionResult(text: combined, confidence: 0.0, isFinal: true))
                                }
                                subscriber.putCompletion()
                            }
                        })

                        disposable.set(ActionDisposable {
                            task.cancel()
                        })
                    @unknown default:
                        subscriber.putNext(nil)
                        subscriber.putCompletion()
                    }
                }
            }
        } else {
            subscriber.putNext(nil)
            subscriber.putCompletion()
        }
        
        return disposable
    }
    |> runOn(.mainQueue())
}

public struct LocallyTranscribedAudio {
    public var text: String
    public var isFinal: Bool
}

public func transcribeAudio(path: String, appLocale: String) -> Signal<LocallyTranscribedAudio?, NoError> {
    var signals: [Signal<TranscriptionResult?, NoError>] = []
    var locales: [String] = []
    if !locales.contains(Locale.current.identifier) {
        locales.append(Locale.current.identifier)
    }
    if locales.isEmpty {
        locales.append("en-US")
    }
    for locale in locales {
        signals.append(transcribeAudio(path: path, locale: locale))
    }
    var resultSignal: Signal<[TranscriptionResult?], NoError> = .single([])
    for signal in signals {
        resultSignal = resultSignal |> mapToSignal { result -> Signal<[TranscriptionResult?], NoError> in
            return signal |> map { next in
                return result + [next]
            }
        }
    }
    
    return resultSignal
    |> map { results -> LocallyTranscribedAudio? in
        let sortedResults = results.compactMap({ $0 }).sorted(by: { lhs, rhs in
            return lhs.confidence > rhs.confidence
        })
        return sortedResults.first.flatMap { result -> LocallyTranscribedAudio in
            return LocallyTranscribedAudio(text: result.text, isFinal: result.isFinal)
        }
    }
}
