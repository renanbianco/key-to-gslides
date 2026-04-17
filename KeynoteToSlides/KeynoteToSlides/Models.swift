// Models.swift
// Codable result types that mirror the JSON protocol defined in python/cli.py

import Foundation

// MARK: - check_fonts

struct CheckFontsResult: Decodable {
    /// Fonts found in the PPTX that Google Slides does not natively support.
    let unsupported: [String]
    /// Every font found anywhere in the file (slides, layouts, masters).
    let allFonts: [String]

    enum CodingKeys: String, CodingKey {
        case unsupported
        case allFonts = "all_fonts"
    }
}

// MARK: - replace_fonts

struct ReplaceFontsResult: Decodable {
    let outputPath: String
    enum CodingKeys: String, CodingKey {
        case outputPath = "output_path"
    }
}

// MARK: - has_videos

struct HasVideosResult: Decodable {
    let hasVideos: Bool
    /// Basenames of embedded video files (e.g. ["clip.mp4", "intro.mov"]).
    let videoNames: [String]
    enum CodingKeys: String, CodingKey {
        case hasVideos  = "has_videos"
        case videoNames = "video_names"
    }
}

// MARK: - compress_pptx

struct CompressResult: Decodable {
    let outputPath: String
    let originalSize: Int
    let finalSize: Int
    /// Basenames of video files that were stripped to meet the size limit.
    let videosStripped: [String]
    /// False if even maximum compression didn't bring the file under 95 MB.
    let underLimit: Bool

    enum CodingKeys: String, CodingKey {
        case outputPath    = "output_path"
        case originalSize  = "original_size"
        case finalSize     = "final_size"
        case videosStripped = "videos_stripped"
        case underLimit    = "under_limit"
    }

    var savedBytes: Int { originalSize - finalSize }
    var savedMB: Double { Double(savedBytes) / 1_048_576 }
    var finalMB: Double { Double(finalSize) / 1_048_576 }
}

// MARK: - Progress

struct PythonProgress: Sendable {
    let done: Int
    let total: Int
    let message: String

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(done) / Double(total)
    }
}
