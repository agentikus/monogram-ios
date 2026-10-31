import Foundation
import Postbox
import SwiftSignalKit

func monogramGoogleTranslate(text: String, toLang: String) -> Signal<String, TranslationError> {
    return Signal { subscriber in
        guard var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single") else {
            subscriber.putError(.generic)
            return EmptyDisposable
        }
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: toLang),
            URLQueryItem(name: "dt", value: "t")
        ]
        guard let url = components.url, let encodedText = text.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics) else {
            subscriber.putError(.generic)
            return EmptyDisposable
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = "q=\(encodedText)".data(using: .utf8)
        
        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil, let json = try? JSONSerialization.jsonObject(with: data) as? [Any], let sentences = json.first as? [Any] else {
                subscriber.putError(.generic)
                return
            }
            var result = ""
            for case let sentence as [Any] in sentences {
                if let part = sentence.first as? String {
                    result += part
                }
            }
            if result.isEmpty {
                subscriber.putError(.generic)
            } else {
                subscriber.putNext(result)
                subscriber.putCompletion()
            }
        }
        task.resume()
        return ActionDisposable {
            task.cancel()
        }
    }
}
