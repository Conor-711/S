import Foundation
import AppKit

/// Utility for comparing images using strict pixel-level equality
struct ImageDiffer: Sendable {
    
    /// Compare two images for strict pixel equality
    /// - Parameters:
    ///   - image1: First NSImage to compare
    ///   - image2: Second NSImage to compare
    /// - Returns: true if images are identical, false otherwise
    static func areImagesEqual(_ image1: NSImage?, _ image2: NSImage?) -> Bool {
        guard let img1 = image1, let img2 = image2 else {
            return image1 == nil && image2 == nil
        }
        
        guard let data1 = imageToData(img1),
              let data2 = imageToData(img2) else {
            return false
        }
        
        return data1 == data2
    }
    
    /// Convert NSImage to PNG Data for comparison
    /// - Parameter image: The NSImage to convert
    /// - Returns: PNG data representation of the image
    static func imageToData(_ image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData
    }
    
    /// Check if an image has changed compared to previous data
    /// - Parameters:
    ///   - newImage: The new image to check
    ///   - previousData: The previous image's data
    /// - Returns: true if the image has changed, false if identical
    static func hasImageChanged(_ newImage: NSImage, comparedTo previousData: Data?) -> Bool {
        guard let previousData = previousData else {
            return true
        }
        
        guard let newData = imageToData(newImage) else {
            return true
        }
        
        return newData != previousData
    }
}
