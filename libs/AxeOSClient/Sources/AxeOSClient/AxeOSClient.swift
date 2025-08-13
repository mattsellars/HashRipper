
import Foundation

public enum AxeOSClientError: Error {
    case deviceResponseError(String)
    case unknownError(String)
    case fileNotFound(String)
    case invalidFirmwareFile(String)
    case unauthorized(String)
}


public class AxeOSClient: Identifiable {
    private var urlSession: URLSession

    public var id: String { deviceIpAddress }
    
    public let deviceIpAddress: String
    
    let baseURL: URL

    public init(deviceIpAddress: String, urlSession: URLSession) {
        self.baseURL = URL(string: "http://\(deviceIpAddress)")!
        self.deviceIpAddress = deviceIpAddress
        self.urlSession = urlSession
    }

    public func configureURLSession(_ urlSession: URLSession) {
        self.urlSession = urlSession
    }

    public func restartClient() async -> Result<Bool, AxeOSClientError> {
        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("/api/system/restart"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.unknownError("Unknown/Unexpected response type from miner: \(String(describing: response))"))
            }

            guard
                httpResponse.statusCode == 200
            else {
                return .failure(.deviceResponseError(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)))
            }

            print("Issued restart to miner")
            return .success(true)
        } catch let error {
            return .failure(.unknownError(String(describing: error)))
        }
    }

    public func getSystemInfo() async -> Result<AxeOSDeviceInfo, Error> {
        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("/api/system/info"))
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               httpResponse.value(forHTTPHeaderField: "Content-Type") == "application/json"
            else {
                return .failure(
                    AxeOSClientError.deviceResponseError(
                        "Request failed with response: \(String(describing: response))"
                    )
                )
            }

            return try .success(JSONDecoder().decode(AxeOSDeviceInfo.self, from: data))
        } catch let error {
            return .failure(error)
        }
    }

    public func updateSystemSettings(
        settings: MinerSettings
    ) async -> Result<Bool, AxeOSClientError> {
        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("/api/system"))
            request.httpMethod = "PATCH"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(settings)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.unknownError("Unknown/Unexpected response type from miner: \(String(describing: response))"))
            }

            guard (200..<300).contains(http.statusCode) else {
                return .failure(.deviceResponseError(HTTPURLResponse.localizedString(forStatusCode: http.statusCode)))
            }
            return .success(true)

        } catch let error {
            return .failure(.unknownError(String(describing: error)))
        }
    }
    
    /// Upload firmware binary file to the miner via OTA update
    /// - Parameters:
    ///   - fileURL: Local file URL to the firmware binary (.bin file)
    ///   - progressCallback: Optional callback for upload progress (0.0 to 1.0)
    /// - Returns: Result indicating success or failure
    public func uploadFirmware(from fileURL: URL, progressCallback: ((Double) -> Void)? = nil) async -> Result<Bool, AxeOSClientError> {
        return await uploadOTAFile(from: fileURL, endpoint: "/api/system/OTA", fileType: "firmware", progressCallback: progressCallback)
    }
    
    /// Upload web interface files to the miner via OTA update
    /// - Parameters:
    ///   - fileURL: Local file URL to the web interface binary (.bin file)
    ///   - progressCallback: Optional callback for upload progress (0.0 to 1.0)
    /// - Returns: Result indicating success or failure
    public func uploadWebInterface(from fileURL: URL, progressCallback: ((Double) -> Void)? = nil) async -> Result<Bool, AxeOSClientError> {
        return await uploadOTAFile(from: fileURL, endpoint: "/api/system/OTAWWW", fileType: "web interface", progressCallback: progressCallback)
    }
    
    /// Generic OTA file upload method
    /// - Parameters:
    ///   - fileURL: Local file URL to upload
    ///   - endpoint: API endpoint (/api/system/OTA or /api/system/OTAWWW)
    ///   - fileType: Human-readable file type for error messages
    ///   - progressCallback: Optional callback for upload progress (0.0 to 1.0)
    /// - Returns: Result indicating success or failure
    private func uploadOTAFile(from fileURL: URL, endpoint: String, fileType: String, progressCallback: ((Double) -> Void)? = nil) async -> Result<Bool, AxeOSClientError> {
        do {
            // Verify file exists
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return .failure(.fileNotFound("File not found at path: \(fileURL.path)"))
            }
            
            // Read file data
            let fileData = try Data(contentsOf: fileURL)
            
            // Create request
            var request = URLRequest(url: baseURL.appendingPathComponent(endpoint))
            request.httpMethod = "POST"
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.setValue("\(fileData.count)", forHTTPHeaderField: "Content-Length")
            request.httpBody = fileData
            
            // Set timeout for potentially long upload
            request.timeoutInterval = 120.0
            
            // If progress callback provided, use upload task with progress tracking
            if let progressCallback = progressCallback {
                return await uploadWithProgress(request: request, fileType: fileType, progressCallback: progressCallback)
            } else {
                // Use simple data task if no progress needed
                let (_, response) = try await urlSession.data(for: request)
                return handleUploadResponse(response: response, fileType: fileType)
            }
            
        } catch let error {
            return .failure(.unknownError("Failed to upload \(fileType): \(String(describing: error))"))
        }
    }
    
    /// Upload with progress tracking using URLSessionUploadTask
    private func uploadWithProgress(request: URLRequest, fileType: String, progressCallback: @escaping (Double) -> Void) async -> Result<Bool, AxeOSClientError> {
        return await withCheckedContinuation { continuation in
            guard let httpBody = request.httpBody else {
                continuation.resume(returning: .failure(.unknownError("No request body data")))
                return
            }
            
            let delegate = OTAUploadDelegate(
                fileType: fileType,
                progressCallback: progressCallback,
                completion: { result in
                    continuation.resume(returning: result)
                }
            )
            
            // Create a separate session with our delegate
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 120.0
            let uploadSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            
            var uploadRequest = request
            uploadRequest.httpBody = nil // Remove body since we'll provide it as Data parameter
            
            let task = uploadSession.uploadTask(with: uploadRequest, from: httpBody)
//            delegate.configure(with: task, fileType: fileType, deviceIP: deviceIpAddress)
            task.resume()
        }
    }
    
    /// Handle upload response for simple uploads without progress
    private func handleUploadResponse(response: URLResponse, fileType: String) -> Result<Bool, AxeOSClientError> {
        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.unknownError("Unknown/Unexpected response type from miner: \(String(describing: response))"))
        }
        
        switch httpResponse.statusCode {
        case 200:
            print("Successfully uploaded \(fileType) to miner at \(deviceIpAddress)")
            return .success(true)
        case 400:
            return .failure(.invalidFirmwareFile("Invalid \(fileType) file"))
        case 401:
            return .failure(.unauthorized("Unauthorized - Client not in allowed network range"))
        case 500:
            return .failure(.deviceResponseError("Internal server error during \(fileType) upload"))
        default:
            return .failure(.deviceResponseError("Upload failed with status code: \(httpResponse.statusCode) - \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))"))
        }
    }
}

