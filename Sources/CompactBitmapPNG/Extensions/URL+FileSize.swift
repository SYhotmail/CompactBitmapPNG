//
//  URL+FileSize.swift
//  CompactBitmapPNG
//
//  Created by Siarhei Yakushevich on 08/07/2026.
//
import Foundation

extension URL {
    func fileSizeInBytes(fileManager: FileManager = .default) throws -> UInt64? {
        guard isFileURL else { return nil }

        let attributes = try fileManager.attributesOfItem(atPath: path)
        return (attributes[.size] as? NSNumber)?.uint64Value
    }
}
