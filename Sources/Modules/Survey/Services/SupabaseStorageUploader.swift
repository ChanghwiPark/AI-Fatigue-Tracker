import Foundation

/// Supabase Storage 비동기 업로드 관리자
/// - 캡처 이미지를 로컬에 영구 보관함과 동시에 Supabase Storage 버킷에 안전하게 업로드 시도
public final class SupabaseStorageUploader {
    public static let shared = SupabaseStorageUploader()

    private init() {}

    /// 캡처된 로컬 이미지 파일을 Supabase Storage에 업로드
    /// - Parameters:
    ///   - localPath: 로컬 이미지 파일 경로
    ///   - completion: 업로드 성공 여부 및 원격 Storage 키/경로 콜백
    public func uploadScreenshot(localPath: String, completion: @escaping (Bool, String?) -> Void) {
        guard FileManager.default.fileExists(atPath: localPath) else {
            completion(false, nil)
            return
        }

        let baseURLString = Config.SupabaseConfig.projectURL
        let anonKey = Config.SupabaseConfig.anonKey
        let bucket = Config.SupabaseConfig.screenshotBucket

        // placeholder URL인 경우 업로드 건너뛰고 로컬 경로 유지
        if baseURLString.contains("your-project-id") || anonKey.contains("your-anon-key") {
            print("[SupabaseStorage] Supabase 설정이 아직 기본 placeholder 상태입니다. 로컬에만 보관합니다.")
            completion(true, "local_only:\(localPath)")
            return
        }

        let fileURL = URL(fileURLWithPath: localPath)
        let filename = fileURL.lastPathComponent

        // Supabase Storage Upload API: POST /storage/v1/object/{bucket}/{filename}
        guard let requestURL = URL(string: "\(baseURLString)/storage/v1/object/\(bucket)/\(filename)") else {
            completion(false, nil)
            return
        }

        guard let imageData = try? Data(contentsOf: fileURL) else {
            completion(false, nil)
            return
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("image/png", forHTTPHeaderField: "Content-Type")
        request.httpBody = imageData

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("[SupabaseStorage] 업로드 네트워크 에러 (로컬 파일 유지): \(error.localizedDescription)")
                completion(false, nil)
                return
            }

            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                let storagePath = "\(bucket)/\(filename)"
                print("[SupabaseStorage] 스크린샷 업로드 성공: \(storagePath)")
                completion(true, storagePath)
            } else {
                print("[SupabaseStorage] 업로드 HTTP 응답 실패: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                completion(false, nil)
            }
        }.resume()
    }
}