/// URLSessionTaskDelegate for handling upload progress
private class OTAUploadDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let progressCallback: (Double) -> Void
    private let completion: (Result<Bool, AxeOSClientError>) -> Void
    private var fileType: String
    
    init(fileType: String, progressCallback: @escaping (Double) -> Void, completion: @escaping (Result<Bool, AxeOSClientError>) -> Void) {
        self.fileType = fileType
        self.progressCallback = progressCallback
        self.completion = completion
        super.init()
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        DispatchQueue.main.async {
            self.progressCallback(progress)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            session.invalidateAndCancel()
        }
        
        if let error = error {
            DispatchQueue.main.async {
                self.completion(.failure(.unknownError("Upload failed: \(error.localizedDescription)")))
            }
            return
        }
        
        guard let httpResponse = task.response as? HTTPURLResponse else {
            DispatchQueue.main.async {
                self.completion(.failure(.unknownError("Unknown/Unexpected response type")))
            }
            return
        }
        
        let result: Result<Bool, AxeOSClientError>
        switch httpResponse.statusCode {
        case 200:
//            print("Successfully uploaded \(fileType) to miner at \(deviceIP)")
            result = .success(true)
        case 400:
            result = .failure(.invalidFirmwareFile("Invalid \(fileType) file"))
        case 401:
            result = .failure(.unauthorized("Unauthorized - Client not in allowed network range"))
        case 500:
            result = .failure(.deviceResponseError("Internal server error during \(fileType) upload"))
        default:
            result = .failure(.deviceResponseError("Upload failed with status code: \(httpResponse.statusCode) - \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))"))
        }
        
        DispatchQueue.main.async {
            self.completion(result)
        }
    }
}

