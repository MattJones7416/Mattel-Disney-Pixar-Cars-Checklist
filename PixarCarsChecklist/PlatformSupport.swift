// PlatformSupport.swift
import SwiftUI

#if os(iOS) || targetEnvironment(macCatalyst)
import UIKit
public typealias PlatformImage = UIImage
#else
import AppKit
public typealias PlatformImage = NSImage
#endif

// Convert raw Data -> platform image
public func platformImage(from data: Data) -> PlatformImage? {
    #if os(iOS) || targetEnvironment(macCatalyst)
    UIImage(data: data)
    #else
    NSImage(data: data)
    #endif
}

// Convert platform image -> SwiftUI Image
public func swiftUIImage(from image: PlatformImage) -> Image {
    #if os(iOS) || targetEnvironment(macCatalyst)
    Image(uiImage: image)
    #else
    Image(nsImage: image)
    #endif
}
