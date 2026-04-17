// DriveUploader.swift
import Foundation

enum UploadError: LocalizedError {
    case initiationFailed(Int)
    case noUploadURI
    case chunkFailed(Int, String)
    case sessionExpired
    case tooLarge
    case quotaExceeded
    case noFileID

    var errorDescription: String? {
        switch self {
        case .initiationFailed(let code): return "Could not start upload session (HTTP \(code))."
        case .noUploadURI: return "Google Drive did not return an upload URI."
        case .chunkFailed(let code, let msg): return "Upload failed (HTTP \(code)): \(msg)"
        case .sessionExpired: return "Upload session expired. Please try again."
        case .tooLarge: return "File is too large for Google to convert (limit: 100 MB). Try splitting the presentation."
        case .quotaExceeded: return "Your Google Drive storage is full. Free up space at drive.google.com and try again."
        case .noFileID: return "Upload completed but Google Drive returned no file ID."
        }
    }
}

struct DriveUploader {

    private static let pptxMIME  = "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    private static let slidesMIME = "application/vnd.google-apps.presentation"
    private static let uploadURL  = "https://www.googleapis.com/upload/drive/v3/files"
    private static let chunkSize  = 5 * 1024 * 1024  // 5 MB

    static func upload(
        pptxPath: String,
        title: String,
        accessToken: String,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {

        let fileData = try Data(contentsOf: URL(fileURLWithPath: pptxPath))
        let fileSize = fileData.count

        // 1. Initiate resumable session
        let uploadURI = try await initiateSession(title: title, fileSize: fileSize, accessToken: accessToken)

        // 2. Upload in chunks
        var offset = 0
        var resultURL: URL? = nil

        while offset < fileSize {
            let chunkEnd = min(offset + chunkSize - 1, fileSize - 1)
            let chunk = fileData[offset...chunkEnd]

            var req = URLRequest(url: uploadURI)
            req.httpMethod = "PUT"
            req.setValue(pptxMIME, forHTTPHeaderField: "Content-Type")
            req.setValue(String(chunk.count), forHTTPHeaderField: "Content-Length")
            req.setValue("bytes \(offset)-\(chunkEnd)/\(fileSize)", forHTTPHeaderField: "Content-Range")
            req.httpBody = Data(chunk)

            var lastError: Error? = nil
            var chunkDone = false

            for attempt in 0..<5 {
                do {
                    let (data, response) = try await URLSession.shared.data(for: req)
                    let http = response as! HTTPURLResponse

                    switch http.statusCode {
                    case 200, 201:
                        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                        if let link = json["webViewLink"] as? String, let url = URL(string: link) {
                            resultURL = url
                        } else if let id = json["id"] as? String {
                            resultURL = URL(string: "https://docs.google.com/presentation/d/\(id)/edit")
                        }
                        offset = fileSize
                        chunkDone = true

                    case 308:
                        offset = chunkEnd + 1
                        onProgress(Double(offset) / Double(fileSize))
                        chunkDone = true

                    case 413:
                        throw UploadError.tooLarge

                    case 429:
                        let wait = Int(http.value(forHTTPHeaderField: "Retry-After") ?? "2") ?? 2
                        try await Task.sleep(for: .seconds(Double(wait)))
                        lastError = UploadError.chunkFailed(429, "Rate limited")

                    case 500, 502, 503, 504:
                        try await Task.sleep(for: .seconds(Double(1 << attempt)))
                        lastError = UploadError.chunkFailed(http.statusCode, "Transient server error")

                    case 404:
                        throw UploadError.sessionExpired

                    default:
                        let msg = String(data: data, encoding: .utf8) ?? ""
                        // Check for quota error
                        if msg.contains("storageQuotaExceeded") { throw UploadError.quotaExceeded }
                        throw UploadError.chunkFailed(http.statusCode, msg.prefix(200).description)
                    }

                    if chunkDone { break }

                } catch let e as UploadError { throw e }
                  catch { lastError = error }
            }

            if !chunkDone {
                throw lastError ?? UploadError.chunkFailed(0, "Upload failed after 5 attempts")
            }
        }

        guard let url = resultURL else { throw UploadError.noFileID }
        return url
    }

    private static func initiateSession(title: String, fileSize: Int, accessToken: String) async throws -> URL {
        guard var comps = URLComponents(string: uploadURL) else { fatalError() }
        comps.queryItems = [
            .init(name: "uploadType", value: "resumable"),
            .init(name: "fields", value: "id,webViewLink"),
        ]

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue(pptxMIME, forHTTPHeaderField: "X-Upload-Content-Type")
        req.setValue(String(fileSize), forHTTPHeaderField: "X-Upload-Content-Length")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": title, "mimeType": slidesMIME])

        let (_, response) = try await URLSession.shared.data(for: req)
        let http = response as! HTTPURLResponse
        guard (200...299).contains(http.statusCode) else { throw UploadError.initiationFailed(http.statusCode) }
        guard let location = http.value(forHTTPHeaderField: "Location"), let uri = URL(string: location) else {
            throw UploadError.noUploadURI
        }
        return uri
    }
}