/// Miner device settings returned by /api/system
public struct MinerSettings: Codable, Equatable {
    // MARK: ‑ Stratum
    let stratumURL: String?
    let fallbackStratumURL: String?
    let stratumUser: String?
    let stratumPassword: String?          // write‑only in spec — may be absent on GET
    let fallbackStratumUser: String?
    let fallbackStratumPassword: String?  // write‑only
    let stratumPort: Int?
    let fallbackStratumPort: Int?

    // MARK: ‑ Network / Wi‑Fi
    let ssid: String?
    let wifiPass: String?                 // write‑only
    let hostname: String?

    // MARK: ‑ ASIC & fan tuning
    let coreVoltage: Int?
    let frequency: Int?
    let flipscreen: Int?          // 0 | 1
    let overheatMode: Int?        // 0
    let overclockEnabled: Int?    // 0 | 1
    let invertscreen: Int?        // 0 | 1
    let invertfanpolarity: Int?   // 0 | 1
    let autofanspeed: Int?        // 0 | 1
    let fanspeed: Int?            // 0‑100 %

    // Map JSON keys that don’t follow Swift’s camelCase conventions
    enum CodingKeys: String, CodingKey {
        case stratumURL
        case fallbackStratumURL
        case stratumUser
        case stratumPassword
        case fallbackStratumUser
        case fallbackStratumPassword
        case stratumPort
        case fallbackStratumPort
        case ssid
        case wifiPass
        case hostname
        case coreVoltage
        case frequency
        case flipscreen
        case overheatMode        = "overheat_mode"
        case overclockEnabled
        case invertscreen
        case invertfanpolarity
        case autofanspeed
        case fanspeed
    }

    public init(
        stratumURL: String?,
        fallbackStratumURL: String?,
        stratumUser: String?,
        stratumPassword: String?,
        fallbackStratumUser: String?,
        fallbackStratumPassword: String?, stratumPort: Int?, fallbackStratumPort: Int?, ssid: String?, wifiPass: String?, hostname: String?, coreVoltage: Int?, frequency: Int?, flipscreen: Int?, overheatMode: Int?, overclockEnabled: Int?, invertscreen: Int?, invertfanpolarity: Int?, autofanspeed: Int?, fanspeed: Int?) {
        self.stratumURL = stratumURL
        self.fallbackStratumURL = fallbackStratumURL
        self.stratumUser = stratumUser
        self.stratumPassword = stratumPassword
        self.fallbackStratumUser = fallbackStratumUser
        self.fallbackStratumPassword = fallbackStratumPassword
        self.stratumPort = stratumPort
        self.fallbackStratumPort = fallbackStratumPort
        self.ssid = ssid
        self.wifiPass = wifiPass
        self.hostname = hostname
        self.coreVoltage = coreVoltage
        self.frequency = frequency
        self.flipscreen = flipscreen
        self.overheatMode = overheatMode
        self.overclockEnabled = overclockEnabled
        self.invertscreen = invertscreen
        self.invertfanpolarity = invertfanpolarity
        self.autofanspeed = autofanspeed
        self.fanspeed = fanspeed
    }
}

public struct StratumAccountInfo {
    let user: String
    let password: String
    let url: String
    let port: Int

    init(user: String, password: String, url: String, port: Int) {
        self.user = user
        self.password = password
        self.url = url
        self.port = port
    }
}
